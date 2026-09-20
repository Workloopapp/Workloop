import { withWorkloopOperator } from "./workloop_operator_email.ts";
import {
  businessContactEmail,
  loadBusinessEmailContact,
} from "./business_contact_email.ts";
import {
  type BookingConfirmationEmailConfig,
  bookingConfirmationEmailContent,
  type BookingConfirmationRpcClient,
} from "./booking_confirmation_email.ts";
import { emailFrame, escapeEmail } from "./learning_email_content.ts";
export function bookingReminderEmail(
  payload: Record<string, unknown>,
  unsubscribeUrl: string,
) {
  const contact = businessContactEmail(payload);
  const business = String(payload.business_name ?? "The business");
  const minutes = Number(payload.minutes_before);
  if (![1440, 120, 60].includes(minutes)) {
    throw new Error("invalid_reminder_interval");
  }
  const timeLabel = minutes === 1440
    ? "in 24 hours"
    : minutes === 120
    ? "in 2 hours"
    : "in 1 hour";
  // Reuse timezone and duration formatting from the existing booking template.
  const details =
    bookingConfirmationEmailContent({ payload }).plainText.split("\n\n").find(
      (p) => p.startsWith("Booking:"),
    ) ?? "";
  const subject = `Reminder: your booking with ${business} starts ${timeLabel}`;
  const heading = `Your booking starts ${timeLabel}.`;
  const intro = `Hi ${
    String(payload.customer_name ?? "there")
  }, here is a reminder of your upcoming booking with ${business}.`;
  return withWorkloopOperator({
    subject,
    text:
      `${intro}\n\n${details}\n\nIf your plans have changed, contact ${business} directly.\n\n${contact.text}\n\nStop reminder emails from this business: ${unsubscribeUrl}\nThis does not cancel your booking.\nSent by Workloop on behalf of ${business}.`,
    html: emailFrame({
      heading,
      preview: subject,
      body: `<p style="font-size:17px;line-height:1.65">${
        escapeEmail(intro)
      }</p><div style="background:#f0d18b;border:1px solid #8d8070;border-radius:6px;padding:22px;font-size:17px;line-height:1.65">${
        escapeEmail(details).replaceAll("\n", "<br>")
      }</div><p style="font-size:17px;line-height:1.65">If your plans have changed, contact ${
        escapeEmail(business)
      } directly.</p>${contact.html}`,
      footer: `Sent by Workloop on behalf of ${
        escapeEmail(business)
      }.<br><a href="${
        escapeEmail(unsubscribeUrl)
      }" style="color:#286280">Stop reminder emails from this business</a>. This does not cancel your booking.`,
    }).replace("A NOTE FOR THE BUSINESS OF ONE", "YOUR BOOKING REMINDER"),
  });
}
type Claim = {
  outbox_id: string;
  lease_token: string;
  recipient_email: string;
  unsubscribe_token: string;
  reply_email: string | null;
  payload: Record<string, unknown>;
};
export async function drainBookingReminderEmails(
  input: {
    client: BookingConfirmationRpcClient;
    config: BookingConfirmationEmailConfig;
    supabaseUrl: string;
    limit?: number;
    fetcher?: typeof fetch;
  },
) {
  const call = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await input.client.rpc(name, args);
    if (error) throw new Error(`${name}:${error.code}`);
    return data;
  };
  const claims = await call("claim_booking_reminder_emails", {
    p_limit: input.limit ?? 5,
  }) as Claim[];
  let sent = 0, failed = 0, skipped = 0;
  for (const claim of claims ?? []) {
    if (
      !await call("booking_reminder_still_allowed", {
        p_outbox_id: claim.outbox_id,
        p_lease_token: claim.lease_token,
      })
    ) {
      skipped++;
      continue;
    }
    const url =
      `${input.supabaseUrl}/functions/v1/learning-series?action=stop-reminders&token=${claim.unsubscribe_token}`;
    let providerId: string | null = null, error: string | null = null;
    try {
      const contact = await loadBusinessEmailContact(
        input.client,
        "reminder",
        claim.outbox_id,
      );
      const content = bookingReminderEmail({
        ...claim.payload,
        business_contact: contact,
      }, url);
      const reply = typeof contact.email === "string" &&
          /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact.email)
        ? contact.email
        : "support@workloop.uk";
      const response = await (input.fetcher ?? fetch)(
        "https://api.resend.com/emails",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${input.config.apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `booking-reminder/${claim.outbox_id}`,
          },
          body: JSON.stringify({
            from: input.config.from,
            to: [claim.recipient_email],
            reply_to: reply,
            ...content,
            headers: {
              "List-Unsubscribe": `<${url}>`,
              "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
            },
          }),
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!response.ok) throw new Error(`provider_http_${response.status}`);
      const body = await response.json();
      if (typeof body.id !== "string") throw new Error("provider_missing_id");
      providerId = body.id;
      sent++;
    } catch (e) {
      error = e instanceof Error
        ? e.message.slice(0, 160)
        : "provider_unavailable";
      failed++;
    }
    await call("finish_booking_reminder_email", {
      p_outbox_id: claim.outbox_id,
      p_lease_token: claim.lease_token,
      p_provider_message_id: providerId,
      p_error: error,
    });
  }
  return { sent, failed, skipped };
}
