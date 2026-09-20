type Handler = (request: Request) => Promise<Response>;
let handler: Handler;
const originalServe = Deno.serve;
try {
  Deno.serve = ((callback: Handler) => {
    handler = callback;
  }) as unknown as typeof Deno.serve;
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
}

const workspace = "11111111-1111-4111-8111-111111111111";
const invoiceId = "22222222-2222-4222-8222-222222222222";
const documentId = "33333333-3333-4333-8333-333333333333";
const operationKey = "payment-link-operation-123";

async function exercise(options: {
  document?: boolean;
  contact?: boolean;
  email?: string;
  failRecipient?: boolean;
  missingUrl?: boolean;
  failStripe?: boolean;
  existingCheckout?: "open" | "expired";
}) {
  const originalFetch = globalThis.fetch;
  const environment: Record<string, string> = {
    SUPABASE_URL: "https://project.example.com",
    SUPABASE_ANON_KEY: "anon-test",
    SUPABASE_SERVICE_ROLE_KEY: "service-test-secret-with-thirty-two-characters",
    STRIPE_SECRET_KEY: "sk_test_fixture",
    WORKLOOP_PAYMENTS_BETA_ENABLED: "true",
    STRIPE_CHECKOUT_SUCCESS_URL: options.missingUrl
      ? ""
      : "https://workloop.uk/success",
    STRIPE_CHECKOUT_CANCEL_URL: "https://workloop.uk/cancel",
    WORKLOOP_PLATFORM_FEE_ENABLED: "false",
  };
  const previous = new Map(
    Object.keys(environment).map((key) => [key, Deno.env.get(key)]),
  );
  for (const [key, value] of Object.entries(environment)) {
    Deno.env.set(key, value);
  }
  const requests: string[] = [];
  let reserved = false;
  let checkoutForm: URLSearchParams | undefined;
  let checkoutKey: string | null = null;
  let reconciledStatus = "requires_payment_method";
  const nextKey = `${operationKey}-next`;
  const json = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    requests.push(url.pathname + url.search);
    if (url.pathname === "/auth/v1/user") {
      return Promise.resolve(
        json({ id: workspace, email: "owner@example.com" }),
      );
    }
    if (url.pathname.endsWith("/current_user_meets_mfa_policy")) {
      return Promise.resolve(json(true));
    }
    if (url.pathname.endsWith("/workspace_members")) {
      return Promise.resolve(json({ workspace_id: workspace }));
    }
    if (url.pathname === "/v1/accounts/acct_example") {
      return Promise.resolve(
        json({
          details_submitted: true,
          charges_enabled: true,
          payouts_enabled: true,
        }),
      );
    }
    if (url.pathname.endsWith("/workspace_payment_accounts")) {
      return Promise.resolve(
        json({
          stripe_account_id: "acct_example",
          mode: "test",
          charges_enabled: true,
          payouts_enabled: true,
          onboarding_status: "ready",
        }),
      );
    }
    if (url.pathname.endsWith("/invoices")) {
      return Promise.resolve(json({
        id: invoiceId,
        workspace_id: workspace,
        invoice_number: "INV-001",
        total: 50,
        amount_paid: 0,
        status: "sent",
        contact_id: options.contact ? workspace : null,
        appointment_id: null,
        source_document_id: options.document === false ? null : documentId,
      }));
    }
    if (
      url.pathname.endsWith("/business_documents") ||
      url.pathname.endsWith("/contacts")
    ) {
      if (reserved) {
        throw new Error("Recipient must be resolved before reservation");
      }
      if (options.failRecipient) {
        return Promise.resolve(
          json({ code: "42501", message: "permission denied" }, 403),
        );
      }
      return Promise.resolve(
        json(
          url.pathname.endsWith("/business_documents")
            ? {
              client_snapshot: { email: options.email ?? "saved@example.com" },
            }
            : { email: "changed-contact@example.com" },
        ),
      );
    }
    if (url.pathname.endsWith("/reserve_stripe_collection")) {
      reserved = true;
      return Promise.resolve(
        json({
          // Mirrors the existing SQL: terminal operations discard the old
          // reservation and a retry of their request key gets a fresh key.
          idempotencyKey: reconciledStatus === "cancelled"
            ? nextKey
            : operationKey,
          amountMinor: 5000,
        }),
      );
    }
    if (url.pathname === "/v1/checkout/sessions/cs_existing") {
      return Promise.resolve(json({
        status: options.existingCheckout,
        payment_status: "unpaid",
        livemode: false,
        currency: "gbp",
        amount_total: 5000,
        metadata: {
          workloop_workspace_id: workspace,
          workloop_invoice_id: invoiceId,
        },
      }));
    }
    if (url.pathname === "/v1/checkout/sessions") {
      checkoutForm = new URLSearchParams(String(init?.body));
      checkoutKey = new Headers(init?.headers).get("Idempotency-Key");
      if (!reserved) throw new Error("Stripe collection needs the reservation");
      if (options.failStripe) {
        throw new TypeError("Response lost after Stripe accepted");
      }
      return Promise.resolve(
        json({ id: "cs_test", url: "https://checkout.stripe.com/example" }),
      );
    }
    if (url.pathname.endsWith("/payment_transactions")) {
      if (init?.method === "PATCH") {
        reconciledStatus = JSON.parse(String(init.body)).status;
        return Promise.resolve(json({ id: "existing-transaction" }));
      }
      if (init?.method === "POST") {
        return Promise.resolve(
          json({ id: "transaction", idempotency_key: operationKey }),
        );
      }
      if (reserved) {
        throw new Error("No fallible transaction lookup after reservation");
      }
      return Promise.resolve(json(
        options.existingCheckout
          ? [{
            id: "existing-transaction",
            workspace_id: workspace,
            invoice_id: invoiceId,
            idempotency_key: operationKey,
            stripe_checkout_session_id: "cs_existing",
            collection_method: "payment_link",
            status: "requires_payment_method",
            amount_minor: 5000,
            currency: "gbp",
            updated_at: "2026-09-12T10:00:00Z",
            metadata: { checkout_url: "https://checkout.stripe.com/existing" },
          }]
          : [],
      ));
    }
    throw new Error(`Unexpected request ${url.pathname}`);
  }) as typeof fetch;
  try {
    const response = await handler(
      new Request("https://function.example.com", {
        method: "POST",
        headers: { Authorization: "Bearer test" },
        body: JSON.stringify({
          action: "createPaymentLink",
          workspaceId: workspace,
          invoiceId,
          idempotencyKey: operationKey,
          receiptEmail: "attacker@example.com",
        }),
      }),
    );
    return {
      status: response.status,
      body: await response.json(),
      requests,
      reserved,
      checkoutForm,
      checkoutKey,
    };
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("manually addressed invoice uses its frozen recipient and creates a link", async () => {
  const result = await exercise({});
  if (
    result.status !== 200 ||
    result.checkoutForm?.get("customer_email") !== "saved@example.com"
  ) throw new Error(JSON.stringify(result));
  if (result.requests.some((url) => url.includes("/contacts"))) {
    throw new Error("Optional contact was queried");
  }
});

Deno.test("issued snapshot wins over a changed saved contact", async () => {
  const result = await exercise({ contact: true });
  if (result.checkoutForm?.get("customer_email") !== "saved@example.com") {
    throw new Error("Frozen email was not retained");
  }
});

Deno.test("legacy invoice without contact can use checkout without a pinned email", async () => {
  const result = await exercise({ document: false });
  if (result.status !== 200 || result.checkoutForm?.has("customer_email")) {
    throw new Error(JSON.stringify(result));
  }
  if (result.requests.some((url) => url.includes("/contacts"))) {
    throw new Error("Null contact was queried");
  }
});

Deno.test("recipient/configuration failures leave collection unreserved", async () => {
  for (const options of [{ failRecipient: true }, { missingUrl: true }]) {
    const result = await exercise(options);
    if (result.status === 200 || result.reserved || result.checkoutForm) {
      throw new Error("Preflight stranded a reservation");
    }
  }
});

Deno.test("uncertain Stripe response retains the reservation for idempotent recovery", async () => {
  const result = await exercise({ failStripe: true });
  if (result.status === 200 || !result.reserved || !result.checkoutForm) {
    throw new Error("Uncertain outcome lost its collection guard");
  }
  if (result.requests.some((url) => /release|delete/.test(url))) {
    throw new Error("Uncertain Stripe operation was released");
  }
});

Deno.test("existing checkout reuses the matching operation with reconciled status", async () => {
  const result = await exercise({ existingCheckout: "open" });
  if (
    result.status !== 200 || result.body.reused !== true ||
    result.checkoutForm ||
    result.body.transaction.status !== "pending" ||
    result.body.url !== "https://checkout.stripe.com/existing"
  ) throw new Error(JSON.stringify(result));
});

Deno.test("expired checkout cannot return a stale link after reservation rotates", async () => {
  const result = await exercise({ existingCheckout: "expired" });
  if (
    result.status !== 200 || result.body.reused || !result.checkoutForm ||
    result.checkoutKey !== `${operationKey}-next` ||
    result.body.url !== "https://checkout.stripe.com/example"
  ) throw new Error(JSON.stringify(result));
});
