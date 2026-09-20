import { createClient } from "@supabase/supabase-js";
import { Webhook } from "svix";

type Json = Record<string, unknown>;

const supportedEvents = new Set([
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.failed",
  "email.opened",
  "email.clicked",
  "email.bounced",
  "email.complained",
  "email.scheduled",
  "email.suppressed",
]);

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function objectValue(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function stringValue(value: unknown, maxLength = 160) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET") ?? "";
  if (
    !supabaseUrl || serviceRoleKey.length < 32 ||
    !webhookSecret.startsWith("whsec_")
  ) {
    return jsonResponse(503, { error: "Webhook is not configured" });
  }

  const svixId = stringValue(req.headers.get("svix-id"));
  const svixTimestamp = stringValue(req.headers.get("svix-timestamp"));
  const svixSignature = stringValue(req.headers.get("svix-signature"), 1000);
  if (!svixId || !svixTimestamp || !svixSignature) {
    return jsonResponse(400, { error: "Missing signature headers" });
  }

  const rawBody = await req.text();
  let event: Json;
  try {
    const verified = await Promise.resolve(
      new Webhook(webhookSecret).verify(rawBody, {
        "svix-id": svixId,
        "svix-timestamp": svixTimestamp,
        "svix-signature": svixSignature,
      }),
    );
    event = objectValue(verified);
  } catch (_) {
    return jsonResponse(400, { error: "Invalid signature" });
  }

  const eventType = stringValue(event.type, 80);
  if (!supportedEvents.has(eventType)) {
    return jsonResponse(200, { received: true, ignored: true });
  }

  const data = objectValue(event.data);
  const providerMessageId = stringValue(data.email_id);
  const occurredAt = new Date(stringValue(event.created_at, 80));
  if (!providerMessageId || Number.isNaN(occurredAt.getTime())) {
    return jsonResponse(400, { error: "Invalid event" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: inserted, error } = await serviceClient.rpc(
    "record_resend_webhook_event",
    {
      p_svix_id: svixId,
      p_provider_message_id: providerMessageId,
      p_event_type: eventType,
      p_occurred_at: occurredAt.toISOString(),
    },
  );
  if (error) {
    console.error("resend_webhook_record_failed", { code: error.code });
    return jsonResponse(500, { error: "Could not record event" });
  }

  // Stop the optional learning series after a provider bounce or complaint.
  // Retry this even on a duplicate webhook in case the prior suppression failed.
  if (
    ["email.bounced", "email.complained", "email.suppressed"].includes(
      eventType,
    )
  ) {
    const suppression = await serviceClient.rpc("suppress_learning_email", {
      p_provider_message_id: providerMessageId,
    });
    if (suppression.error) {
      return jsonResponse(500, { error: "Could not update email preferences" });
    }
    const events = await serviceClient.rpc("suppress_customer_event_email", {
      p_provider_id: providerMessageId,
    });
    if (events.error) {
      return jsonResponse(500, {
        error: "Could not update delivery suppression",
      });
    }
    const reminders = await serviceClient.rpc("suppress_booking_reminders", {
      p_provider_message_id: providerMessageId,
    });
    if (reminders.error) {
      return jsonResponse(500, {
        error: "Could not update reminder preferences",
      });
    }
  }

  return jsonResponse(200, {
    received: true,
    duplicate: inserted !== true,
  });
});
