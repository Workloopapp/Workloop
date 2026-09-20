import {
  classifyFcmResponse,
  createGoogleServiceAssertion,
  fcmPushConfig,
  googleAccessToken,
  pushRetryAfterSeconds,
  sendFirebaseMessage,
} from "./push_delivery_fcm.ts";
import { drainPushNotifications } from "./push_delivery.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const config = {
  projectId: "workloop-push-test",
  clientEmail: "push@workloop-push-test.iam.gserviceaccount.com",
  privateKeyPem: "unused",
};

function claimed(platform: string, environment?: "production" | "sandbox") {
  return {
    delivery_id: `delivery-${platform}`,
    delivery_lease_token: `lease-${platform}`,
    push_token_id: `token-${platform}`,
    device_token: `device-${platform}`,
    platform,
    apns_environment: environment,
    notification_type: "booking_request",
    notification_title: "Private name",
    notification_body: "Private contact £123",
    deep_link: "/booking-requests",
  };
}

Deno.test("FCM config accepts only a complete server service account", () => {
  equal(fcmPushConfig(() => "bad-json"), null);
  equal(fcmPushConfig(() => undefined), null);
  equal(
    fcmPushConfig(() =>
      JSON.stringify({
        type: "service_account",
        project_id: config.projectId,
        client_email: config.clientEmail,
        private_key:
          "-----BEGIN PRIVATE KEY-----\\nfixture\\n-----END PRIVATE KEY-----",
        token_uri: "https://untrusted.invalid/ignored",
      })
    )?.projectId,
    config.projectId,
  );
});

Deno.test("Google OAuth assertion uses RS256, correct audience, scope and expiry", async () => {
  const keys = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const exported = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...exported))
  }\n-----END PRIVATE KEY-----`;
  const current = { ...config, privateKeyPem };
  const now = new Date("2026-09-04T12:00:00Z");
  const assertion = await createGoogleServiceAssertion(current, now);
  const [header, payload, signature] = assertion.split(".");
  const decode = (value: string) =>
    Uint8Array.from(
      atob(value.replaceAll("-", "+").replaceAll("_", "/")),
      (c) => c.charCodeAt(0),
    );
  equal(JSON.parse(new TextDecoder().decode(decode(header))).alg, "RS256");
  const claims = JSON.parse(new TextDecoder().decode(decode(payload)));
  equal(claims.aud, "https://oauth2.googleapis.com/token");
  equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  equal(claims.exp - claims.iat, 3600);
  equal(
    await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      keys.publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${payload}`),
    ),
    true,
  );
  let exchanges = 0;
  const fetcher = ((url, init) => {
    equal(url, "https://oauth2.googleapis.com/token");
    equal(
      new URLSearchParams(String(init?.body)).get("grant_type"),
      "urn:ietf:params:oauth:grant-type:jwt-bearer",
    );
    exchanges++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ access_token: "short-lived-token", expires_in: 3600 }),
      ),
    );
  }) as typeof fetch;
  equal(
    await googleAccessToken({ config: current, fetcher, now }),
    "short-lived-token",
  );
  equal(
    await googleAccessToken({ config: current, fetcher, now }),
    "short-lived-token",
  );
  equal(exchanges, 1);
});

Deno.test("FCM invalid payload and server credentials never disable a device", () => {
  equal(classifyFcmResponse(200, "malformed-body").outcome, "retry");
  equal(classifyFcmResponse(503, "").outcome, "retry");
  equal(classifyFcmResponse(429, "", 120).retryAfterSeconds, 120);
  equal(
    classifyFcmResponse(403, '{"error":{"status":"PERMISSION_DENIED"}}')
      .disableToken,
    false,
  );
  equal(classifyFcmResponse(404, "").disableToken, false);
  equal(
    classifyFcmResponse(
      400,
      '{"error":{"status":"INVALID_ARGUMENT","message":"private-token"}}',
    ).disableToken,
    false,
  );
  equal(
    classifyFcmResponse(
      404,
      JSON.stringify({
        error: {
          details: [{
            "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            errorCode: "UNREGISTERED",
          }],
        },
      }),
    ).disableToken,
    true,
  );
  equal(
    JSON.stringify(
      classifyFcmResponse(
        400,
        '{"error":{"status":"private-token","message":"private-token"}}',
      ),
    ).includes("private-token"),
    false,
  );
});

