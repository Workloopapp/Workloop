import {
  type BookingConfirmationEmailConfig,
  type BookingConfirmationRpcClient,
  escapeHtml,
} from "./booking_confirmation_email.ts";
import { withWorkloopOperator } from "./workloop_operator_email.ts";

export function subscriptionTrialEmailContent(trialEndsAt: string) {
  const end = new Date(trialEndsAt);
  if (!Number.isFinite(end.getTime())) throw new Error("invalid_trial_end");
  const date = new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
    timeZoneName: "short",
  }).format(end);
  const manage = "https://apps.apple.com/account/subscriptions";
  const summary = `Your Workloop free trial ends on ${date}.`;
  const renewal =
    "Apple will then renew your monthly subscription at the price shown in your App Store subscription. You can see the exact price and renewal date there.";
  const cancel =
    "To avoid the first charge, cancel through Apple at least 24 hours before your trial ends. Deleting Workloop or your Workloop account does not cancel an Apple subscription.";
  const recent =
    "If you have recently changed your subscription, Apple shows its latest status.";
  const plainText =
    `Hi,\n\n${summary}\n\n${renewal}\n\n${cancel}\n\nManage or cancel your subscription: ${manage}\n\n${recent}\n\nThis is a service reminder about your subscription. Need a hand? Contact support@workloop.uk.`;
  return withWorkloopOperator({
    subject: "Your Workloop free trial ends soon",
    plainText,
    html:
      `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:Arial,sans-serif"><table role="presentation" width="100%"><tr><td align="center" style="padding:32px 16px"><table role="presentation" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:32px"><p style="font-size:26px;font-weight:700">workloop</p><p style="padding:12px;background:#c3d7e4;border-radius:5px">YOUR SUBSCRIPTION</p><h1 style="font-size:30px;line-height:1.15">Your free trial ends soon.</h1><p style="line-height:1.6">${
        escapeHtml(summary)
      }</p><p style="line-height:1.6">${
        escapeHtml(renewal)
      }</p><p style="line-height:1.6">${
        escapeHtml(cancel)
      }</p><p style="margin:28px 0"><a href="${manage}" style="display:inline-block;padding:15px 20px;background:#91b4c8;color:#443c32;border:1px solid #443c32;border-radius:6px;text-decoration:none;font-weight:700">Manage or cancel subscription</a></p><p style="line-height:1.6;color:#665c50">${
        escapeHtml(recent)
      }</p><p style="font-size:14px;line-height:1.6;color:#665c50">This is a service reminder about your subscription. Need a hand? <a href="mailto:support@workloop.uk">Contact Workloop support</a>.</p></td></tr></table></td></tr></table></body></html>`,
  });
}

export async function drainSubscriptionTrialEmails(input: {
  client: BookingConfirmationRpcClient;
  config: BookingConfirmationEmailConfig;
  limit?: number;
  fetcher?: typeof fetch;
}) {
  const claims = await input.client.rpc("claim_subscription_trial_emails", {
    p_limit: input.limit ?? 5,
  });
  if (claims.error) throw new Error("subscription_trial_email_claim_failed");
  const rows = Array.isArray(claims.data)
    ? claims.data as {
      outbox_id: string;
      lease_token: string;
    }[]
    : [];
  let sent = 0, skipped = 0, pending = 0, failed = 0;
  for (const claim of rows) {
    let delivered = false, suppressed = false, providerId = "", failure = "";
    try {
      // No recipient or date is trusted from a cached claim. Recheck current
      // ownership, trial, cancellation, refund and account state before sending.
      const prepared = await input.client.rpc(
        "prepare_subscription_trial_email",
        {
          p_outbox_id: claim.outbox_id,
          p_lease_token: claim.lease_token,
        },
      );
      if (prepared.error) {
        throw new Error("subscription_trial_email_prepare_failed");
      }
      const item = Array.isArray(prepared.data) ? prepared.data[0] : null;
      if (!item) suppressed = true;
      else {
        if (
          typeof item.recipient_email !== "string" ||
          typeof item.trial_ends_at !== "string"
        ) {
          throw new Error("subscription_trial_email_invalid_claim");
        }
        const content = subscriptionTrialEmailContent(item.trial_ends_at);
        const response = await (input.fetcher ?? fetch)(
          "https://api.resend.com/emails",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${input.config.apiKey}`,
              "Content-Type": "application/json",
              "Idempotency-Key": `subscription-trial/${claim.outbox_id}`,
            },
            body: JSON.stringify({
              from: input.config.from,
              reply_to: "support@workloop.uk",
              to: [item.recipient_email],
              subject: content.subject,
              text: content.plainText,
              html: content.html,
            }),
            signal: AbortSignal.timeout(10_000),
          },
        );
        if (!response.ok) {
          throw new Error(`email_provider_http_${response.status}`);
        }
        const body = await response.json();
        if (typeof body?.id !== "string" || !body.id) {
          throw new Error("email_provider_invalid_response");
        }
        providerId = body.id;
        delivered = true;
      }
    } catch {
      // Store a stable code, never provider bodies, recipient addresses or keys.
      failure = "subscription_trial_email_delivery_failed";
    }
    const finish = await input.client.rpc("finish_subscription_trial_email", {
      p_outbox_id: claim.outbox_id,
      p_lease_token: claim.lease_token,
      p_sent: delivered,
      p_skipped: suppressed,
      p_provider_message_id: providerId || null,
      p_error: failure || null,
    });
    if (finish.error) throw new Error("subscription_trial_email_finish_failed");
    if (finish.data === "sent") sent++;
    else if (finish.data === "skipped") skipped++;
    else if (finish.data === "failed") failed++;
    else pending++;
  }
  return { processed: rows.length, sent, skipped, pending, failed };
}
