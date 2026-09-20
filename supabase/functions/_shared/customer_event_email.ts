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
export type CustomerEvent =
  | "request_received"
  | "request_declined"
  | "booking_changed"
  | "booking_cancelled"
  | "payment_request";
export function customerEventEmail(
  event: CustomerEvent,
  p: Record<string, unknown>,
) {
  const business = String(p.business_name ?? "The business"),
    customer = String(p.customer_name ?? "there");
  let details =
    bookingConfirmationEmailContent({ payload: p }).plainText.split("\n\n")
      .find((s) => s.startsWith("Booking:")) ?? "";
  if (event.startsWith("request_")) {
    details = details.replace("When:", "Requested time:").replace(
      "the time agreed with the business",
      String(p.requested_time || "To be agreed with the business"),
    );
  }
  let subject: string,
    heading: string,
    message: string,
    extra = "",
    button = "";
  switch (event) {
    case "request_received":
      subject = `${business} received your booking request`;
      heading = "Your request is awaiting confirmation.";
      message =
        `Hi ${customer}, ${business} has received your request. Your booking is not confirmed yet. Please wait for a separate confirmation before treating this time as reserved.`;
      extra = details.replace("Booking:", "Requested service:");
      break;
    case "request_declined":
      subject = `An update on your booking request with ${business}`;
      heading = "This booking request could not be accepted.";
      message =
        `Hi ${customer}, ${business} could not accept this request. No booking has been confirmed. Contact the business directly to discuss another time or service; please wait for confirmation of any new arrangement.`;
      extra = details.replace("Booking:", "Requested service:");
      break;
    case "booking_changed":
      subject = `Your booking with ${business} has changed`;
      heading = "Here are your updated booking details.";
      message =
        `Hi ${customer}, ${business} has updated your booking. Please check the details below and contact the business directly if anything does not match what you agreed.`;
      extra = details +
        (typeof p.price === "number"
          ? `\nAgreed price: £${p.price.toFixed(2)}`
          : "");
      break;
    case "booking_cancelled":
      subject = `Your booking with ${business} has been cancelled`;
      heading = "This booking has been cancelled.";
      message =
        `Hi ${customer}, ${business} has marked this booking as cancelled. You no longer need to attend at the time below. Contact the business directly if you have any questions.`;
      extra = details +
        "\n\nCancellation does not itself confirm a refund. If you have already paid, contact the business about its cancellation terms and refund status. Any completed card refund is confirmed separately.";
      break;
    case "payment_request": {
      const amount = Number(p.amount_minor);
      if (!Number.isInteger(amount) || amount <= 0) {
        throw Error("invalid_payment_amount");
      }
      const url = new URL(String(p.checkout_url));
      if (
        url.protocol !== "https:" || url.hostname !== "checkout.stripe.com" ||
        url.username || url.password
      ) throw Error("invalid_checkout_url");
      subject = `Payment request from ${business}: £${
        (amount / 100).toFixed(2)
      }`;
      heading = `A payment of £${(amount / 100).toFixed(2)} is requested.`;
      message =
        `Hi ${customer}, ${business} has sent you a secure payment request. Check the reference and amount before paying. If you have already paid another way or something looks wrong, contact the business directly first.`;
      extra = `Reference: ${String(p.invoice_number ?? "Your payment")}${
        p.booking_title ? "\nBooking: " + String(p.booking_title) : ""
      }\nAmount requested: £${
        (amount / 100).toFixed(2)
      }\n\nPay securely: ${url}\nThe link may expire. Contact the business if you need a fresh link.`;
      button =
        `<p><a style="display:inline-block;padding:16px 22px;background:#91b4c8;color:#443c32;border:1px solid #443c32;border-radius:6px;text-decoration:none;font-weight:bold" href="${
          escapeEmail(url.toString())
        }">Pay securely with Stripe</a></p>`;
      break;
    }
    default:
      throw Error("unsupported_customer_event");
  }
  const contact = businessContactEmail(p);
  const footer =
    `Sent by Workloop on behalf of ${business}. This is a service message about your request, booking or payment.`;
  return withWorkloopOperator({
    subject,
    text:
      `${heading}\n\n${message}\n\n${extra}\n\n${contact.text}\n\n${footer}`,
    html: emailFrame({
      heading,
      preview: subject,
      body: `<p style="font-size:17px;line-height:1.65">${
        escapeEmail(message)
      }</p><div style="background:#f5edd9;padding:20px;border:1px solid #8d8070;border-radius:6px;font-size:16px;line-height:1.65;overflow-wrap:anywhere">${
        escapeEmail(extra).replaceAll("\n", "<br>")
      }</div>${button}${contact.html}`,
      footer: escapeEmail(footer),
    }).replace("A NOTE FOR THE BUSINESS OF ONE", "YOUR BOOKING & PAYMENT"),
  });
}
export async function drainCustomerEventEmails(
  input: {
    client: BookingConfirmationRpcClient;
    config: BookingConfirmationEmailConfig;
    fetcher?: typeof fetch;
  },
) {
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const r = await input.client.rpc(name, args);
    if (r.error) throw Error(`${name}:${r.error.code}`);
    return r.data;
  };
  const rows = await rpc("claim_customer_event_emails", {
    p_limit: 5,
  }) as Array<
    {
      id: string;
      lease_token: string;
      event: CustomerEvent;
      email: string;
      payload: Record<string, unknown>;
    }
  >;
  let sent = 0, failed = 0, skipped = 0;
  for (const row of rows ?? []) {
    if (
      !await rpc("customer_event_still_allowed", {
        p_id: row.id,
        p_lease_token: row.lease_token,
      })
    ) {
      skipped++;
      continue;
    }
    let providerId: string | null = null, error: string | null = null;
    try {
      const contact = await loadBusinessEmailContact(
        input.client,
        "event",
        row.id,
      );
      const content = customerEventEmail(row.event, {
        ...row.payload,
        business_contact: contact,
      });
      const reply = String(contact.email ?? "support@workloop.uk");
      const response = await (input.fetcher ?? fetch)(
        "https://api.resend.com/emails",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${input.config.apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `customer-event/${row.id}`,
          },
          body: JSON.stringify({
            from: input.config.from,
            to: [row.email],
            reply_to: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(reply)
              ? reply
              : "support@workloop.uk",
            ...content,
          }),
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!response.ok) throw Error(`provider_http_${response.status}`);
      const body = await response.json();
      if (typeof body.id !== "string") throw Error("provider_missing_id");
      providerId = body.id;
      sent++;
    } catch (e) {
      error = e instanceof Error
        ? e.message.slice(0, 160)
        : "provider_unavailable";
      failed++;
    }
    await rpc("finish_customer_event_email", {
      p_id: row.id,
      p_lease_token: row.lease_token,
      p_provider_id: providerId,
      p_error: error,
    });
  }
  return { sent, failed, skipped };
}
