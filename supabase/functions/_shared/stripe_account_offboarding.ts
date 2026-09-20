import { StripeApiError, stripeRequest } from "./stripe_api.ts";

type Json = Record<string, unknown>;

type StripeRequestOptions = {
  method?: "GET" | "POST";
  json?: unknown;
};

export type StripeRequester = <T>(
  secretKey: string,
  path: string,
  options?: StripeRequestOptions,
) => Promise<T>;

const supportedConfigurations = new Set(["customer", "merchant", "recipient"]);

function stringArray(value: unknown) {
  if (!Array.isArray(value)) return [] as string[];
  return value.filter((item): item is string =>
    typeof item === "string" && supportedConfigurations.has(item)
  );
}

function assertMatchingKeyMode(secretKey: string, mode: string) {
  const matches = mode === "live"
    ? secretKey.startsWith("sk_live_")
    : mode === "test" && secretKey.startsWith("sk_test_");
  if (!matches) {
    throw new Error("Stripe account mode does not match the configured key");
  }
}

// Stripe-owned Standard accounts must retain their independent Stripe account.
// Revoke only Workloop's access when Stripe explicitly requires that path.
async function disconnectStandardAccount(
  secretKey: string,
  accountId: string,
  clientId: string,
  fetcher: typeof fetch,
) {
  if (!/^ca_[A-Za-z0-9]+$/.test(clientId)) {
    throw new Error(
      "Stripe Connect client ID is not configured for offboarding",
    );
  }
  const response = await fetcher(
    "https://connect.stripe.com/oauth/deauthorize",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        client_id: clientId,
        stripe_user_id: accountId,
      }),
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.stripe_user_id !== accountId) {
    // invalid_client can also mean wrong mode or platform: never treat it as
    // evidence that access was revoked, and never skip deletion safeguards.
    throw new StripeApiError(
      "Stripe did not confirm account disconnection",
      response.status,
      typeof payload.error === "string" ? payload.error : undefined,
    );
  }
  return { alreadyClosed: false, disconnected: true };
}

// GET makes already-closed configurations safe to retry. A successful Standard
// disconnection is checkpointed by the caller before local deletion begins.
export async function closeWorkloopStripeAccount(
  secretKey: string,
  accountId: string,
  mode: string,
  request: StripeRequester = stripeRequest,
  connectClientId = "",
  fetcher: typeof fetch = fetch,
) {
  assertMatchingKeyMode(secretKey, mode);
  if (!/^acct_[A-Za-z0-9]+$/.test(accountId)) {
    throw new Error("Invalid Stripe account identifier");
  }

  const account = await request<Json>(
    secretKey,
    `/v2/core/accounts/${encodeURIComponent(accountId)}`,
  );
  if (account.closed === true) return { alreadyClosed: true };

  const appliedConfigurations = stringArray(account.applied_configurations);
  if (appliedConfigurations.length === 0) {
    throw new Error("Stripe account has no closeable configuration");
  }

  let closed: Json;
  try {
    closed = await request<Json>(
      secretKey,
      `/v2/core/accounts/${encodeURIComponent(accountId)}/close`,
      {
        method: "POST",
        json: { applied_configurations: appliedConfigurations },
      },
    );
  } catch (error) {
    if (
      error instanceof StripeApiError &&
      error.code === "stripe_loss_liable_cannot_be_deleted"
    ) {
      return disconnectStandardAccount(
        secretKey,
        accountId,
        connectClientId,
        fetcher,
      );
    }
    throw error;
  }
  if (closed.closed !== true) {
    throw new Error("Stripe did not confirm account offboarding");
  }
  return { alreadyClosed: false };
}
