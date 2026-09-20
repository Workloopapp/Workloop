import {
  apnsPushConfig,
  classifyApnsResponse,
  drainPushNotifications,
  privacySafePushContent,
  type PushDeliveryRpcClient,
} from "./push_delivery.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("APNs config is all-or-nothing and expands escaped newlines", () => {
  const config = apnsPushConfig((name) =>
    ({
      APNS_TEAM_ID: "6RH526FD7B",
      APNS_KEY_ID: "KK99YL9CWC",
      APNS_BUNDLE_ID: "com.ismaeel.workloop",
      APNS_PRIVATE_KEY:
        "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
      APNS_ENVIRONMENT: "production",
    })[name]
  );
  assertEquals(config?.bundleId, "com.ismaeel.workloop");
  assertEquals(config?.privateKeyPem.includes("\nabc\n"), true);
  assertEquals(apnsPushConfig(() => undefined), null);
  assertEquals(
    apnsPushConfig((name) =>
      ({
        APNS_TEAM_ID: "6RH526FD7B",
        APNS_KEY_ID: "KK99YL9CWC",
        APNS_BUNDLE_ID: "com.ismaeel.workloop",
        APNS_PRIVATE_KEY:
          "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
        APNS_ENVIRONMENT: "prodution",
      })[name]
    ),
    null,
  );
});

Deno.test("push copy does not expose client or payment detail", () => {
  const request = privacySafePushContent({
    type: "booking_request",
    title: "Amina requested a booking",
    body: "Amina 07123456789 wants an appointment",
  });
  const overdue = privacySafePushContent({
    type: "invoice_overdue",
    title: "£900 overdue",
    body: "Jordan owes £900",
  });
  const task = privacySafePushContent({
    type: "task_due",
    title: "Call Amina on 07123456789",
    body: "Chase Amina's £900 balance",
  });
  const brief = privacySafePushContent({
    type: "morning_digest",
    title: "Amina's bookings",
    body: "Amina owes £900",
  });
  assertEquals(JSON.stringify(request).includes("Amina"), false);
  assertEquals(JSON.stringify(overdue).includes("900"), false);
  assertEquals(JSON.stringify(task).includes("Amina"), false);
  assertEquals(JSON.stringify(task).includes("900"), false);
  assertEquals(JSON.stringify(brief).includes("Amina"), false);
  assertEquals(JSON.stringify(brief).includes("900"), false);
});

Deno.test("APNs failures distinguish retryable and dead tokens", () => {
  assertEquals(classifyApnsResponse(503, "").outcome, "retry");
  assertEquals(
    classifyApnsResponse(410, '{"reason":"Unregistered"}').disableToken,
    true,
  );
  assertEquals(
    classifyApnsResponse(400, '{"reason":"BadDeviceToken"}').disableToken,
    true,
  );
  assertEquals(
    classifyApnsResponse(200, "", "apple-message-1")
      .providerMessageId,
    "apple-message-1",
  );
});

Deno.test("durable drain finishes a successful claimed delivery", async () => {
  const rpcCalls: Array<{ name: string; params?: Record<string, unknown> }> =
    [];
  const apnsPayloads: Array<Record<string, unknown>> = [];
  const client: PushDeliveryRpcClient = {
    rpc(name, params) {
      rpcCalls.push({ name, params });
      if (name === "claim_push_deliveries") {
        return Promise.resolve({
          error: null,
          data: [{
            delivery_id: "delivery-1",
            delivery_lease_token: "lease-1",
            push_token_id: "token-1",
            device_token: "apns-device-token",
            platform: "ios",
            notification_type: "booking_request",
            notification_title: "Private title",
            notification_body: "Private body",
            deep_link: "/booking-requests/92000000-0000-4000-8000-000000000002",
          }],
        });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };
  const result = await drainPushNotifications({
    client,
    config: {
      teamId: "6RH526FD7B",
      keyId: "KK99YL9CWC",
      bundleId: "com.ismaeel.workloop",
      privateKeyPem: "unused",
      environment: "production",
    },
    providerToken: "provider-token",
    fetcher: ((_, init) => {
      apnsPayloads.push(
        JSON.parse(init?.body?.toString() ?? "{}") as Record<string, unknown>,
      );
      return Promise.resolve(
        new Response("", {
          status: 200,
          headers: { "apns-id": "apple-message-1" },
        }),
      );
    }) as typeof fetch,
  });
  assertEquals(result.sent, 1);
  assertEquals(rpcCalls.map((call) => call.name), [
    "claim_push_deliveries",
    "finish_push_delivery",
  ]);
  assertEquals(rpcCalls[1].params?.p_outcome, "sent");
  assertEquals(
    apnsPayloads[0]?.deep_link,
    "/booking-requests/92000000-0000-4000-8000-000000000002",
  );
  assertEquals(apnsPayloads[0]?.["gcm.message_id"], "delivery-1");
  assertEquals(JSON.stringify(apnsPayloads[0]).includes("Private body"), false);
});
