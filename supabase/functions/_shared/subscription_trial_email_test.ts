import {
  drainSubscriptionTrialEmails,
  subscriptionTrialEmailContent,
} from "./subscription_trial_email.ts";
import type { BookingConfirmationRpcClient } from "./booking_confirmation_email.ts";
const config = {
  apiKey: "test-key-never-used",
  from: "Workloop <test@example.test>",
};
const claim = { outbox_id: "receipt-one", lease_token: "lease-one" };
const prepared = {
  recipient_email: "account@example.test",
  trial_ends_at: "2026-10-12T12:30:00Z",
  days_before: 7,
};
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
Deno.test("billing email names exact end and clear cancellation path without inventing price", () => {
  const content = subscriptionTrialEmailContent(prepared.trial_ends_at);
  for (
    const required of [
      "12 October 2026",
      "12:30 UTC",
      "at least 24 hours",
      "https://apps.apple.com/account/subscriptions",
      "does not cancel",
      "Haani Enterprise Limited",
    ]
  ) {
    equal(content.plainText.includes(required), true);
  }
  equal(content.plainText.includes("£14.99"), false);
  equal(content.html.includes("Manage or cancel subscription"), true);
});
Deno.test("successful email is rechecked before send and records provider evidence", async () => {
  const actions: string[] = [];
  let completion: Record<string, unknown> = {};
  const client: BookingConfirmationRpcClient = {
    rpc: async (name, params) => {
      actions.push(name);
      if (name === "claim_subscription_trial_emails") {
        return {
          data: [claim],
          error: null,
        };
      }
      if (name === "prepare_subscription_trial_email") {
        return {
          data: [prepared],
          error: null,
        };
      }
      completion = params!;
      return { data: "sent", error: null };
    },
  };
  const fetcher: typeof fetch = (_url, init) => {
    actions.push("provider");
    equal(
      new Headers(init?.headers).get("Idempotency-Key"),
      "subscription-trial/receipt-one",
    );
    equal(JSON.parse(String(init?.body)).to, [prepared.recipient_email]);
    return Promise.resolve(
      new Response(JSON.stringify({ id: "provider-one" }), { status: 200 }),
    );
  };
  const result = await drainSubscriptionTrialEmails({
    client,
    config,
    fetcher,
  });
  equal(actions, [
    "claim_subscription_trial_emails",
    "prepare_subscription_trial_email",
    "provider",
    "finish_subscription_trial_email",
  ]);
  equal(completion.p_provider_message_id, "provider-one");
  equal(result.sent, 1);
});
Deno.test("cancellation after claim prevents any provider request", async () => {
  let sent = false;
  const client: BookingConfirmationRpcClient = {
    rpc: async (name, params) => {
      if (name === "claim_subscription_trial_emails") {
        return {
          data: [claim],
          error: null,
        };
      }
      if (name === "prepare_subscription_trial_email") {
        return {
          data: [],
          error: null,
        };
      }
      equal(params?.p_sent, false);
      equal(params?.p_skipped, true);
      return { data: "skipped", error: null };
    },
  };
  const result = await drainSubscriptionTrialEmails({
    client,
    config,
    fetcher: () => {
      sent = true;
      throw new Error("must not send");
    },
  });
  equal(sent, false);
  equal(result.skipped, 1);
});
Deno.test("provider failures produce retry evidence without storing customer data", async () => {
  let completion: Record<string, unknown> = {};
  const client: BookingConfirmationRpcClient = {
    rpc: async (name, params) => {
      if (name === "claim_subscription_trial_emails") {
        return {
          data: [claim],
          error: null,
        };
      }
      if (name === "prepare_subscription_trial_email") {
        return {
          data: [prepared],
          error: null,
        };
      }
      completion = params!;
      return { data: "pending", error: null };
    },
  };
  const result = await drainSubscriptionTrialEmails({
    client,
    config,
    fetcher: () => {
      throw new Error("account@example.test secret provider payload");
    },
  });
  equal(completion.p_sent, false);
  equal(completion.p_error, "subscription_trial_email_delivery_failed");
  equal(result.pending, 1);
});
Deno.test("database recheck failure never sends from a stale claim", async () => {
  let calls = 0;
  const client: BookingConfirmationRpcClient = {
    rpc: async (name) => {
      if (name === "claim_subscription_trial_emails") {
        return {
          data: [claim],
          error: null,
        };
      }
      if (name === "prepare_subscription_trial_email") {
        return {
          data: null,
          error: { code: "503" },
        };
      }
      return { data: "pending", error: null };
    },
  };
  await drainSubscriptionTrialEmails({
    client,
    config,
    fetcher: () => {
      calls++;
      throw new Error("must not send");
    },
  });
  equal(calls, 0);
});
Deno.test("provider success without message id is not counted as delivery", async () => {
  const client: BookingConfirmationRpcClient = {
    rpc: async (name, params) => {
      if (name === "claim_subscription_trial_emails") {
        return {
          data: [claim],
          error: null,
        };
      }
      if (name === "prepare_subscription_trial_email") {
        return {
          data: [prepared],
          error: null,
        };
      }
      equal(params?.p_sent, false);
      return { data: "pending", error: null };
    },
  };
  const result = await drainSubscriptionTrialEmails({
    client,
    config,
    fetcher: () => Promise.resolve(new Response("{}", { status: 200 })),
  });
  equal(result.sent, 0);
  equal(result.pending, 1);
});
