import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  closeWorkloopStripeAccount,
  type StripeRequester,
} from "./stripe_account_offboarding.ts";
import { StripeApiError } from "./stripe_api.ts";

const standardRequest: StripeRequester = <T>(_secret: string, path: string) => {
  if (path.endsWith("/close")) {
    return Promise.reject(
      new StripeApiError(
        "Standard account",
        400,
        "stripe_loss_liable_cannot_be_deleted",
      ),
    );
  }
  return Promise.resolve(
    { closed: false, applied_configurations: ["merchant"] } as T,
  );
};

Deno.test("Standard live account revokes platform access without closing independent Stripe account", async () => {
  let calls = 0;
  const fakeFetch: typeof fetch = (input, init) => {
    calls++;
    assertEquals(input, "https://connect.stripe.com/oauth/deauthorize");
    assertEquals(init?.method, "POST");
    assertEquals(
      new Headers(init?.headers).get("Authorization"),
      "Bearer sk_live_private",
    );
    assertEquals(
      String(init?.body),
      "client_id=ca_Workloop&stripe_user_id=acct_Workloop123",
    );
    return Promise.resolve(
      Response.json({ stripe_user_id: "acct_Workloop123" }),
    );
  };
  assertEquals(
    await closeWorkloopStripeAccount(
      "sk_live_private",
      "acct_Workloop123",
      "live",
      standardRequest,
      "ca_Workloop",
      fakeFetch,
    ),
    { alreadyClosed: false, disconnected: true },
  );
  assertEquals(calls, 1);
});

Deno.test("Standard offboarding without Connect client ID fails before OAuth request", async () => {
  await assertRejects(
    () =>
      closeWorkloopStripeAccount(
        "sk_live_private",
        "acct_Workloop123",
        "live",
        standardRequest,
      ),
    Error,
    "client ID is not configured",
  );
});

Deno.test("unrelated Stripe errors never fall through to disconnection", async () => {
  const fail: StripeRequester = () =>
    Promise.reject(
      new StripeApiError("balance present", 400, "account_has_balance"),
    );
  await assertRejects(
    () =>
      closeWorkloopStripeAccount(
        "sk_live_private",
        "acct_Workloop123",
        "live",
        fail,
        "ca_Workloop",
      ),
    StripeApiError,
    "balance present",
  );
});

for (
  const [label, status, body] of [
    ["wrong returned account", 200, { stripe_user_id: "acct_Other" }],
    ["unknown platform or already disconnected", 400, {
      error: "invalid_client",
    }],
    ["provider failure", 500, { error: "server_error" }],
  ] as const
) {
  Deno.test(`Standard offboarding fails closed on ${label}`, async () => {
    const fakeFetch: typeof fetch = () =>
      Promise.resolve(Response.json(body, { status }));
    await assertRejects(
      () =>
        closeWorkloopStripeAccount(
          "sk_live_private",
          "acct_Workloop123",
          "live",
          standardRequest,
          "ca_Workloop",
          fakeFetch,
        ),
      StripeApiError,
      "did not confirm",
    );
  });
}

Deno.test("closes every configuration on a Workloop Accounts v2 account", async () => {
  const calls: Array<{ path: string; options: unknown }> = [];
  const request: StripeRequester = <T>(
    _secret: string,
    path: string,
    options?: unknown,
  ) => {
    calls.push({ path, options });
    return Promise.resolve(
      (calls.length === 1
        ? { closed: false, applied_configurations: ["merchant", "recipient"] }
        : { closed: true }) as T,
    );
  };

  const result = await closeWorkloopStripeAccount(
    "sk_test_private",
    "acct_Workloop123",
    "test",
    request,
  );

  assertEquals(result, { alreadyClosed: false });
  assertEquals(calls, [
    { path: "/v2/core/accounts/acct_Workloop123", options: undefined },
    {
      path: "/v2/core/accounts/acct_Workloop123/close",
      options: {
        method: "POST",
        json: { applied_configurations: ["merchant", "recipient"] },
      },
    },
  ]);
});

Deno.test("already closed Stripe accounts are an idempotent success", async () => {
  const request: StripeRequester = <T>() =>
    Promise.resolve({ closed: true } as T);
  const result = await closeWorkloopStripeAccount(
    "sk_live_private",
    "acct_Workloop123",
    "live",
    request,
  );
  assertEquals(result, { alreadyClosed: true });
});

Deno.test("offboarding rejects a key/account mode mismatch", async () => {
  await assertRejects(
    () =>
      closeWorkloopStripeAccount(
        "sk_test_private",
        "acct_Workloop123",
        "live",
      ),
    Error,
    "mode does not match",
  );
});
