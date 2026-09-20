import { createClient } from "@supabase/supabase-js";
import {
  publicStripeError,
  safePlatformFeeMinor,
  StripeApiError,
  stripeRequest,
} from "../_shared/stripe_api.ts";
import {
  requireMatchingPaymentOperation,
  requireRefundWithinBalance,
  requireStripeIdempotencyKey,
} from "../_shared/stripe_idempotency.ts";
import {
  currentCheckoutUpdate,
  currentIntentUpdate,
  currentRefundStatus,
} from "../_shared/stripe_reconciliation.ts";
import { paymentLinkReceiptEmail } from "./receipt_email.ts";
import { paymentsBetaEnabled } from "../_shared/payments_beta_gate.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json = Record<string, unknown>;

function response(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function stringValue(value: unknown, maxLength = 160) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function objectValue(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function optionalReceiptEmail(value: unknown) {
  const email = stringValue(value, 255).toLowerCase();
  if (!email) return "";
  if (
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error("Enter a valid receipt email or leave it blank");
  }
  return email;
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function requireConfiguredUrl(name: string) {
  const value = Deno.env.get(name) ?? "";
  if (!value.startsWith("https://")) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}

function accountStatus(account: Json) {
  const requirements = account.requirements as Json | undefined;
  const disabledReason = stringValue(requirements?.disabled_reason, 200);
  const detailsSubmitted = account.details_submitted === true;
  const chargesEnabled = account.charges_enabled === true;
  const payoutsEnabled = account.payouts_enabled === true;
  return {
    detailsSubmitted,
    chargesEnabled,
    payoutsEnabled,
    onboardingStatus: disabledReason
      ? "restricted"
      : chargesEnabled && payoutsEnabled && detailsSubmitted
      ? "ready"
      : "pending",
    requirementsDue: Array.isArray(requirements?.currently_due)
      ? requirements.currently_due.filter((value) => typeof value === "string")
      : [],
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }
  if (!paymentsBetaEnabled()) {
    return response(503, {
      error: "Payments are not available during this beta",
      code: "payments_beta_disabled",
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const liveMode = stripeSecretKey.startsWith("sk_live_");
  if (
    !supabaseUrl || !anonKey || serviceRoleKey.length < 32 ||
    !stripeSecretKey.startsWith("sk_")
  ) {
    return response(503, { error: "Payments are not configured yet" });
  }
  if (liveMode && Deno.env.get("STRIPE_LIVE_MODE_ALLOWED") !== "true") {
    return response(503, { error: "Live payments require explicit approval" });
  }

  let payload: Json;
  try {
    payload = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }
  const action = stringValue(payload.action, 48);
  const workspaceId = stringValue(payload.workspaceId, 64);
  if (!isUuid(workspaceId)) {
    return response(400, { error: "Invalid workspace" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const user = authData.user;
  if (authError || !user) return response(401, { error: "Unauthorized" });

  const { data: meetsMfaPolicy, error: mfaPolicyError } = await userClient.rpc(
    "current_user_meets_mfa_policy",
  );
  if (mfaPolicyError) {
    console.error("stripe_mfa_policy_check_failed", {
      code: mfaPolicyError.code,
    });
    return response(503, { error: "Could not verify account security" });
  }
  if (meetsMfaPolicy !== true) {
    return response(403, {
      error: "Complete two-factor verification to continue",
      code: "mfa_required",
    });
  }

  const { data: member } = await serviceClient
    .from("workspace_members")
    .select("workspace_id")
    .eq("workspace_id", workspaceId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!member) return response(403, { error: "Workspace access denied" });

  const mode = liveMode ? "live" : "test";

  async function loadPaymentAccount() {
    const { data } = await serviceClient
      .from("workspace_payment_accounts")
      .select("*")
      .eq("workspace_id", workspaceId)
      .maybeSingle();
    return data as Json | null;
  }

  async function ensurePaymentAccount() {
    const existing = await loadPaymentAccount();
    if (existing) {
      if (existing.mode !== mode) {
        throw new Error(
          `Workspace is configured for Stripe ${existing.mode} mode`,
        );
      }
      return existing;
    }
    const account = await stripeRequest<Json>(
      stripeSecretKey,
      "/v2/core/accounts",
      {
        json: {
          dashboard: "full",
          identity: { country: "gb" },
          configuration: {
            merchant: {
              capabilities: { card_payments: { requested: true } },
            },
          },
          defaults: {
            currency: "gbp",
            responsibilities: {
              fees_collector: "stripe",
              losses_collector: "stripe",
            },
          },
          metadata: { workloop_workspace_id: workspaceId },
          include: [
            "configuration.merchant",
            "defaults",
            "requirements",
          ],
        },
        idempotencyKey: `workloop-connect-v2-${mode}-${workspaceId}`,
      },
    );
    const accountId = stringValue(account.id, 80);
    if (!accountId.startsWith("acct_")) {
      throw new Error("Stripe account was not created");
    }
    const status = accountStatus(account);
    const { data, error } = await serviceClient
      .from("workspace_payment_accounts")
      .upsert({
        workspace_id: workspaceId,
        stripe_account_id: accountId,
        mode,
        country: "GB",
        currency: "gbp",
        onboarding_status: status.onboardingStatus,
        details_submitted: status.detailsSubmitted,
        charges_enabled: status.chargesEnabled,
        payouts_enabled: status.payoutsEnabled,
        requirements_due: status.requirementsDue,
        last_synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "workspace_id" })
      .select()
      .single();
    if (error) throw error;
    return data as Json;
  }

  async function refreshPaymentAccount(accountRow: Json) {
    const accountId = stringValue(accountRow.stripe_account_id, 80);
    const account = await stripeRequest<Json>(
      stripeSecretKey,
      `/v1/accounts/${accountId}`,
    );
    const status = accountStatus(account);
    const { data, error } = await serviceClient
      .from("workspace_payment_accounts")
      .update({
        onboarding_status: status.onboardingStatus,
        details_submitted: status.detailsSubmitted,
        charges_enabled: status.chargesEnabled,
        payouts_enabled: status.payoutsEnabled,
        requirements_due: status.requirementsDue,
        last_synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("workspace_id", workspaceId)
      .select()
      .single();
    if (error) throw error;
    return data as Json;
  }

  async function ensureTerminalLocation(accountRow: Json) {
    const current = stringValue(accountRow.terminal_location_id, 80);
    if (current.startsWith("tml_")) return current;
    const [{ data: workspace }, { data: settings }] = await Promise.all([
      serviceClient.from("workspaces").select("name").eq("id", workspaceId)
        .single(),
      serviceClient.from("workspace_settings").select("business_address")
        .eq("workspace_id", workspaceId).maybeSingle(),
    ]);
    const displayName = stringValue(workspace?.name, 80) || "Workloop business";
    const address = stringValue(settings?.business_address, 200);
    const form: Array<[string, string]> = [
      ["display_name", displayName],
      ["address[country]", "GB"],
      ["metadata[workloop_workspace_id]", workspaceId],
    ];
    if (address) form.push(["address[line1]", address]);
    const location = await stripeRequest<Json>(
      stripeSecretKey,
      "/v1/terminal/locations",
      {
        accountId: stringValue(accountRow.stripe_account_id, 80),
        idempotencyKey: `workloop-location-${mode}-${workspaceId}`,
        form,
      },
    );
    const locationId = stringValue(location.id, 80);
    if (!locationId.startsWith("tml_")) {
      throw new Error("Terminal location was not created");
    }
    const { error } = await serviceClient
      .from("workspace_payment_accounts")
      .update({
        terminal_location_id: locationId,
        updated_at: new Date().toISOString(),
      })
      .eq("workspace_id", workspaceId);
    if (error) throw error;
    return locationId;
  }

  async function requireReadyAccount() {
    const refreshed = await refreshPaymentAccount(await ensurePaymentAccount());
    if (
      refreshed.charges_enabled !== true ||
      refreshed.payouts_enabled !== true ||
      refreshed.onboarding_status !== "ready"
    ) {
      throw new Error("Finish Stripe setup before taking a payment");
    }
    return refreshed;
  }

  async function succeededRefundAmount(transactionId: string) {
    const { data: refunds, error: refundsError } = await serviceClient
      .from("payment_refunds")
      .select("amount_minor")
      .eq("transaction_id", transactionId)
      .eq("status", "succeeded");
    if (refundsError) throw refundsError;
    const refunded = (refunds ?? []).reduce(
      (sum, row) => sum + Number(row.amount_minor),
      0,
    );
    return Math.max(0, refunded);
  }

  async function loadInvoice() {
    const invoiceId = stringValue(payload.invoiceId, 64);
    if (!isUuid(invoiceId)) throw new Error("Invalid payment record");
    const { data, error } = await serviceClient
      .from("invoices")
      .select(
        "id, workspace_id, invoice_number, total, amount_paid, status, contact_id, appointment_id, source_document_id",
      )
      .eq("id", invoiceId)
      .eq("workspace_id", workspaceId)
      .single();
    if (error || !data) throw new Error("Payment record was not found");
    return data as Json;
  }

  async function reserveCollection(
    invoice: Json,
    accountRow: Json,
    method: "tap_to_pay" | "payment_link",
    receiptEmail = "",
  ) {
    // Configuration failures must happen before the durable collection lock.
    safePlatformFeeMinor(0);
    const requestedKey = requireStripeIdempotencyKey(
      payload,
      "Invalid payment request",
    );
    const requested = payload.amountMinor;
    if (
      requested !== undefined &&
      (!Number.isSafeInteger(requested) || Number(requested) <= 0)
    ) {
      throw new StripeApiError(
        "Enter a valid payment amount",
        400,
        "invalid_amount",
      );
    }
    const { data: active, error: activeError } = await serviceClient.from(
      "payment_transactions",
    )
      .select("*").eq("workspace_id", workspaceId).eq("invoice_id", invoice.id)
      .in("status", ["pending", "processing", "requires_payment_method"]);
    if (activeError) throw activeError;
    const read = (path: string) =>
      stripeRequest<Json>(stripeSecretKey, path, {
        accountId: stringValue(accountRow.stripe_account_id),
      });
    for (const transaction of active ?? []) {
      const update = transaction.collection_method === "payment_link"
        ? await currentCheckoutUpdate(
          String(transaction.stripe_checkout_session_id),
          transaction,
          liveMode,
          read,
        )
        : await currentIntentUpdate(
          String(transaction.stripe_payment_intent_id),
          transaction,
          liveMode,
          read,
        );
      const updatedAt = new Date().toISOString();
      const { data: updated, error } = await serviceClient.from(
        "payment_transactions",
      )
        .update({ ...update, updated_at: updatedAt })
        .eq("id", transaction.id).eq("updated_at", transaction.updated_at)
        .select("id").maybeSingle();
      if (error) throw error;
      if (!updated) {
        throw new StripeApiError(
          "Payment status changed. Please try again.",
          409,
          "payment_changed",
        );
      }
      Object.assign(transaction, update, { updated_at: updatedAt });
    }
    const { data, error } = await serviceClient.rpc(
      "reserve_stripe_collection",
      {
        p_workspace_id: workspaceId,
        p_invoice_id: invoice.id,
        p_user_id: user!.id,
        p_idempotency_key: requestedKey,
        p_collection_method: method,
        p_amount_minor: requested ?? null,
        p_receipt_email: receiptEmail,
      },
    );
    if (error) {
      if (error.code === "P0001") {
        throw new StripeApiError(error.message, 409, "collection_in_progress");
      }
      throw error;
    }
    const reservation = objectValue(data);
    const key = stringValue(reservation.idempotencyKey, 128);
    const amountMinor = Number(reservation.amountMinor);
    if (
      key.length < 16 || !Number.isSafeInteger(amountMinor) || amountMinor <= 0
    ) throw new Error("Invalid collection reservation");
    return {
      idempotencyKey: key,
      amountMinor,
      // A concurrent creator may be absent from this snapshot. Replaying Stripe
      // with the reserved key and the existing upsert safely recovers that case.
      existing: (active ?? []).find((row) =>
        row.idempotency_key === key && row.invoice_id === invoice.id &&
        row.collection_method === method &&
        Number(row.amount_minor) === amountMinor &&
        ["pending", "processing", "requires_payment_method"].includes(
          row.status,
        )
      ),
    };
  }

  try {
    switch (action) {
      case "accountStatus": {
        const existing = await loadPaymentAccount();
        if (!existing) return response(200, { connected: false, mode });
        const refreshed = await refreshPaymentAccount(existing);
        return response(200, {
          connected: true,
          mode,
          onboardingStatus: refreshed.onboarding_status,
          detailsSubmitted: refreshed.details_submitted,
          chargesEnabled: refreshed.charges_enabled,
          payoutsEnabled: refreshed.payouts_enabled,
          requirementsDue: refreshed.requirements_due,
          terminalLocationId: refreshed.terminal_location_id,
        });
      }
      case "createOnboardingLink": {
        const accountRow = await ensurePaymentAccount();
        const link = await stripeRequest<Json>(
          stripeSecretKey,
          "/v2/core/account_links",
          {
            json: {
              account: stringValue(accountRow.stripe_account_id, 80),
              use_case: {
                type: "account_onboarding",
                account_onboarding: {
                  configurations: ["merchant"],
                  refresh_url: requireConfiguredUrl(
                    "STRIPE_CONNECT_REFRESH_URL",
                  ),
                  return_url: requireConfiguredUrl(
                    "STRIPE_CONNECT_RETURN_URL",
                  ),
                },
              },
            },
          },
        );
        return response(200, { url: link.url, mode });
      }
      case "createDashboardLink": {
        await requireReadyAccount();
        return response(200, { url: "https://dashboard.stripe.com/" });
      }
      case "createConnectionToken": {
        const accountRow = await requireReadyAccount();
        const locationId = await ensureTerminalLocation(accountRow);
        const token = await stripeRequest<Json>(
          stripeSecretKey,
          "/v1/terminal/connection_tokens",
          {
            accountId: stringValue(accountRow.stripe_account_id, 80),
            form: [["location", locationId]],
          },
        );
        return response(200, { secret: token.secret, locationId });
      }
      case "createTerminalPaymentIntent": {
        const accountRow = await requireReadyAccount();
        const invoice = await loadInvoice();
        const receiptEmail = optionalReceiptEmail(payload.receiptEmail);
        const { amountMinor, idempotencyKey } = await reserveCollection(
          invoice,
          accountRow,
          "tap_to_pay",
          receiptEmail,
        );
        const { data: existing, error: existingError } = await serviceClient
          .from("payment_transactions")
          .select(
            "id, invoice_id, stripe_payment_intent_id, collection_method, status, amount_minor, metadata",
          )
          .eq("workspace_id", workspaceId)
          .eq("idempotency_key", idempotencyKey)
          .maybeSingle();
        if (existingError) throw existingError;
        if (existing) {
          requireMatchingPaymentOperation(
            existing,
            stringValue(invoice.id, 64),
            amountMinor,
            "tap_to_pay",
          );
          const existingReceiptEmail = stringValue(
            objectValue(existing.metadata).receipt_email,
            254,
          );
          if (existingReceiptEmail !== receiptEmail) {
            throw new Error("Payment request key was already used");
          }
          const existingIntentId = stringValue(
            existing.stripe_payment_intent_id,
            100,
          );
          const existingIntent = await stripeRequest<Json>(
            stripeSecretKey,
            `/v1/payment_intents/${existingIntentId}`,
            { accountId: stringValue(accountRow.stripe_account_id, 80) },
          );
          return response(200, {
            transaction: existing,
            clientSecret: existingIntent.client_secret,
            locationId: await ensureTerminalLocation(accountRow),
            reused: true,
          });
        }
        const feeMinor = safePlatformFeeMinor(amountMinor);
        const form: Array<[string, string]> = [
          ["amount", String(amountMinor)],
          ["currency", "gbp"],
          ["payment_method_types[]", "card_present"],
          ["capture_method", "automatic"],
          [
            "description",
            `Workloop ${stringValue(invoice.invoice_number, 60)}`,
          ],
          ["metadata[workloop_workspace_id]", workspaceId],
          ["metadata[workloop_invoice_id]", stringValue(invoice.id, 64)],
          ["metadata[workloop_collection_method]", "tap_to_pay"],
        ];
        if (receiptEmail) {
          form.push(["receipt_email", receiptEmail]);
        }
        if (feeMinor > 0) {
          form.push(["application_fee_amount", String(feeMinor)]);
        }
        const intent = await stripeRequest<Json>(
          stripeSecretKey,
          "/v1/payment_intents",
          {
            accountId: stringValue(accountRow.stripe_account_id, 80),
            idempotencyKey,
            form,
          },
        );
        const { data: insertedTransaction, error } = await serviceClient
          .from("payment_transactions")
          .upsert({
            workspace_id: workspaceId,
            invoice_id: invoice.id,
            stripe_account_id: accountRow.stripe_account_id,
            stripe_payment_intent_id: intent.id,
            collection_method: "tap_to_pay",
            status: "pending",
            currency: "gbp",
            amount_minor: amountMinor,
            platform_fee_minor: feeMinor,
            created_by_user_id: user.id,
            idempotency_key: idempotencyKey,
            metadata: receiptEmail ? { receipt_email: receiptEmail } : {},
          }, {
            onConflict: "workspace_id,idempotency_key",
            ignoreDuplicates: true,
          })
          .select()
          .maybeSingle();
        if (error) throw error;
        const transaction = insertedTransaction ??
          (await serviceClient.from("payment_transactions")
            .select("*").eq("workspace_id", workspaceId).eq(
              "idempotency_key",
              idempotencyKey,
            ).single()).data;
        if (!transaction) {
          throw new Error("Could not recover the payment operation");
        }
        return response(200, {
          transaction,
          clientSecret: intent.client_secret,
          locationId: await ensureTerminalLocation(accountRow),
        });
      }
      case "createPaymentLink": {
        const accountRow = await requireReadyAccount();
        const invoice = await loadInvoice();
        const successUrl = requireConfiguredUrl("STRIPE_CHECKOUT_SUCCESS_URL");
        const cancelUrl = requireConfiguredUrl("STRIPE_CHECKOUT_CANCEL_URL");
        const receiptEmail = await paymentLinkReceiptEmail(
          serviceClient,
          invoice,
          workspaceId,
        );
        const { amountMinor, idempotencyKey, existing } =
          await reserveCollection(
            invoice,
            accountRow,
            "payment_link",
          );
        if (existing) {
          return response(200, {
            transaction: existing,
            url: (existing.metadata as Json | null)?.checkout_url,
            reused: true,
          });
        }
        const feeMinor = safePlatformFeeMinor(amountMinor);
        const form: Array<[string, string]> = [
          ["mode", "payment"],
          ["payment_method_types[]", "card"],
          ["success_url", successUrl],
          ["cancel_url", cancelUrl],
          ["client_reference_id", stringValue(invoice.id, 64)],
          ["line_items[0][quantity]", "1"],
          ["line_items[0][price_data][currency]", "gbp"],
          ["line_items[0][price_data][unit_amount]", String(amountMinor)],
          [
            "line_items[0][price_data][product_data][name]",
            `Payment ${stringValue(invoice.invoice_number, 60)}`,
          ],
          ["payment_intent_data[metadata][workloop_workspace_id]", workspaceId],
          [
            "payment_intent_data[metadata][workloop_invoice_id]",
            stringValue(invoice.id, 64),
          ],
          [
            "payment_intent_data[metadata][workloop_collection_method]",
            "payment_link",
          ],
          ["metadata[workloop_workspace_id]", workspaceId],
          ["metadata[workloop_invoice_id]", stringValue(invoice.id, 64)],
        ];
        if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(receiptEmail)) {
          form.push(["customer_email", receiptEmail], [
            "payment_intent_data[receipt_email]",
            receiptEmail,
          ]);
        }
        if (feeMinor > 0) {
          form.push([
            "payment_intent_data[application_fee_amount]",
            String(feeMinor),
          ]);
        }
        const session = await stripeRequest<Json>(
          stripeSecretKey,
          "/v1/checkout/sessions",
          {
            accountId: stringValue(accountRow.stripe_account_id, 80),
            idempotencyKey,
            form,
          },
        );
        const { data: insertedTransaction, error } = await serviceClient
          .from("payment_transactions")
          .upsert({
            workspace_id: workspaceId,
            invoice_id: invoice.id,
            stripe_account_id: accountRow.stripe_account_id,
            stripe_checkout_session_id: session.id,
            collection_method: "payment_link",
            status: "pending",
            currency: "gbp",
            amount_minor: amountMinor,
            platform_fee_minor: feeMinor,
            created_by_user_id: user.id,
            idempotency_key: idempotencyKey,
            metadata: { checkout_url: session.url },
          }, {
            onConflict: "workspace_id,idempotency_key",
            ignoreDuplicates: true,
          })
          .select()
          .maybeSingle();
        if (error) throw error;
        const transaction = insertedTransaction ??
          (await serviceClient.from("payment_transactions")
            .select("*").eq("workspace_id", workspaceId).eq(
              "idempotency_key",
              idempotencyKey,
            ).single()).data;
        if (!transaction) {
          throw new Error("Could not recover the payment operation");
        }
        return response(200, { transaction, url: session.url });
      }
      case "refund": {
        const accountRow = await loadPaymentAccount();
        if (!accountRow || accountRow.mode !== mode) {
          throw new Error("Payment account is unavailable");
        }
        const transactionId = stringValue(payload.transactionId, 64);
        if (!isUuid(transactionId)) throw new Error("Invalid transaction");
        const { data: transaction, error: transactionError } =
          await serviceClient
            .from("payment_transactions")
            .select("*")
            .eq("id", transactionId)
            .eq("workspace_id", workspaceId)
            .single();
        if (
          transactionError || !transaction ||
          transaction.stripe_account_id !== accountRow.stripe_account_id
        ) {
          throw new Error("Transaction was not found");
        }
        const amount = Number(transaction.amount_minor);
        const requested = Number(payload.amountMinor);
        if (
          !Number.isSafeInteger(requested) || requested <= 0 ||
          requested > amount
        ) {
          throw new Error("Refund amount is outside the refundable balance");
        }
        const intentId = stringValue(transaction.stripe_payment_intent_id, 100);
        if (!intentId.startsWith("pi_")) {
          throw new Error("Payment is not ready to refund");
        }
        const idempotencyKey = requireStripeIdempotencyKey(
          payload,
          "Invalid refund request",
        );
        const { data: existingRefund, error: existingRefundError } =
          await serviceClient
            .from("payment_refunds")
            .select("stripe_refund_id, transaction_id, amount_minor, status")
            .eq("workspace_id", workspaceId)
            .eq("idempotency_key", idempotencyKey)
            .maybeSingle();
        if (existingRefundError) throw existingRefundError;
        if (existingRefund) {
          if (
            existingRefund.transaction_id !== transactionId ||
            Number(existingRefund.amount_minor) !== requested
          ) {
            throw new Error("Refund request key was already used");
          }
          if (["failed", "cancelled"].includes(existingRefund.status)) {
            throw new StripeApiError(
              "Stripe could not complete this refund. Check it in Stripe before trying again.",
              409,
              "refund_failed",
            );
          }
          return response(200, {
            refundId: existingRefund.stripe_refund_id,
            status: existingRefund.status,
            reused: true,
          });
        }
        const alreadyRefunded = await succeededRefundAmount(transactionId);
        requireRefundWithinBalance(requested, amount, alreadyRefunded);
        const refund = await stripeRequest<Json>(
          stripeSecretKey,
          "/v1/refunds",
          {
            accountId: stringValue(accountRow.stripe_account_id, 80),
            idempotencyKey,
            form: [
              ["payment_intent", intentId],
              ["amount", String(requested)],
              ["metadata[workloop_workspace_id]", workspaceId],
              ["metadata[workloop_transaction_id]", transactionId],
              ["metadata[workloop_idempotency_key]", idempotencyKey],
            ],
          },
        );
        const refundStatus = currentRefundStatus(refund.status);
        const { error: refundError } = await serviceClient.from(
          "payment_refunds",
        ).upsert({
          workspace_id: workspaceId,
          transaction_id: transactionId,
          stripe_refund_id: refund.id,
          amount_minor: requested,
          status: refundStatus,
          created_by_user_id: user.id,
          idempotency_key: idempotencyKey,
          updated_at: new Date().toISOString(),
        }, { onConflict: "stripe_refund_id", ignoreDuplicates: true });
        if (refundError) throw refundError;
        if (refundStatus === "failed" || refundStatus === "cancelled") {
          throw new StripeApiError(
            "Stripe could not complete this refund. Check it in Stripe before trying again.",
            409,
            "refund_failed",
          );
        }
        if (refundStatus === "succeeded") {
          const update = await currentIntentUpdate(
            intentId,
            transaction,
            liveMode,
            (path) =>
              stripeRequest<Json>(stripeSecretKey, path, {
                accountId: stringValue(accountRow.stripe_account_id),
              }),
          );
          const { data: updated, error: updateError } = await serviceClient
            .from("payment_transactions")
            .update({ ...update, updated_at: new Date().toISOString() }).eq(
              "id",
              transactionId,
            )
            .eq("updated_at", transaction.updated_at).select("id")
            .maybeSingle();
          if (updateError) throw updateError;
          if (!updated) {
            throw new StripeApiError(
              "Refund sent. Refresh the payment to check its status.",
              409,
              "payment_changed",
            );
          }
        }
        return response(200, { refundId: refund.id, status: refundStatus });
      }
      default:
        return response(400, { error: "Unsupported payment action" });
    }
  } catch (error) {
    console.error("stripe_payment_action_failed", {
      action,
      workspaceId,
      message: error instanceof Error ? error.message : "unknown",
    });
    const safe = publicStripeError(error);
    return response(safe.status, { error: safe.message, code: safe.code });
  }
});
