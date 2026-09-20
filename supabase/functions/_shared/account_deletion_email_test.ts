import {
  accountDeletionEmailConfig,
  accountDeletionEmailContent,
  drainAccountDeletionEmails,
} from "./account_deletion_email.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("deletion email config fails closed and reuses a trusted sender", () => {
  assert(
    accountDeletionEmailConfig(() => undefined) === null,
    "missing config",
  );
  const config = accountDeletionEmailConfig((name) =>
    ({
      RESEND_API_KEY: "re_1234567890123456",
      ACCOUNT_WELCOME_EMAIL_FROM: "Workloop <hello@workloop.uk>",
    })[name]
  );
  assert(config?.from === "Workloop <hello@workloop.uk>", "trusted sender");
});

Deno.test("request email clearly says deletion is not complete", () => {
  const content = accountDeletionEmailContent("deletion_requested");
  assert(content.subject.includes("deletion request"), "specific subject");
  assert(
    content.plainText.includes("has not been deleted yet"),
    "honest state",
  );
  assert(content.html.includes("REQUEST RECEIVED"), "specific visual label");
  assert(
    content.html.includes("mailto:support@workloop.uk"),
    "urgent support route",
  );
});

Deno.test("completion email describes deletion and bounded retention honestly", () => {
  const content = accountDeletionEmailContent("account_deleted");
  assert(content.subject.includes("has been deleted"), "completion subject");
  assert(
    content.plainText.includes("can no longer sign in"),
    "account outcome",
  );
  assert(
    content.plainText.includes("Limited records may be retained"),
    "retention truth",
  );
  assert(content.html.includes("https://workloop.uk/privacy"), "privacy route");
  assert(!content.plainText.includes("—"), "no em dash");
});

Deno.test("deletion drain uses event-specific stable idempotency", async () => {
  const calls: string[] = [];
  let idempotencyKey = "";
  const result = await drainAccountDeletionEmails({
    client: {
      rpc(name) {
        calls.push(name);
        if (name === "claim_account_deletion_emails") {
          return Promise.resolve({
            data: [{
              outbox_id: "outbox-1",
              lease_token: "lease-1",
              recipient_email: "owner@example.com",
              event: "account_deleted",
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
    idempotencyKey === "account-account_deleted/outbox-1",
    "stable provider key",
  );
  assert(result.sent === 1, "delivery recorded");
  assert(
    calls.join(",") ===
      "claim_account_deletion_emails,finish_account_deletion_email",
    "claim and finish",
  );
});