Deno.test("Android message uses existing channel, safe preview and tap route", async () => {
  let body: Record<string, unknown> = {};
  const outcome = await sendFirebaseMessage({
    config,
    deviceToken: "device",
    deliveryId: "delivery",
    deepLink: "/booking-requests",
    content: { title: "Booking request", body: "A request needs attention." },
    accessToken: "access-token",
    fetcher: ((url, init) => {
      equal(
        url,
        `https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send`,
      );
      body = JSON.parse(String(init?.body));
      return Promise.resolve(
        new Response('{"name":"projects/workloop/messages/1"}'),
      );
    }) as typeof fetch,
  });
  const message = body.message as Record<string, unknown>;
  equal(message.data, {
    delivery_id: "delivery",
    deep_link: "/booking-requests",
  });
  equal(
    (message.android as { notification: { channel_id: string } }).notification
      .channel_id,
    "workloop_reminders",
  );
  equal(outcome.outcome, "sent");
});

Deno.test("Android drains independently without APNs credentials and respects Retry-After", async () => {
  const finished: Record<string, unknown>[] = [];
  const result = await drainPushNotifications({
    config: null,
    fcmConfig: config,
    fcmAccessToken: "access-token",
    limit: 50,
    client: {
      rpc(name, params) {
        if (name === "claim_push_deliveries") {
          equal(params?.p_limit, 5);
          return Promise.resolve({ data: [claimed("android")], error: null });
        }
        finished.push(params!);
        return Promise.resolve({ data: true, error: null });
      },
    },
    fetcher: ((_, init) => {
      equal(String(init?.body).includes("Private"), false);
      return Promise.resolve(
        new Response("", { status: 429, headers: { "retry-after": "3600" } }),
      );
    }) as typeof fetch,
  });
  equal(result.retried, 1);
  equal(finished[0].p_retry_after_seconds, 3600);
  equal(finished[0].p_disable_token, false);
});

Deno.test("per-device APNs environment overrides worker default; legacy mismatch retains token", async () => {
  const hosts: string[] = [];
  const finished: Record<string, unknown>[] = [];
  await drainPushNotifications({
    config: {
      teamId: "6RH526FD7B",
      keyId: "KK99YL9CWC",
      bundleId: "com.ismaeel.workloop",
      privateKeyPem: "unused",
      environment: "production",
    },
    fcmConfig: null,
    providerToken: "provider-token",
    client: {
      rpc(name, params) {
        if (name === "claim_push_deliveries") {
          return Promise.resolve({
            data: [claimed("ios", "sandbox"), claimed("ios")],
            error: null,
          });
        }
        finished.push(params!);
        return Promise.resolve({ data: true, error: null });
      },
    },
    fetcher: ((url) => {
      hosts.push(new URL(String(url)).hostname);
      return Promise.resolve(
        hosts.length === 1
          ? new Response("")
          : new Response('{"reason":"BadDeviceToken"}', { status: 400 }),
      );
    }) as typeof fetch,
  });
  equal(hosts, ["api.sandbox.push.apple.com", "api.push.apple.com"]);
  equal(finished[1].p_outcome, "retry");
  equal(finished[1].p_disable_token, false);
});

Deno.test("Retry-After supports seconds and HTTP dates without negative delays", () => {
  const now = new Date("2026-09-04T12:00:00Z");
  equal(pushRetryAfterSeconds("120", now), 120);
  equal(pushRetryAfterSeconds("Fri, 04 Sep 2026 12:05:00 GMT", now), 300);
  equal(pushRetryAfterSeconds("yesterday", now), undefined);
  equal(pushRetryAfterSeconds("0", now), undefined);
});
