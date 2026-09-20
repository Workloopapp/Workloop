import {
  automationAlertConfig,
  type AutomationClient,
  deliverOperationalAlerts,
  operationalAlertEmailContent,
  processAccountDeletions,
} from "./workloop_automations.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("operations alert configuration fails closed", () => {
  assert(automationAlertConfig(() => undefined) === null, "missing rejected");
  const config = automationAlertConfig((name) =>
    ({
      RESEND_API_KEY: "re_1234567890123456",
      BOOKING_CONFIRMATION_EMAIL_FROM: "Workloop <ops@workloop.uk>",
      OPERATIONS_ALERT_EMAIL: "OWNER@WORKLOOP.UK",
    })[name]
  );
  assert(config?.recipient === "owner@workloop.uk", "recipient normalized");
});

Deno.test("account deletion worker is bounded and uses the protected endpoint", async () => {
  let requestUrl = "";
  let adminToken = "";
  const query = {
    select() {
      return this;
    },
    in() {
      return this;
    },
    order() {
      return this;
    },
    limit() {
      return Promise.resolve({ data: [{ id: "request-1" }], error: null });
    },
  };
  const client = {
    from() {
      return query;
    },
  } as unknown as AutomationClient;

  const result = await processAccountDeletions({
    client,
    supabaseUrl: "https://project.supabase.co",
    serviceRoleKey: "service-role-key-with-at-least-32-chars",
    adminToken: "admin-token-with-at-least-32-characters",
    fetcher: (url, init) => {
      requestUrl = url.toString();
      adminToken = new Headers(init?.headers).get("x-admin-token") ?? "";
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assert(result.completed === 1, "request completed");
  assert(requestUrl.endsWith("/complete-account-deletion"), "protected route");
  assert(adminToken.startsWith("admin-token"), "admin token forwarded");
});

Deno.test("operational alert delivery is escaped and acknowledged", async () => {
  const calls: string[] = [];
  let body = "";
  const client = {
    rpc(name: string) {
      calls.push(name);
      if (name === "claim_operational_alerts") {
        return Promise.resolve({
          data: [{
            alert_id: "alert-1",
            alert_key: "queue:<unsafe>",
            category: "transactional_email",
            severity: "critical",
            message: "Delivery <failed>",
            first_seen_at: "2026-08-15T18:00:00Z",
          }],
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    },
  } as unknown as AutomationClient;

  const result = await deliverOperationalAlerts({
    client,
    config: {
      apiKey: "re_1234567890123456",
      from: "Workloop <ops@workloop.uk>",
      recipient: "owner@workloop.uk",
    },
    now: new Date("2026-08-15T18:00:00Z"),
    fetcher: (_url, init) => {
      body = init?.body?.toString() ?? "";
      return Promise.resolve(new Response('{"id":"mail-1"}', { status: 200 }));
    },
  });
  assert(result.sent === 1, "alert sent");
  const providerBody = JSON.parse(body);
  assert(
    providerBody.html.includes("Delivery &lt;failed&gt;"),
    "HTML input escaped",
  );
  assert(
    calls.join(",") ===
      "claim_operational_alerts,finish_operational_alert_delivery",
    "claim acknowledged",
  );

  const content = operationalAlertEmailContent({
    alert_id: "alert-1",
    alert_key: "key",
    category: "account_deletion",
    severity: "warning",
    message: "Delayed",
    first_seen_at: "now",
  });
  assert(content.subject.includes("Warning"), "warning subject");
});
