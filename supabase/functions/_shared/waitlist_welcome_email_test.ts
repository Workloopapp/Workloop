import {
  drainWaitlistWelcomeEmails,
  waitlistWelcomeEmailConfig,
  waitlistWelcomeEmailContent,
} from "./waitlist_welcome_email.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("waitlist email config fails closed and supports a dedicated sender", () => {
  assert(
    waitlistWelcomeEmailConfig(() => undefined) === null,
    "missing config",
  );
  const config = waitlistWelcomeEmailConfig((name) =>
    ({
      RESEND_API_KEY: "re_1234567890123456",
      WAITLIST_CONFIRMATION_EMAIL_FROM: "Workloop <hello@workloop.uk>",
    })[name]
  );
  assert(config?.from === "Workloop <hello@workloop.uk>", "dedicated sender");
});

Deno.test("waitlist welcome content is useful, honest, and free of dash-heavy copy", () => {
  const content = waitlistWelcomeEmailContent();
  assert(content.subject.includes("Workloop"), "branded subject");
  assert(content.plainText.includes("30 days free"), "pricing context");
  assert(
    content.plainText.includes("does not require payment details"),
    "beta trust",
  );
  assert(
    content.html.includes("https://workloop.uk/help/welcome"),
    "fixed CTA",
  );
  assert(!content.plainText.includes("—"), "no em dash");
});

Deno.test("waitlist drain uses a stable Resend idempotency key", async () => {
  const calls: Array<{ name: string; params?: Record<string, unknown> }> = [];
  let idempotencyKey = "";
  const result = await drainWaitlistWelcomeEmails({
    client: {
      rpc(name, params) {
        calls.push({ name, params });
        if (name === "claim_waitlist_welcome_emails") {
          return Promise.resolve({
            data: [{
              outbox_id: "outbox-1",
              lease_token: "lease-1",
              recipient_email: "customer@example.com",
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
  assert(idempotencyKey === "launch-waitlist-joined/outbox-1", "stable key");
  assert(result.sent === 1 && calls.length === 2, "claimed and acknowledged");
});
