import { createClient } from "@supabase/supabase-js";
import { stripeRequest, verifyStripeSignature } from "../_shared/stripe_api.ts";
import {
  currentCheckoutUpdate,
  currentIntentUpdate,
  currentRefundStatus,
} from "../_shared/stripe_reconciliation.ts";

type Json = Record<string, unknown>;

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function stringValue(value: unknown, maxLength = 200) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function objectValue(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function idValue(value: unknown) {
  if (typeof value === "string") return value;
  return stringValue(objectValue(value).id);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (
    !supabaseUrl || serviceRoleKey.length < 32 ||
    !webhookSecret.startsWith("whsec_") || !stripeSecret.startsWith("sk_")
  ) {
    return jsonResponse(503, { error: "Webhook is not configured" });
  }

  const rawBody = await req.text();
  const signature = req.headers.get("Stripe-Signature") ?? "";
  if (!await verifyStripeSignature(rawBody, signature, webhookSecret)) {
    return jsonResponse(400, { error: "Invalid signature" });
  }

  let event: Json;
  try {
    event = JSON.parse(rawBody) as Json;
  } catch (_) {
    return jsonResponse(400, { error: "Invalid event" });
  }
  const eventId = stringValue(event.id, 120);
  const eventType = stringValue(event.type, 120);
  const accountId = stringValue(event.account, 100);
  if (!eventId.startsWith("evt_") || !eventType) {
    return jsonResponse(400, { error: "Invalid event" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: claimed, error: claimError } = await supabase.rpc(
    "claim_stripe_webhook_event",
    {
      p_event_id: eventId,
      p_account_id: accountId || null,
      p_event_type: eventType,
      p_livemode: event.livemode === true,
      p_payload: event,
    },
  );
  if (claimError) {
    console.error("stripe_webhook_claim_failed", {
      eventId,
      code: claimError.code,
    });
    return jsonResponse(500, { error: "Could not record event" });
  }
  if (claimed !== true) {
    return jsonResponse(200, { received: true, duplicate: true });
  }

  async function finish(
    status: "processed" | "ignored" | "failed",
    message?: string,
  ) {
    const { error } = await supabase.rpc("finish_stripe_webhook_event", {
      p_event_id: eventId,
      p_status: status,
      p_error_message: message?.slice(0, 1000) ?? null,
    });
    if (error) throw error;
  }

  const object = objectValue(objectValue(event.data).object);
  try {
    const targetAccountId = eventType === "account.updated"
      ? stringValue(object.id)
      : accountId;
    const { data: paymentAccount, error: accountError } = await supabase
      .from("workspace_payment_accounts").select(
        "workspace_id, mode, updated_at",
      )
      .eq("stripe_account_id", targetAccountId).maybeSingle();
    if (accountError) throw accountError;
    if (
      !paymentAccount ||
      paymentAccount.mode !== (event.livemode === true ? "live" : "test") ||
      (stripeSecret.startsWith("sk_live_") !== (event.livemode === true))
    ) {
      await finish("ignored");
      return jsonResponse(200, { received: true });
    }
    const readStripe = (path: string) =>
      stripeRequest<Json>(stripeSecret, path, { accountId: targetAccountId });
    const liveMode = event.livemode === true;
    const findTransaction = async (field: string, id: string) => {
      const { data, error } = await supabase.from("payment_transactions")
        .select("*")
        .eq("stripe_account_id", targetAccountId).eq(
          "workspace_id",
          paymentAccount!.workspace_id,
        )
        .eq(field, id).maybeSingle();
      if (error) throw error;
      if (!data) {
        let metadata = objectValue(object.metadata);
        if (
          field === "stripe_payment_intent_id" && id.startsWith("pi_") &&
          metadata.workloop_workspace_id !== paymentAccount!.workspace_id
        ) {
          metadata = objectValue(
            (await readStripe(`/v1/payment_intents/${id}`)).metadata,
          );
        }
        // A Workloop event can beat transaction creation or Checkout-to-intent
        // linking. Return a retryable error rather than permanently losing it.
        if (metadata.workloop_workspace_id === paymentAccount!.workspace_id) {
          throw new Error(
            "Workloop transaction is not recorded yet; retry delivery",
          );
        }
      }
      return data as Json | null;
    };
    const updateTransaction = async (transaction: Json, update: Json) => {
      const { data, error } = await supabase.from("payment_transactions")
        .update({ ...update, updated_at: new Date().toISOString() })
        .eq("id", transaction.id).eq("stripe_account_id", targetAccountId)
        .eq("updated_at", transaction.updated_at).select("id").maybeSingle();
      if (error) throw error;
      if (!data) {
        throw new Error(
          "Payment changed during reconciliation; retry delivery",
        );
      }
    };
    let handled = true;
    if (eventType === "account.updated") {
      const account = await stripeRequest<Json>(
        stripeSecret,
        `/v1/accounts/${targetAccountId}`,
      );
      const requirements = objectValue(account.requirements);
      const ready = account.charges_enabled === true &&
        account.payouts_enabled === true && account.details_submitted === true;
      const { data, error } = await supabase.from("workspace_payment_accounts")
        .update({
          onboarding_status: requirements.disabled_reason
            ? "restricted"
            : ready
            ? "ready"
            : "pending",
          details_submitted: account.details_submitted === true,
          charges_enabled: account.charges_enabled === true,
          payouts_enabled: account.payouts_enabled === true,
          requirements_due: Array.isArray(requirements.currently_due)
            ? requirements.currently_due.filter((item) =>
              typeof item === "string"
            )
            : [],
          last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("stripe_account_id", targetAccountId).eq(
          "updated_at",
          paymentAccount.updated_at,
        ).select("workspace_id").maybeSingle();
      if (error) throw error;
      if (!data) {
        throw new Error(
          "Account changed during reconciliation; retry delivery",
        );
      }
    } else if (eventType.startsWith("checkout.session.")) {
      const sessionId = stringValue(object.id);
      const transaction = await findTransaction(
        "stripe_checkout_session_id",
        sessionId,
      );
      if (!transaction) handled = false;
      else {await updateTransaction(
          transaction,
          await currentCheckoutUpdate(
            sessionId,
            transaction,
            liveMode,
            readStripe,
          ),
        );}
    } else if (
      eventType.startsWith("refund.") || eventType.startsWith("charge.refund.")
    ) {
      const refundId = stringValue(object.id);
      const refund = await readStripe(`/v1/refunds/${refundId}`);
      const intentId = idValue(refund.payment_intent);
      const transaction = await findTransaction(
        "stripe_payment_intent_id",
        intentId,
      );
      if (!transaction) handled = false;
      else {
        if (
          refund.currency !== transaction.currency ||
          !Number.isSafeInteger(refund.amount) || Number(refund.amount) <= 0 ||
          Number(refund.amount) > Number(transaction.amount_minor)
        ) {
          throw new Error("Refund does not match the recorded transaction");
        }
        const { data: previous, error: previousError } = await supabase.from(
          "payment_refunds",
        )
          .select("id, updated_at").eq("stripe_refund_id", refundId)
          .maybeSingle();
        if (previousError) throw previousError;
        const metadata = objectValue(refund.metadata);
        const refundKey = stringValue(metadata.workloop_idempotency_key, 128);
        const values = {
          workspace_id: transaction.workspace_id,
          transaction_id: transaction.id,
          stripe_refund_id: refundId,
          amount_minor: refund.amount,
          status: currentRefundStatus(refund.status),
          reason: stringValue(refund.reason) || null,
          failure_reason: stringValue(refund.failure_reason) || null,
          ...(refundKey.length >= 16 ? { idempotency_key: refundKey } : {}),
          updated_at: new Date().toISOString(),
        };
        const write = previous
          ? supabase.from("payment_refunds").update(values).eq(
            "id",
            previous.id,
          ).eq("updated_at", previous.updated_at)
          : supabase.from("payment_refunds").insert(values);
        const { data: saved, error } = await write.select("id").maybeSingle();
        if (error) throw error;
        if (!saved) {
          throw new Error(
            "Refund changed during reconciliation; retry delivery",
          );
        }
        await updateTransaction(
          transaction,
          await currentIntentUpdate(
            intentId,
            transaction,
            liveMode,
            readStripe,
          ),
        );
      }
    } else if (
      eventType.startsWith("payment_intent.") || eventType.startsWith("charge.")
    ) {
      const intentId = eventType.startsWith("payment_intent.")
        ? stringValue(object.id)
        : idValue(object.payment_intent);
      if (!intentId) handled = false;
      else {
        const transaction = await findTransaction(
          "stripe_payment_intent_id",
          intentId,
        );
        if (!transaction) handled = false;
        else {await updateTransaction(
            transaction,
            await currentIntentUpdate(
              intentId,
              transaction,
              liveMode,
              readStripe,
            ),
          );}
      }
    } else handled = false;

    await finish(handled ? "processed" : "ignored");
    return jsonResponse(200, { received: true });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Unknown webhook error";
    console.error("stripe_webhook_processing_failed", {
      eventId,
      eventType,
      message,
    });
    try {
      await finish("failed", message);
    } catch (finishError) {
      console.error("stripe_webhook_failure_record_failed", {
        eventId,
        message: finishError instanceof Error ? finishError.message : "unknown",
      });
    }
    return jsonResponse(500, { error: "Webhook processing failed" });
  }
});
