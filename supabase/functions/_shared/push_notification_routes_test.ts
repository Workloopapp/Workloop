import { drainPushNotifications } from "./push_delivery.ts";

const recordId = "92400000-0000-4000-8000-000000000001";
const destinations = [
  ["booking_request", `/booking-requests/${recordId}`],
  ["new_booking", `/bookings/${recordId}`],
  ["invoice_overdue", `/payments/${recordId}`],
  ["task_due", `/tasks/${recordId}`],
  ["note", `/notes/${recordId}`],
  ["morning_digest", "/home"],
];

for (const platform of ["ios", "android"]) {
  for (const [type, deepLink] of destinations) {
    Deno.test(`${platform} push retains the canonical ${type} destination`, async () => {
      const requests: Record<string, unknown>[] = [];
      const finishes: Record<string, unknown>[] = [];
      const result = await drainPushNotifications({
        config: {
          teamId: "TESTTEAM",
          keyId: "TESTKEY",
          bundleId: "uk.workloop.test",
          privateKeyPem: "unused",
          environment: "sandbox",
        },
        fcmConfig: {
          projectId: "workloop-push-test",
          clientEmail: "push@workloop-push-test.iam.gserviceaccount.com",
          privateKeyPem: "unused",
        },
        providerToken: "synthetic-provider-token",
        fcmAccessToken: "synthetic-access-token",
        client: {
          rpc(name, params) {
            if (name === "claim_push_deliveries") {
              return Promise.resolve({
                error: null,
                data: [{
                  delivery_id: "synthetic-delivery",
                  delivery_lease_token: "synthetic-lease",
                  push_token_id: "synthetic-device-id",
                  device_token: "synthetic-device-token",
                  platform,
                  apns_environment: "sandbox",
                  notification_type: type,
                  notification_title: "Private client name",
                  notification_body: "Private client contact and payment",
                  deep_link: deepLink,
                }],
              });
            }
            finishes.push(params!);
            return Promise.resolve({ error: null, data: true });
          },
        },
        fetcher: ((_, init) => {
          requests.push(JSON.parse(String(init?.body)));
          return Promise.resolve(
            platform === "android"
              ? new Response('{"name":"projects/workloop/messages/test"}')
              : new Response("", { headers: { "apns-id": "synthetic-id" } }),
          );
        }) as typeof fetch,
      });
      if (requests.length !== 1 || result.sent !== 1) {
        throw new Error("Expected exactly one synthetic provider request");
      }
      const request = requests[0];
      const route = platform === "android"
        ? (request.message as { data: { deep_link: string } }).data.deep_link
        : request.deep_link;
      if (route !== deepLink) {
        throw new Error(`Provider route changed from ${deepLink} to ${route}`);
      }
      if (JSON.stringify(request).includes("Private client")) {
        throw new Error("Lock-screen payload leaked private inbox copy");
      }
      if (
        finishes.length !== 1 ||
        finishes[0].p_delivery_id !== "synthetic-delivery" ||
        finishes[0].p_outcome !== "sent"
      ) {
        throw new Error("Worker did not finish the correct claimed delivery");
      }
    });
  }
}
