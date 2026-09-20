import {
  type FcmPushConfig,
  fcmPushConfig,
  pushRetryAfterSeconds,
  sendFirebaseMessage,
} from "./push_delivery_fcm.ts";

type RpcError = { code?: string; message?: string };

export type PushDeliveryRpcClient = {
  rpc: (
    name: string,
    params?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: RpcError | null }>;
};

export type ApnsPushConfig = {
  teamId: string;
  keyId: string;
  bundleId: string;
  privateKeyPem: string;
  environment: "production" | "sandbox";
};

type PushDelivery = {
  delivery_id: string;
  delivery_lease_token: string;
  push_token_id: string;
  device_token: string;
  platform: string;
  apns_environment?: "production" | "sandbox" | null;
  notification_type: string;
  notification_title: string;
  notification_body: string;
  deep_link: string | null;
};

export type PushDeliveryOutcome = {
  outcome: "sent" | "retry" | "failed";
  providerMessageId?: string;
  errorCode?: string;
  disableToken: boolean;
  retryAfterSeconds?: number;
};

let cachedProviderToken: {
  value: string;
  expiresAt: number;
  configKey: string;
} | null = null;

export function apnsPushConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): ApnsPushConfig | null {
  const teamId = readEnv("APNS_TEAM_ID")?.trim() ?? "";
  const keyId = readEnv("APNS_KEY_ID")?.trim() ?? "";
  const bundleId = readEnv("APNS_BUNDLE_ID")?.trim() ?? "";
  const privateKeyPem = (readEnv("APNS_PRIVATE_KEY") ?? "")
    .replaceAll("\\n", "\n")
    .trim();
  const environment = readEnv("APNS_ENVIRONMENT")?.trim();
  if (
    !/^[A-Z0-9]{10}$/u.test(teamId) ||
    !/^[A-Z0-9]{10}$/u.test(keyId) ||
    !/^[A-Za-z0-9.-]{3,255}$/u.test(bundleId) ||
    !privateKeyPem.includes("BEGIN PRIVATE KEY") ||
    (environment !== "production" && environment !== "sandbox")
  ) return null;
  return { teamId, keyId, bundleId, privateKeyPem, environment };
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function encodeJson(value: Record<string, unknown>) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function privateKeyBytes(privateKeyPem: string) {
  const encoded = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/gu, "")
    .replace(/-----END PRIVATE KEY-----/gu, "")
    .replace(/\s/gu, "");
  const binary = atob(encoded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export async function createAppleProviderJwt(input: {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
  now?: Date;
}) {
  const now = Math.floor((input.now ?? new Date()).getTime() / 1000);
  const header = encodeJson({ alg: "ES256", kid: input.keyId });
  const payload = encodeJson({
    iss: input.teamId,
    iat: now,
  });
  const unsigned = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(input.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  return `${unsigned}.${base64Url(signature)}`;
}

export async function appleProviderToken(input: {
  config: ApnsPushConfig;
  now?: Date;
}) {
  const now = input.now ?? new Date();
  const configKey = JSON.stringify({
    teamId: input.config.teamId,
    keyId: input.config.keyId,
    privateKeyPem: input.config.privateKeyPem,
  });
  if (
    cachedProviderToken?.configKey === configKey &&
    cachedProviderToken?.expiresAt &&
    cachedProviderToken.expiresAt > now.getTime()
  ) {
    return cachedProviderToken.value;
  }
  const token = await createAppleProviderJwt({
    teamId: input.config.teamId,
    keyId: input.config.keyId,
    privateKeyPem: input.config.privateKeyPem,
    now,
  });
  cachedProviderToken = {
    value: token,
    configKey,
    expiresAt: now.getTime() + 50 * 60 * 1000,
  };
  return token;
}

export function privacySafePushContent(input: {
  type: string;
  title: string;
  body: string;
}) {
  switch (input.type) {
    case "booking_request":
      return {
        title: "Booking request",
        body: "A booking request needs your attention.",
      };
    case "invoice_overdue":
      return {
        title: "Payment needs attention",
        body: "Open Workloop to review an overdue payment.",
      };
    case "payment_received":
    case "payment":
      return {
        title: "Payment updated",
        body: "A payment has been recorded in Workloop.",
      };
    case "new_booking":
    case "booking":
      return {
        title: "Booking updated",
        body: "A booking has been confirmed in Workloop.",
      };
    case "lead_followup":
      return {
        title: "Follow-up needs attention",
        body: "Open Workloop to review the next useful action.",
      };
    case "no_show":
      return {
        title: "Booking needs attention",
        body: "Open Workloop to review the booking status.",
      };
    case "task_due":
    case "task":
      return {
        title: "Task needs attention",
        body: "Open Workloop to review the task.",
      };
    case "note":
      return {
        title: "Workloop note",
        body: "Open Workloop to review the note.",
      };
    case "morning_digest":
      return {
        title: "Your morning brief",
        body: "Open Workloop to see today's schedule and priorities.",
      };
    default:
      return {
        title: "Workloop update",
        body: "Open Workloop to review this business update.",
      };
  }
}

export function classifyApnsResponse(
  status: number,
  responseBody: string,
  providerMessageId?: string | null,
): PushDeliveryOutcome {
  if (status >= 200 && status < 300) {
    return {
      outcome: "sent",
      providerMessageId: providerMessageId ?? undefined,
      disableToken: false,
    };
  }
  let reason = "";
  try {
    reason = (JSON.parse(responseBody) as { reason?: string }).reason ?? "";
  } catch (_) {
    // A status-derived error still gives the worker a stable outcome.
  }
  if (!/^[A-Za-z]{1,60}$/u.test(reason)) reason = "";
  if (
    status === 410 ||
    [
      "BadDeviceToken",
      "DeviceTokenNotForTopic",
      "MissingDeviceToken",
      "Unregistered",
    ].includes(reason)
  ) {
    return {
      outcome: "failed",
      errorCode: `apns_${reason || "unregistered"}`.toLowerCase(),
      disableToken: true,
    };
  }
  if (status === 400 || status === 413) {
    return {
      outcome: "failed",
      errorCode: `apns_${reason || `http_${status}`}`.toLowerCase(),
      disableToken: false,
    };
  }
  if (status === 429 || status >= 500 || status === 401 || status === 403) {
    return {
      outcome: "retry",
      errorCode: `apns_${reason || `http_${status}`}`.toLowerCase(),
      disableToken: false,
    };
  }
  return {
    outcome: "failed",
    errorCode: `apns_${reason || `http_${status}`}`.toLowerCase(),
    disableToken: false,
  };
}

async function sendAppleMessage(input: {
  delivery: PushDelivery;
  config: ApnsPushConfig;
  providerToken: string;
  fetcher: typeof fetch;
}) {
  const content = privacySafePushContent({
    type: input.delivery.notification_type,
    title: input.delivery.notification_title,
    body: input.delivery.notification_body,
  });
  const environment = input.delivery.apns_environment ??
    input.config.environment;
  const host = environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const response = await input.fetcher(
    `https://${host}/3/device/${
      encodeURIComponent(input.delivery.device_token)
    }`,
    {
      method: "POST",
      headers: {
        Authorization: `bearer ${input.providerToken}`,
        "apns-topic": input.config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: content,
          sound: "default",
          "thread-id": "workloop-business-activity",
        },
        // FlutterFire intentionally ignores direct APNs callbacks unless the
        // payload has an FCM-compatible message identifier. Workloop sends
        // through APNs directly, so use our durable delivery ID to make
        // foreground receipt, warm taps and cold-launch taps observable by
        // FirebaseMessaging without exposing any customer data.
        "gcm.message_id": input.delivery.delivery_id,
        delivery_id: input.delivery.delivery_id,
        deep_link: input.delivery.deep_link ?? "/notifications",
      }),
      signal: AbortSignal.timeout(10_000),
    },
  );
  if (response.status === 401 || response.status === 403) {
    // Do not keep reusing a rejected provider JWT for the rest of its
    // 50-minute cache window. The durable outbox will retry with a fresh JWT.
    cachedProviderToken = null;
  }
  const outcome = classifyApnsResponse(
    response.status,
    await response.text(),
    response.headers.get("apns-id"),
  );
  if (
    input.delivery.apns_environment == null &&
    outcome.errorCode === "apns_baddevicetoken"
  ) {
    // A legacy token has no signed-build environment. A global mismatch is
    // not evidence that this user's token is dead; preserve it for re-registration.
    return {
      outcome: "retry" as const,
      errorCode: "apns_legacy_environment_unverified",
      disableToken: false,
    };
  }
  const retryAfterSeconds = pushRetryAfterSeconds(
    response.headers.get("retry-after"),
  );
  return {
    ...outcome,
    ...(outcome.outcome === "retry" && retryAfterSeconds
      ? { retryAfterSeconds }
      : {}),
  };
}

export async function drainPushNotifications(input: {
  client: PushDeliveryRpcClient;
  config: ApnsPushConfig | null;
  fcmConfig?: FcmPushConfig | null;
  fetcher?: typeof fetch;
  providerToken?: string;
  fcmAccessToken?: string;
  limit?: number;
}) {
  const firebaseConfig = input.fcmConfig === undefined
    ? fcmPushConfig()
    : input.fcmConfig;
  if (input.config === null && firebaseConfig === null) {
    return { configured: false, claimed: 0, sent: 0, retried: 0, failed: 0 };
  }
  const fetcher = input.fetcher ?? fetch;
  const { data, error } = await input.client.rpc("claim_push_deliveries", {
    // Sequential provider requests can each take 10s (plus OAuth). Keep the
    // complete batch below the database's two-minute delivery lease.
    p_limit: Math.max(1, Math.min(input.limit ?? 5, 5)),
  });
  if (error) throw new Error(`push_delivery_claim_failed:${error.code}`);
  const deliveries = Array.isArray(data) ? data as PushDelivery[] : [];
  let sent = 0;
  let retried = 0;
  let failed = 0;

  for (const delivery of deliveries) {
    let outcome: PushDeliveryOutcome;
    try {
      if (delivery.platform === "ios" && input.config) {
        const providerToken = input.providerToken ?? await appleProviderToken({
          config: input.config,
        });
        outcome = await sendAppleMessage({
          delivery,
          config: input.config,
          providerToken,
          fetcher,
        });
      } else if (delivery.platform === "android" && firebaseConfig) {
        outcome = await sendFirebaseMessage({
          config: firebaseConfig,
          deviceToken: delivery.device_token,
          deliveryId: delivery.delivery_id,
          deepLink: delivery.deep_link ?? "/notifications",
          content: privacySafePushContent({
            type: delivery.notification_type,
            title: delivery.notification_title,
            body: delivery.notification_body,
          }),
          fetcher,
          accessToken: input.fcmAccessToken,
        });
      } else if (["ios", "android"].includes(delivery.platform)) {
        outcome = {
          outcome: "retry",
          errorCode: delivery.platform === "ios"
            ? "apns_not_configured"
            : "fcm_not_configured",
          disableToken: false,
        };
      } else {
        outcome = {
          outcome: "failed",
          errorCode: "push_platform_unsupported",
          disableToken: false,
        };
      }
    } catch (_) {
      outcome = {
        outcome: "retry",
        errorCode: delivery.platform === "android"
          ? "fcm_request_failed"
          : "apns_request_failed",
        disableToken: false,
      };
    }
    const finish = await input.client.rpc("finish_push_delivery", {
      p_delivery_id: delivery.delivery_id,
      p_lease_token: delivery.delivery_lease_token,
      p_outcome: outcome.outcome,
      p_provider_message_id: outcome.providerMessageId ?? null,
      p_error_code: outcome.errorCode ?? null,
      p_disable_token: outcome.disableToken,
      ...(outcome.retryAfterSeconds
        ? { p_retry_after_seconds: outcome.retryAfterSeconds }
        : {}),
    });
    if (finish.error || finish.data !== true) {
      throw new Error(`push_delivery_finish_failed:${finish.error?.code}`);
    }
    if (outcome.outcome === "sent") sent++;
    else if (outcome.outcome === "retry") retried++;
    else failed++;
  }
  return {
    configured: true,
    claimed: deliveries.length,
    sent,
    retried,
    failed,
  };
}
