import { createClient } from "@supabase/supabase-js";
import twilio from "twilio";
import {
  bookingSmsCapabilities,
  bookingSmsWebhookConfig,
  type SmsRpcClient,
} from "../_shared/booking_sms.ts";
import { handleBookingSmsWebhook } from "../_shared/booking_sms_webhook.ts";

const env = (name: string) => Deno.env.get(name);
const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (request: Request) => {
  const url = new URL(request.url);
  const action = url.searchParams.get("action");
  const supabaseUrl = env("SUPABASE_URL") ?? "";
  const publicKey = env("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !publicKey) {
    return json(503, { error: "SMS service unavailable" });
  }
  if (action === "status" || action === "inbound") {
    const config = bookingSmsWebhookConfig(env);
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!config || serviceKey.length < 32) {
      return json(503, { error: "SMS provider is not configured" });
    }
    try {
      return await handleBookingSmsWebhook({
        request,
        config,
        client: createClient(supabaseUrl, serviceKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        }) as unknown as SmsRpcClient,
        validateSignature: twilio.validateRequest,
      });
    } catch {
      return json(500, { error: "Could not record SMS provider update" });
    }
  }
  if (request.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json(401, { error: "Sign in required" });
  }
  const client = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user || data.user.is_anonymous) {
    return json(401, { error: "Sign in required" });
  }
  try {
    const raw = await request.text();
    if (raw.length > 256 || JSON.parse(raw).action !== "capabilities") {
      return json(400, { error: "Unknown SMS action" });
    }
  } catch {
    return json(400, { error: "Invalid SMS request" });
  }
  return json(200, bookingSmsCapabilities(env));
});
