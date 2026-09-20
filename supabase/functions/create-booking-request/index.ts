import { createClient } from "@supabase/supabase-js";
import {
  bestEffortPlatformIp,
  bookingRequestOutcomeResponse,
  bookingRequestValidationError,
  cleanAddOnIds,
  cleanServiceIds,
  nullableStringValue,
  parseRequestedInstant,
  resolveRequestToken,
  stringValue,
} from "./request_validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type BookingRequestPayload = {
  handle?: unknown;
  name?: unknown;
  phone?: unknown;
  email?: unknown;
  serviceId?: unknown;
  service_id?: unknown;
  serviceIds?: unknown;
  service_ids?: unknown;
  preferredTimeText?: unknown;
  preferred_time_text?: unknown;
  requestedFor?: unknown;
  requested_for?: unknown;
  requestedTimezone?: unknown;
  requested_timezone?: unknown;
  message?: unknown;
  website?: unknown;
  requestToken?: unknown;
  request_token?: unknown;
  addOnIds?: unknown;
  add_on_ids?: unknown;
};

const textEncoder = new TextEncoder();

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const configuredRateLimitSalt =
    Deno.env.get("BOOKING_REQUEST_RATE_LIMIT_SALT") ?? "";
  if (supabaseUrl.length === 0 || serviceRoleKey.length < 32) {
    return response(500, {
      error: "Booking request service is not configured",
    });
  }
  // Prefer a dedicated secret, but retain a secure, domain-separated fallback
  // so a missing optional secret cannot silently disable public bookings.
  const rateLimitSalt = configuredRateLimitSalt.length >= 32
    ? configuredRateLimitSalt
    : await sha256(`workloop-booking-rate-limit:${serviceRoleKey}`);

  let payload: BookingRequestPayload;
  try {
    payload = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }

  if (stringValue(payload.website, 120).length > 0) {
    return response(202, { ok: true });
  }

  const handle = stringValue(payload.handle, 80).toLowerCase();
  const name = stringValue(payload.name, 80);
  const phone = stringValue(payload.phone, 32);
  const email = typeof payload.email === "string"
    ? payload.email.trim().toLowerCase()
    : "";
  const preferredTimeText = nullableStringValue(
    payload.preferredTimeText ?? payload.preferred_time_text,
    160,
  );
  const requestedForInput = stringValue(
    payload.requestedFor ?? payload.requested_for,
    64,
  );
  const requestedFor = requestedForInput.length === 0
    ? null
    : parseRequestedInstant(payload.requestedFor ?? payload.requested_for);
  const requestedTimezone = stringValue(
    payload.requestedTimezone ?? payload.requested_timezone,
    64,
  );
  const hasRequestedFor = requestedForInput.length > 0;
  const hasRequestedTimezone = requestedTimezone.length > 0;
  const hasStructuredRequestedTime = hasRequestedFor && hasRequestedTimezone;
  const message = nullableStringValue(payload.message, 1000);
  const serviceId = stringValue(payload.serviceId ?? payload.service_id, 64);
  const serviceIds = cleanServiceIds(
    payload.serviceIds ?? payload.service_ids,
    serviceId,
  );
  if (
    serviceIds === null ||
    (serviceIds.length > 1 && !hasStructuredRequestedTime)
  ) {
    return response(400, {
      error: "Choose valid services and a requested date and time",
    });
  }
  const requestToken = resolveRequestToken(
    payload.requestToken ?? payload.request_token,
  );
  const addOnIds = cleanAddOnIds(payload.addOnIds ?? payload.add_on_ids);
  if (addOnIds === null) {
    return response(400, { error: "Invalid optional extras" });
  }
  const validationError = bookingRequestValidationError({
    handle,
    name,
    phone,
    email,
    serviceId,
    requestToken,
  });
  if (validationError !== null) {
    return response(400, { error: validationError });
  }
  if (
    hasRequestedFor !== hasRequestedTimezone ||
    (hasStructuredRequestedTime &&
      (requestedFor === null || Number.isNaN(requestedFor.getTime()) ||
        !/^(?:UTC|GMT|[A-Za-z_]+(?:\/[A-Za-z0-9_+\-]+)+)$/.test(
          requestedTimezone,
        )))
  ) {
    return response(400, {
      error: "A valid requested date and time is required",
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile, error: profileError } = await supabase
    .from("business_profiles")
    .select("workspace_id")
    .eq("handle", handle)
    .maybeSingle();

  if (profileError) return response(500, { error: "Could not load profile" });
  if (!profile) return response(404, { error: "Profile not found" });

  // Reject inactive owners before the final database insert-time check.
  const { data: member, error: memberError } = await supabase
    .rpc("is_public_workspace_active", {
      p_workspace_id: profile.workspace_id,
    });

  if (memberError) {
    return response(500, { error: "Could not load profile" });
  }
  if (member !== true) return response(404, { error: "Profile not found" });

  const sourceHash = await sha256(
    `${profile.workspace_id}:${
      bestEffortPlatformIp(req.headers)
    }:${rateLimitSalt}`,
  );

  // Keep the legacy service-role overload available while older TestFlight
  // builds are still in circulation. New clients always send the structured
  // instant and timezone and therefore use the exact-time overload.
  const rpcPayload = hasStructuredRequestedTime
    ? {
      p_workspace_id: profile.workspace_id,
      p_name: name,
      p_phone: phone,
      p_email: email,
      p_service_id: serviceId || null,
      p_preferred_time_text: preferredTimeText,
      p_requested_for: requestedFor!.toISOString(),
      p_requested_timezone: requestedTimezone,
      p_message: message,
      p_source_hash: sourceHash,
      p_request_token: requestToken,
      p_add_on_ids: addOnIds,
      ...(serviceIds.length > 1 ? { p_service_ids: serviceIds } : {}),
    }
    : {
      p_workspace_id: profile.workspace_id,
      p_name: name,
      p_phone: phone,
      p_email: email,
      p_service_id: serviceId || null,
      p_preferred_time_text: preferredTimeText,
      p_message: message,
      p_source_hash: sourceHash,
      p_request_token: requestToken,
    };
  const { data: result, error: createError } = await supabase.rpc(
    hasStructuredRequestedTime
      ? (serviceIds.length > 1
        ? "create_public_booking_request_v4"
        : "create_public_booking_request_v3")
      : "create_public_booking_request_v2",
    rpcPayload,
  );

  if (createError) {
    console.error("booking_request_rpc_failed", { code: createError.code });
    if (createError.code === "42501") {
      return response(404, { error: "Profile not found" });
    }
    if (createError.code === "22023") {
      return response(400, {
        error:
          "The requested date or time is no longer valid. Refresh and choose another time.",
      });
    }
    return response(500, { error: "Could not create request" });
  }

  const row = Array.isArray(result) ? result[0] : result;
  const outcome = typeof row?.outcome === "string" ? row.outcome : "";
  const mappedOutcome = bookingRequestOutcomeResponse(outcome);
  return response(mappedOutcome.status, mappedOutcome.body);
});
