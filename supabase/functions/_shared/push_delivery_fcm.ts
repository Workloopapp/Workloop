import type { PushDeliveryOutcome } from "./push_delivery.ts";

export type FcmPushConfig = {
  projectId: string;
  clientEmail: string;
  privateKeyPem: string;
};

const oauthUrl = "https://oauth2.googleapis.com/token";
let cachedAccess: {
  configKey: string;
  token: string;
  expiresAt: number;
} | null = null;

export function fcmPushConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): FcmPushConfig | null {
  try {
    const data = JSON.parse(readEnv("FCM_SERVICE_ACCOUNT_JSON") ?? "{}");
    const projectId = data.project_id?.trim() ?? "";
    const clientEmail = data.client_email?.trim() ?? "";
    const privateKeyPem = (data.private_key ?? "").replaceAll("\\n", "\n")
      .trim();
    if (
      data.type !== "service_account" ||
      !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/u.test(projectId) ||
      !/^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com$/u.test(
        clientEmail,
      ) || !privateKeyPem.includes("-----BEGIN PRIVATE KEY-----")
    ) return null;
    return { projectId, clientEmail, privateKeyPem };
  } catch (_) {
    return null;
  }
}

function base64Url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-")
    .replaceAll("/", "_").replaceAll("=", "");
}

export async function createGoogleServiceAssertion(
  config: FcmPushConfig,
  now = new Date(),
) {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const encode = (data: Record<string, unknown>) =>
    base64Url(new TextEncoder().encode(JSON.stringify(data)));
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${
    encode({
      iss: config.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: oauthUrl,
      iat: issuedAt,
      exp: issuedAt + 3600,
    })
  }`;
  const encoded = config.privateKeyPem.replace(
    /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/gu,
    "",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

export async function googleAccessToken(input: {
  config: FcmPushConfig;
  fetcher?: typeof fetch;
  now?: Date;
}) {
  const now = input.now ?? new Date();
  const configKey = JSON.stringify(input.config);
  if (
    cachedAccess?.configKey === configKey &&
    cachedAccess.expiresAt > now.getTime()
  ) return cachedAccess.token;
  const assertion = await createGoogleServiceAssertion(input.config, now);
  const response = await (input.fetcher ?? fetch)(oauthUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error("fcm_oauth_failed");
  const data = await response.json();
  if (
    typeof data.access_token !== "string" || !data.access_token ||
    typeof data.expires_in !== "number" || data.expires_in <= 60
  ) throw new Error("fcm_oauth_invalid_response");
  cachedAccess = {
    configKey,
    token: data.access_token,
    expiresAt: now.getTime() + (Math.min(data.expires_in, 3600) - 60) * 1000,
  };
  return cachedAccess.token;
}

export function pushRetryAfterSeconds(value: string | null, now = new Date()) {
  if (!value) return undefined;
  const seconds = /^\d+$/u.test(value.trim())
    ? Number(value.trim())
    : Math.ceil((Date.parse(value) - now.getTime()) / 1000);
  return Number.isFinite(seconds) && seconds > 0
    ? Math.min(seconds, 7 * 24 * 60 * 60)
    : undefined;
}

export function classifyFcmResponse(
  status: number,
  body: string,
  retryAfter?: number,
): PushDeliveryOutcome {
  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(body) ?? {};
  } catch (_) { /* Never persist provider messages or token strings. */ }
  if (status >= 200 && status < 300) {
    if (typeof data.name !== "string" || !data.name.startsWith("projects/")) {
      return {
        outcome: "retry",
        errorCode: "fcm_invalid_response",
        disableToken: false,
      };
    }
    return {
      outcome: "sent",
      providerMessageId: data.name,
      disableToken: false,
    };
  }
  const error = data.error as {
    status?: unknown;
    details?: Array<{ "@type"?: string; errorCode?: unknown }>;
  } | undefined;
  const fcmError = Array.isArray(error?.details)
    ? error.details.find((detail) =>
      detail?.["@type"] ===
        "type.googleapis.com/google.firebase.fcm.v1.FcmError"
    )?.errorCode
    : undefined;
  // Only definitive token removal disables the device. INVALID_ARGUMENT may
  // describe our payload, and SENDER_ID_MISMATCH may describe server credentials.
  if (fcmError === "UNREGISTERED") {
    return {
      outcome: "failed",
      errorCode: "fcm_unregistered",
      disableToken: true,
    };
  }
  const known = new Set([
    "INVALID_ARGUMENT",
    "SENDER_ID_MISMATCH",
    "QUOTA_EXCEEDED",
    "UNAVAILABLE",
    "INTERNAL",
    "THIRD_PARTY_AUTH_ERROR",
    "UNAUTHENTICATED",
    "PERMISSION_DENIED",
    "NOT_FOUND",
  ]);
  const code = typeof fcmError === "string" && known.has(fcmError)
    ? fcmError.toLowerCase()
    : typeof error?.status === "string" && known.has(error.status)
    ? error.status.toLowerCase()
    : `http_${status}`;
  const retry = [401, 403, 408, 429].includes(status) || status >= 500;
  return {
    outcome: retry ? "retry" : "failed",
    errorCode: `fcm_${code}`,
    disableToken: false,
    ...(retryAfter && retry ? { retryAfterSeconds: retryAfter } : {}),
  };
}

export async function sendFirebaseMessage(input: {
  config: FcmPushConfig;
  deviceToken: string;
  deliveryId: string;
  deepLink: string;
  content: { title: string; body: string };
  fetcher: typeof fetch;
  accessToken?: string;
}) {
  const token = input.accessToken ?? await googleAccessToken({
    config: input.config,
    fetcher: input.fetcher,
  });
  const response = await input.fetcher(
    `https://fcm.googleapis.com/v1/projects/${input.config.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: input.deviceToken,
          notification: input.content,
          data: {
            delivery_id: input.deliveryId,
            deep_link: input.deepLink,
          },
          android: {
            priority: "HIGH",
            restricted_package_name: "com.ismaeel.workloop",
            notification: {
              channel_id: "workloop_reminders",
              icon: "ic_stat_workloop",
              sound: "default",
              tag: input.deliveryId,
            },
          },
        },
      }),
      signal: AbortSignal.timeout(10_000),
    },
  );
  if (response.status === 401 || response.status === 403) cachedAccess = null;
  return classifyFcmResponse(
    response.status,
    await response.text(),
    pushRetryAfterSeconds(response.headers.get("retry-after")),
  );
}
