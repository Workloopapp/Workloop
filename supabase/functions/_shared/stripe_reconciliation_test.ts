import {
  currentCheckoutUpdate,
  currentIntentUpdate,
} from "./stripe_reconciliation.ts";
const transaction = {
  amount_minor: 2500,
  currency: "gbp",
  workspace_id: "workspace-1",
  invoice_id: "invoice-1",
};
const metadata = {
  workloop_workspace_id: "workspace-1",
  workloop_invoice_id: "invoice-1",
};
function paidIntent(extra = {}) {
  return {
    id: "pi_1",
    status: "succeeded",
    amount: 2500,
    amount_received: 2500,
    currency: "gbp",
    livemode: false,
    metadata,
    latest_charge: {
      id: "ch_1",
      amount_refunded: 0,
      created: 1000,
      receipt_url: "https://pay.stripe.com/receipt",
    },
    ...extra,
  };
}
Deno.test("late intent events preserve current paid state and hydrate receipts", async () => {
  const update = await currentIntentUpdate(
    "pi_1",
    transaction,
    false,
    () => paidIntent(),
  );
  if (
    update.status !== "succeeded" ||
    update.receipt_url !== "https://pay.stripe.com/receipt"
  ) throw new Error("Payment/receipt lost");
});
Deno.test("late checkout completion retains a refund rather than restoring income", async () => {
  const update = await currentCheckoutUpdate(
    "cs_1",
    transaction,
    false,
    (path) =>
      path.includes("checkout")
        ? {
          amount_total: 2500,
          currency: "gbp",
          livemode: false,
          metadata,
          payment_intent: "pi_1",
        }
        : paidIntent({
          latest_charge: { id: "ch_1", amount_refunded: 2500, created: 1000 },
        }),
  );
  if (update.status !== "refunded" || update.amount_refunded_minor !== 2500) {
    throw new Error("Refund was reverted");
  }
});
Deno.test("partial refunds remain deducted when payment success is redelivered", async () => {
  const update = await currentIntentUpdate(
    "pi_1",
    transaction,
    false,
    () =>
      paidIntent({
        latest_charge: { id: "ch_1", amount_refunded: 500, created: 1000 },
      }),
  );
  if (
    update.status !== "partially_refunded" ||
    update.amount_refunded_minor !== 500
  ) throw new Error("Partial refund lost");
});
Deno.test("current dispute outcome governs late payment and dispute snapshots", async () => {
  for (const outcome of ["needs_response", "lost", "won"]) {
    const update = await currentIntentUpdate(
      "pi_1",
      transaction,
      false,
      (path) =>
        path.startsWith("/v1/disputes")
          ? { data: [{ status: outcome }], has_more: false }
          : paidIntent({
            latest_charge: {
              id: "ch_1",
              amount_refunded: 0,
              created: 1000,
              disputed: true,
            },
          }),
    );
    if (update.status !== (outcome === "won" ? "succeeded" : "disputed")) {
      throw new Error("Wrong dispute outcome");
    }
  }
});
Deno.test("provider reconciliation rejects tenant, mode, currency and amount mismatches", async () => {
  for (
    const extra of [
      { metadata: { ...metadata, workloop_workspace_id: "other" } },
      { metadata: { ...metadata, workloop_invoice_id: "other" } },
      { livemode: true },
      { currency: "usd" },
      { amount: 2600 },
      { amount_received: 2400 },
    ]
  ) {
    let rejected = false;
    try {
      await currentIntentUpdate(
        "pi_1",
        transaction,
        false,
        () => paidIntent(extra),
      );
    } catch (_) {
      rejected = true;
    }
    if (!rejected) throw new Error("Mismatched payment accepted");
  }
});
Deno.test("expired Checkout remains pending until the provider confirms expiry", async () => {
  for (const status of ["open", "expired"]) {
    const update = await currentCheckoutUpdate(
      "cs_1",
      transaction,
      false,
      () => ({
        amount_total: 2500,
        currency: "gbp",
        livemode: false,
        metadata,
        status,
      }),
    );
    if (update.status !== (status === "expired" ? "cancelled" : "pending")) {
      throw new Error("Wrong checkout state");
    }
  }
});
Deno.test("reconciliation retains the original received timestamp on retries", async () => {
  const paid_at = "2026-09-01T10:00:00Z";
  const update = await currentIntentUpdate(
    "pi_1",
    { ...transaction, paid_at },
    false,
    () => paidIntent(),
  );
  if (update.paid_at !== paid_at) {
    throw new Error("Received date changed on retry");
  }
});

Deno.test("expired checkout closes an uncollected intent but preserves a completed charge", async () => {
  for (const succeeded of [false, true]) {
    const update = await currentCheckoutUpdate(
      "cs_1",
      transaction,
      false,
      (path) =>
        path.includes("checkout")
          ? {
            amount_total: 2500,
            currency: "gbp",
            livemode: false,
            metadata,
            status: "expired",
            payment_intent: "pi_1",
          }
          : paidIntent(
            succeeded ? {} : {
              status: "requires_payment_method",
              amount_received: 0,
              latest_charge: null,
            },
          ),
    );
    if (update.status !== (succeeded ? "succeeded" : "cancelled")) {
      throw new Error("Expired checkout was reconciled incorrectly");
    }
  }
});

Deno.test("failed or cancelled refunds are not reported as pending acceptance", async () => {
  const { currentRefundStatus } = await import("./stripe_reconciliation.ts");
  for (
    const [provider, expected] of [
      ["failed", "failed"],
      ["canceled", "cancelled"],
      ["succeeded", "succeeded"],
      ["pending", "pending"],
      ["requires_action", "pending"],
    ]
  ) {
    if (currentRefundStatus(provider) !== expected) {
      throw new Error("Incorrect refund outcome");
    }
  }
});
