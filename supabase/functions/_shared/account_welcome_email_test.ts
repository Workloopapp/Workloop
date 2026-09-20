import {
  accountWelcomeEmailConfig,
  accountWelcomeEmailContent,
  drainAccountWelcomeEmails,
} from "./account_welcome_email.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("account welcome config fails closed and reuses the trusted sender", () => {
  assert(accountWelcomeEmailConfig(() => undefined) === null, "missing config");
  const config = accountWelcomeEmailConfig((name) =>
    ({
      RESEND_API_KEY: "re_1234567890123456",
      WAITLIST_CONFIRMATION_EMAIL_FROM: "Workloop <hello@workloop.uk>",
    })[name]
  );
  assert(config?.from === "Workloop <hello@workloop.uk>", "trusted sender");
});

Deno.test("account welcome content is useful, calm, and specific", () => {
  const content = accountWelcomeEmailContent();
  assert(content.subject === "Welcome to Workloop", "welcome subject");
  assert(
    content.plainText.includes("Your email is confirmed"),
    "verification state",
  );
  assert(
    content.plainText.includes("Start with three simple things"),
    "onboarding advice",
  );
  assert(
    content.html.includes("https://workloop.uk/help/welcome"),
    "fixed CTA",
  );
  assert(content.html.includes("support@workloop.uk"), "support route");
  assert(!content.plainText.includes("—"), "no em dash");
});

Deno.test("account welcome drain is idempotent and acknowledges delivery", async () => {
  const calls: string[] = [];
  let idempotencyKey = "";
  const result = await drainAccountWelcomeEmails({
    client: {
      rpc(name) {
        calls.push(name);
        if (name === "claim_account_welcome_emails") {
          return Promise.resolve({
            data: [{
              outbox_id: "outbox-1",
              lease_token: "lease-1",
              recipient_email: "owner@example.com",
              attempt_count: 1,
            }],
            error: null,
          });
        }
        return Promise.resolve({ data: "sent", error: null });
      },
    },
    config: {
      apiKey: "re_1234567890123456",
      from: "Workloop <hello@workloop.uk>",
    },
    fetcher: (_url, init) => {
      idempotencyKey = new Headers(init?.headers).get("Idempotency-Key") ?? "";
      return Promise.resolve(
        new Response(JSON.stringify({ id: "email-1" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  });
  assert(
    idempotencyKey === "account-email-verified/outbox-1",
    "stable provider key",
  );
  assert(result.sent === 1, "delivery recorded");
  assert(
    calls.join(",") ===
      "claim_account_welcome_emails,finish_account_welcome_email",
    "claim and finish",
  );
});
