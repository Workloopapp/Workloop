import { withWorkloopOperator } from "./workloop_operator_email.ts";
import {
  businessContactEmail,
  loadBusinessEmailContact,
} from "./business_contact_email.ts";
export type BookingConfirmationEmailConfig = {
  apiKey: string;
  from: string;
};

type ClaimedEmail = {
  outbox_id: string;
  booking_request_id: string;
  lease_token: string;
  recipient_email: string;
  payload: Record<string, unknown>;
  attempt_count: number;
};

type RpcError = { code?: string; message?: string };

export type BookingConfirmationRpcClient = {
  rpc: (
    name: string,
    params?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: RpcError | null }>;
};

export function bookingConfirmationEmailConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): BookingConfirmationEmailConfig | null {
  const apiKey = readEnv("RESEND_API_KEY")?.trim() ?? "";
  const from = readEnv("BOOKING_CONFIRMATION_EMAIL_FROM")?.trim() ?? "";
  if (apiKey.length < 16 || from.length < 3) return null;
  return { apiKey, from };
}

export function validBookingConfirmationDrainToken(
  configured: string,
  supplied: string,
) {
  const encoder = new TextEncoder();
  const a = encoder.encode(configured);
  const b = encoder.encode(supplied);
  if (a.length < 32 || a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

function text(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : fallback;
}

export function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function bookingTime(payload: Record<string, unknown>) {
  const raw = text(payload.start_time);
  if (raw.length === 0) return "the time agreed with the business";
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return "the time agreed with the business";
  }
  const requestedTimezone = text(payload.timezone, "UTC");
  try {
    return new Intl.DateTimeFormat("en-GB", {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: requestedTimezone,
      timeZoneName: "short",
    }).format(parsed);
  } catch (_) {
    return new Intl.DateTimeFormat("en-GB", {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
      timeZoneName: "short",
    }).format(parsed);
  }
}

function bookingDuration(payload: Record<string, unknown>) {
  const rawStart = text(payload.start_time);
  const rawEnd = text(payload.end_time);
  if (rawStart.length === 0 || rawEnd.length === 0) return "";

  const start = new Date(rawStart);
  const end = new Date(rawEnd);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return "";
  }

  const minutes = Math.round((end.getTime() - start.getTime()) / 60_000);
  if (!Number.isFinite(minutes) || minutes <= 0) return "";
  if (minutes % 60 === 0) {
    const hours = minutes / 60;
    return hours === 1 ? "1 hour" : `${hours} hours`;
  }
  return `${minutes} minutes`;
}

