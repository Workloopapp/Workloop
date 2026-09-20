import { createClient } from "@supabase/supabase-js";
import {
  SubscriptionBodyError,
  subscriptionRequestBody,
} from "./request_body.ts";
import {
  subscriptionRecord,
  verifyNotification,
  verifyTransaction,
} from "./verification.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};
const reply = (status: number, data: unknown) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return reply(200, {});
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  let body: Record<string, unknown>;
  try {
    body = await subscriptionRequestBody(req);
  } catch (error) {
    if (error instanceof SubscriptionBodyError) {
      return reply(error.status, { error: error.message });
    }
    return reply(400, { error: "Invalid request" });
  }
  const url = Deno.env.get("SUPABASE_URL")!;
  const service = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const webhook = new URL(req.url).pathname.endsWith("/apple-notifications");
  try {
    if (webhook) {
      if (typeof body.signedPayload !== "string") {
        return reply(400, { error: "Signed notification required" });
      }
      const record = await verifyNotification(body.signedPayload);
      if (record) {
        const { error } = await service.rpc(
          "record_verified_store_subscription",
          { p: record },
        );
        if (error) {
          return reply(503, { error: "Could not save subscription update" });
        }
      }
      return reply(200, { received: true });
    }
    const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: {
        headers: { Authorization: req.headers.get("Authorization") ?? "" },
      },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError || !user) {
      return reply(401, { error: "Sign in again to verify your purchase" });
    }
    // Recheck the session and verified account, not merely an unexpired JWT.
    const { error: accessError } = await client.rpc("get_workloop_access");
    if (accessError) {
      return reply(401, { error: "An active verified account is required" });
    }
    if (body.platform !== "apple") {
      return reply(503, {
        error: "Google Play purchases are not available yet",
      });
    }
    if (
      typeof body.signedTransaction !== "string" ||
      body.signedTransaction.length > 60000
    ) return reply(400, { error: "Signed transaction required" });
    const transaction = await verifyTransaction(body.signedTransaction);
    const record = subscriptionRecord(transaction, user.id);
    const { error } = await service.rpc("record_verified_store_subscription", {
      p: record,
    });
    if (error) {
      return reply(409, {
        error:
          "Could not attach this purchase to your account. Contact support.",
      });
    }
    const { data: access, error: readError } = await client.rpc(
      "get_workloop_access",
    );
    if (readError) {
      return reply(503, {
        error: "Purchase saved. Refresh access to continue.",
      });
    }
    return reply(200, {
      verified: true,
      environment: record.environment,
      access,
    });
  } catch {
    // Never log receipts, app account tokens, authorisation headers or PII.
    return reply(400, {
      error:
        "The purchase could not be verified. Please restore purchases or try again.",
    });
  }
});
