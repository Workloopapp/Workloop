type Json = Record<string, unknown>;
export type StripeReader = (path: string) => Promise<Json> | Json;

export function stripeObject(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

export function stripeId(value: unknown): string {
  return typeof value === "string"
    ? value
    : String(stripeObject(value).id ?? "");
}

function requireIdentity(object: Json, transaction: Json, liveMode: boolean) {
  const metadata = stripeObject(object.metadata);
  if (
    object.livemode !== liveMode || object.currency !== transaction.currency ||
    Number(object.amount ?? object.amount_total) !==
      Number(transaction.amount_minor) ||
    metadata.workloop_workspace_id !== transaction.workspace_id ||
    metadata.workloop_invoice_id !== transaction.invoice_id
  ) {
    throw new Error("Stripe payment does not match the recorded transaction");
  }
}

// Event snapshots may arrive in any order. Read the current provider object,
// including its charge, instead of applying the historical event status.
export async function currentIntentUpdate(
  intentId: string,
  transaction: Json,
  liveMode: boolean,
  read: StripeReader,
): Promise<Json> {
  if (!/^pi_[A-Za-z0-9_]+$/.test(intentId)) {
    throw new Error("Invalid Stripe payment identity");
  }
  const intent = await read(
    `/v1/payment_intents/${intentId}?expand[]=latest_charge`,
  );
  requireIdentity(intent, transaction, liveMode);
  const charge = typeof intent.latest_charge === "string"
    ? await read(`/v1/charges/${intent.latest_charge}`)
    : stripeObject(intent.latest_charge);
  const amount = Number(transaction.amount_minor);
  const refunded = Number(charge.amount_refunded ?? 0);
  if (!Number.isSafeInteger(refunded) || refunded < 0 || refunded > amount) {
    throw new Error("Invalid Stripe refund balance");
  }
  const succeeded = intent.status === "succeeded";
  if (succeeded && Number(intent.amount_received) !== amount) {
    throw new Error("Stripe received amount does not match the transaction");
  }
  let status = succeeded
    ? "succeeded"
    : intent.status === "processing"
    ? "processing"
    : intent.status === "canceled"
    ? "cancelled"
    : intent.status === "requires_payment_method"
    ? "requires_payment_method"
    : "pending";
  let dispute: Json | undefined;
  if (charge.disputed === true) {
    const disputes = await read(
      `/v1/disputes?charge=${stripeId(charge)}&limit=100`,
    );
    if (
      disputes.has_more === true || !Array.isArray(disputes.data) ||
      !disputes.data.length
    ) {
      throw new Error("Could not determine current Stripe dispute status");
    }
    dispute = disputes.data.map(stripeObject).find((item) =>
      item.status !== "won" && item.status !== "warning_closed"
    );
  }
  if (refunded > 0) {
    status = refunded >= amount ? "refunded" : "partially_refunded";
  }
  if (dispute) status = "disputed";
  const lastError = stripeObject(intent.last_payment_error);
  const paidAt = transaction.paid_at ??
    (succeeded && Number.isFinite(Number(charge.created))
      ? new Date(Number(charge.created) * 1000).toISOString()
      : null);
  return {
    stripe_payment_intent_id: intentId,
    stripe_charge_id: stripeId(charge) || null,
    amount_refunded_minor: refunded,
    status,
    receipt_url: typeof charge.receipt_url === "string"
      ? charge.receipt_url
      : null,
    failure_code: dispute
      ? (dispute.status === "lost" ? "dispute_lost" : "disputed")
      : succeeded
      ? null
      : lastError.code ?? null,
    failure_message: dispute
      ? (dispute.status === "lost"
        ? "The card dispute was lost."
        : "This payment is under dispute.")
      : succeeded
      ? null
      : lastError.message ?? null,
    paid_at: paidAt,
  };
}

export async function currentCheckoutUpdate(
  sessionId: string,
  transaction: Json,
  liveMode: boolean,
  read: StripeReader,
): Promise<Json> {
  if (!/^cs_[A-Za-z0-9_]+$/.test(sessionId)) {
    throw new Error("Invalid checkout identity");
  }
  const session = await read(`/v1/checkout/sessions/${sessionId}`);
  requireIdentity(session, transaction, liveMode);
  const intentId = stripeId(session.payment_intent);
  if (intentId) {
    const update = await currentIntentUpdate(
      intentId,
      transaction,
      liveMode,
      read,
    );
    if (
      session.status === "expired" &&
      ["pending", "requires_payment_method", "cancelled"].includes(
        String(update.status),
      )
    ) {
      return { ...update, status: "cancelled" };
    }
    return update;
  }
  if (session.payment_status === "paid") {
    throw new Error("Paid checkout has no payment identity");
  }
  return { status: session.status === "expired" ? "cancelled" : "pending" };
}

export function currentRefundStatus(status: unknown) {
  return status === "succeeded"
    ? "succeeded"
    : status === "failed"
    ? "failed"
    : status === "canceled"
    ? "cancelled"
    : "pending";
}