export function bookingConfirmationEmailContent(
  claim: Pick<ClaimedEmail, "payload">,
) {
  const contact = businessContactEmail(claim.payload);
  const customerName = text(claim.payload.customer_name, "there");
  const businessName = text(claim.payload.business_name, "The business");
  const bookingTitle = text(claim.payload.booking_title, "Booking");
  const location = text(claim.payload.location);
  const time = bookingTime(claim.payload);
  const subject = `${businessName} confirmed your booking: ${bookingTitle}`;
  const duration = bookingDuration(claim.payload);
  const locationLine = location.length > 0 ? `\nLocation: ${location}` : "";
  const durationLine = duration.length > 0 ? `\nDuration: ${duration}` : "";
  const plainText =
    `Hi ${customerName},\n\n${businessName} has confirmed your booking request.\n\nBooking: ${bookingTitle}\nWhen: ${time}${durationLine}${locationLine}\n\nYou can review the details with ${businessName} directly if anything needs changing.\n\n${contact.text}\n\nSent by Workloop`;
  const locationHtml = location.length > 0
    ? `<br><strong>Location:</strong> ${escapeHtml(location)}`
    : "";
  const durationHtml = duration.length > 0
    ? `<br><strong>Duration:</strong> ${escapeHtml(duration)}`
    : "";
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><style>@font-face{font-family:Manrope;src:url('https://workloop.uk/Manrope-Variable.ttf') format('truetype');font-weight:100 900}</style></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:'Manrope',Arial,sans-serif"><div style="display:none;max-height:0;overflow:hidden">Your booking with ${
      escapeHtml(businessName)
    } is confirmed.</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5edd9"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:34px"><div style="font-size:26px;font-weight:650;letter-spacing:-.04em">workloop</div><p style="margin:30px 0 12px;color:#286280;font-size:12px;font-weight:600;letter-spacing:.08em;padding:10px 12px;background:#c3d7e4;border:1px solid #8d8070;border-radius:5px;color:#443c32">BOOKING CONFIRMED</p><h1 style="margin:0 0 18px;font-size:34px;line-height:1.1">You’re booked in.</h1><p style="color:#665c50;font-size:17px;line-height:1.6">Hi ${
      escapeHtml(customerName)
    }, ${
      escapeHtml(businessName)
    } has confirmed your booking request.</p><div style="margin:24px 0;padding:22px;background:#f0d18b;border-radius:6px;border:1px solid #8d8070;line-height:1.65"><strong>Booking:</strong> ${
      escapeHtml(bookingTitle)
    }<br><strong>When:</strong> ${
      escapeHtml(time)
    }${durationHtml}${locationHtml}</div><p style="color:#665c50;line-height:1.6">If anything needs changing, contact ${
      escapeHtml(businessName)
    } directly.</p>${contact.html}<p style="margin:28px 0 0;color:#665c50;font-size:14px">Sent by Workloop, the business operating system for one.</p></td></tr></table></td></tr></table></body></html>`;
  return withWorkloopOperator({ subject, plainText, html });
}

export async function sendBookingConfirmationEmail(
  claim: ClaimedEmail,
  config: BookingConfirmationEmailConfig,
  fetcher: typeof fetch = fetch,
) {
  const content = bookingConfirmationEmailContent(claim);
  const response = await fetcher("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `booking-request-confirmed/${claim.outbox_id}`,
    },
    body: JSON.stringify({
      from: config.from,
      to: [claim.recipient_email],
      reply_to: String(
        (claim.payload.business_contact as Record<string, unknown> | undefined)
          ?.email ?? "support@workloop.uk",
      ),
      subject: content.subject,
      text: content.plainText,
      html: content.html,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`email_provider_http_${response.status}`);
  }
  const body = await response.json().catch(() => ({}));
  const providerMessageId = typeof body?.id === "string" ? body.id : "";
  if (providerMessageId.length === 0) {
    throw new Error("email_provider_invalid_response");
  }
  return providerMessageId;
}

export async function drainBookingConfirmationEmails(input: {
  client: BookingConfirmationRpcClient;
  config: BookingConfirmationEmailConfig;
  limit?: number;
  bookingRequestId?: string;
  fetcher?: typeof fetch;
}) {
  const { data, error } = await input.client.rpc(
    "claim_booking_confirmation_emails",
    {
      p_limit: input.limit ?? 20,
      p_booking_request_id: input.bookingRequestId ?? null,
    },
  );
  if (error) throw new Error(`email_outbox_claim_failed:${error.code ?? ""}`);
  const claims = Array.isArray(data) ? data as ClaimedEmail[] : [];
  let sent = 0;
  let pending = 0;
  let failed = 0;

  for (const claim of claims) {
    let providerMessageId = "";
    let delivered = false;
    let failure = "";
    try {
      const contact = await loadBusinessEmailContact(
        input.client,
        "confirmation",
        claim.outbox_id,
      );
      claim.payload = { ...claim.payload, business_contact: contact };
      providerMessageId = await sendBookingConfirmationEmail(
        claim,
        input.config,
        input.fetcher,
      );
      delivered = true;
    } catch (error) {
      failure = error instanceof Error
        ? error.message.slice(0, 500)
        : "email_provider_unavailable";
    }

    const completion = await input.client.rpc(
      "finish_booking_confirmation_email",
      {
        p_outbox_id: claim.outbox_id,
        p_lease_token: claim.lease_token,
        p_sent: delivered,
        p_provider_message_id: providerMessageId || null,
        p_error: failure || null,
      },
    );
    if (completion.error) {
      throw new Error(
        `email_outbox_finish_failed:${completion.error.code ?? ""}`,
      );
    }
    if (completion.data === "sent") sent++;
    else if (completion.data === "failed") failed++;
    else pending++;
  }

  return { processed: claims.length, sent, pending, failed };
}
