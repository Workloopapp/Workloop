import { createClient } from "@supabase/supabase-js";
import {
  isValidWaitlistEmail,
  normalizeWaitlistEmail,
  waitlistOutcomeResponse,
  waitlistSource,
} from "./validation.ts";
import {
  drainWaitlistWelcomeEmails,
  waitlistWelcomeEmailConfig,
} from "../_shared/waitlist_welcome_email.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
  const configuredSalt = Deno.env.get("WAITLIST_RATE_LIMIT_SALT") ?? "";
  if (supabaseUrl.length === 0 || serviceRoleKey.length < 32) {
    return response(500, { error: "Waitlist service is not configured" });
  }
  const rateLimitSalt = configuredSalt.length >= 32
    ? configuredSalt
    : await sha256(`workloop-waitlist-rate-limit:${serviceRoleKey}`);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }

  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return response(400, { error: "Invalid request body" });
  }

  if (typeof payload.website === "string" && payload.website.trim()) {
    return response(200, { ok: true });
  }

  if (!payload || Array.isArray(payload) || payload.consent !== true) {
    return response(400, { error: "Please agree to receive launch updates" });
  }

  const email = normalizeWaitlistEmail(payload.email);
  if (!isValidWaitlistEmail(email)) {
    return response(400, { error: "Enter a valid email address" });
  }

  const source = waitlistSource(payload.source);
  const subjectHash = await sha256(`${email}:${rateLimitSalt}`);
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.rpc("join_launch_waitlist", {
    p_email: email,
    p_subject_hash: subjectHash,
    p_source: source,
  });
  if (error) {
    console.error("waitlist_join_failed", { code: error.code });
    return response(500, { error: "Could not join the waitlist" });
  }

  const mapped = waitlistOutcomeResponse(data);
  if (mapped.status === 200) {
    const emailConfig = waitlistWelcomeEmailConfig();
    if (emailConfig !== null) {
      try {
        await drainWaitlistWelcomeEmails({
          client: supabase,
          config: emailConfig,
          limit: 20,
        });
      } catch (_) {
        // The database transaction already accepted the signup. The scheduled
        // drain retries without exposing recipient data in logs.
        console.error("waitlist_welcome_email_immediate_drain_failed");
      }
    }
  }
  return response(mapped.status, mapped.body);
});
