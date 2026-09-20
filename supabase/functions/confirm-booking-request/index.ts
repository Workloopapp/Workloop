import { createClient } from "@supabase/supabase-js";
import {
  bookingConfirmationEmailConfig,
  BookingConfirmationRpcClient,
  drainBookingConfirmationEmails,
} from "../_shared/booking_confirmation_email.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function normaliseEmail(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isValidEmail(value: unknown): value is string {
  const email = normaliseEmail(value);
  return email.length >= 3 &&
    email.length <= 254 &&
    /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || serviceRoleKey.length < 32) {
    return response(500, { error: "Booking confirmation is not configured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }
  if (!isObject(body) || !isObject(body.payload)) {
    return response(400, { error: "A booking workflow payload is required" });
  }
  const payload = body.payload;
  const bookingRequestId = payload.booking_request_id;
  if (!isUuid(bookingRequestId)) {
    return response(400, { error: "A valid booking request is required" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return response(401, { error: "Unauthorized" });
  }

  const workspaceId = payload.workspace_id;
  if (!isUuid(workspaceId)) {
    return response(400, { error: "A valid workspace is required" });
  }
  const { data: storedRequest, error: requestError } = await userClient
    .from("booking_requests")
    .select("id, workspace_id, email")
    .eq("id", bookingRequestId)
    .eq("workspace_id", workspaceId)
    .maybeSingle();
  if (requestError) {
    return response(500, { error: "Could not verify booking request" });
  }
  if (!storedRequest) {
    return response(404, { error: "Booking request not found", code: "P0002" });
  }
  if (!isObject(payload.new_contact)) {
    return response(400, { error: "New client details are required" });
  }
  const storedRequestEmail = normaliseEmail(storedRequest.email);
  const submittedRequestEmail = isObject(payload.new_contact)
    ? normaliseEmail(payload.new_contact["email"])
    : "";
  const trustedEmail = isValidEmail(storedRequestEmail)
    ? storedRequestEmail
    : isValidEmail(submittedRequestEmail)
    ? submittedRequestEmail
    : "";

  if (
    !isValidEmail(storedRequestEmail) &&
    isValidEmail(trustedEmail)
  ) {
    await userClient
      .from("booking_requests")
      .update({ email: trustedEmail })
      .eq("id", bookingRequestId)
      .is("email", null);
  }

  // The public request email is authoritative when present; if it is absent we
  // accept the owner's explicit email input for legacy requests.
  const trustedPayload = {
    ...payload,
    new_contact: {
      ...payload.new_contact,
      email: isValidEmail(trustedEmail) ? trustedEmail : null,
    },
  };

  const { data: result, error: workflowError } = await userClient.rpc(
    "create_booking_workflow",
    { p_payload: trustedPayload },
  );
  if (workflowError) {
    const code = workflowError.code ?? "";
    const status = code === "42501"
      ? 403
      : ["23P01", "23505", "P0002"].includes(code)
      ? 409
      : 500;
    return response(status, {
      error: status === 500
        ? "Could not confirm booking request"
        : workflowError.message,
      code,
    });
  }

  const emailConfig = bookingConfirmationEmailConfig();
  if (emailConfig !== null) {
    try {
      await drainBookingConfirmationEmails({
        client: serviceClient as unknown as BookingConfirmationRpcClient,
        config: emailConfig,
        limit: 1,
        bookingRequestId,
      });
    } catch (_) {
      // The durable outbox remains authoritative. Do not turn a committed
      // booking into a false client-visible failure because delivery is down.
      console.error("booking_confirmation_email_drain_failed");
    }
  }

  const emailStatusResult = await serviceClient.rpc(
    "booking_confirmation_email_status",
    { p_booking_request_id: bookingRequestId },
  );
  const storedStatus = emailStatusResult.error
    ? "failed"
    : emailStatusResult.data;
  const emailStatus = storedStatus === "sent"
    ? "sent"
    : storedStatus === "failed"
    ? "failed"
    : storedStatus === "not_applicable"
    ? "not_applicable"
    : "pending";

  return response(200, {
    ok: true,
    result,
    confirmationEmail: { status: emailStatus },
  });
});
