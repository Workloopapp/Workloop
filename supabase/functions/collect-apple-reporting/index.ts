import { createClient } from "jsr:@supabase/supabase-js@2.110.5";
import {
  type BetaTesterResource,
  type BetaUsageResource,
  buildTestFlightMetrics,
  createAppStoreConnectJwt,
  fetchAppleCollection,
} from "../_shared/apple_reporting.ts";

type Json = Record<string, unknown>;

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function requiredSecret(name: string) {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

function safeErrorCode(error: unknown) {
  const message = error instanceof Error ? error.message : "unknown_error";
  return /^[a-z0-9_]+$/u.test(message)
    ? message.slice(0, 80)
    : "collector_failed";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const startedAt = new Date();
  const supabaseUrl = requiredSecret("SUPABASE_URL");
  const serviceRoleKey = requiredSecret("SUPABASE_SERVICE_ROLE_KEY");
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const requestToken = req.headers.get("x-workloop-reporting-token") ?? "";
  const { data: authorized, error: authError } = await serviceClient.rpc(
    "authorize_apple_reporting_collector",
    { p_token: requestToken },
  );
  if (authError || authorized !== true) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  try {
    const issuerId = requiredSecret("APPLE_APP_STORE_CONNECT_ISSUER_ID");
    const keyId = requiredSecret("APPLE_TESTFLIGHT_KEY_ID");
    const privateKeyPem = requiredSecret("APPLE_TESTFLIGHT_PRIVATE_KEY");
    const appId = requiredSecret("APPLE_APP_ID");
    const token = await createAppStoreConnectJwt({
      issuerId,
      keyId,
      privateKeyPem,
    });
    const encodedAppId = encodeURIComponent(appId);

    const testers = await fetchAppleCollection<BetaTesterResource>({
      initialUrl:
        `https://api.appstoreconnect.apple.com/v1/betaTesters?filter%5Bapps%5D=${encodedAppId}&fields%5BbetaTesters%5D=state,inviteType&limit=200`,
      token,
    });
    const usages = await fetchAppleCollection<BetaUsageResource>({
      initialUrl:
        `https://api.appstoreconnect.apple.com/v1/apps/${encodedAppId}/metrics/betaTesterUsages?period=P365D&limit=200&groupBy=betaTesters`,
      token,
    });
    const metrics = buildTestFlightMetrics({
      metricDate: startedAt.toISOString().slice(0, 10),
      testers,
      usages,
    });

    const { data: recordsWritten, error: ingestError } = await serviceClient
      .rpc(
        "ingest_reporting_metrics",
        {
          p_source: "testflight",
          p_metrics: metrics,
          p_started_at: startedAt.toISOString(),
        },
      );
    if (ingestError) throw new Error("reporting_ingest_failed");

    return jsonResponse(200, {
      collected: true,
      source: "testflight",
      records_written: recordsWritten,
    });
  } catch (error) {
    const errorCode = safeErrorCode(error);
    await serviceClient.rpc("record_reporting_ingestion_run", {
      p_source: "testflight",
      p_status: "failed",
      p_started_at: startedAt.toISOString(),
      p_records_written: 0,
      p_error_code: errorCode,
      p_error_message: "Apple reporting import failed",
    });
    console.error("apple_reporting_collection_failed", { code: errorCode });
    return jsonResponse(502, {
      error: "Apple reporting import failed",
      code: errorCode,
    });
  }
});
