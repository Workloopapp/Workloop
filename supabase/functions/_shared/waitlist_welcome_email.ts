import { withWorkloopOperator } from "./workloop_operator_email.ts";
import type {
  BookingConfirmationEmailConfig,
  BookingConfirmationRpcClient,
} from "./booking_confirmation_email.ts";

type Claim = {
  outbox_id: string;
  lease_token: string;
  recipient_email: string;
  attempt_count: number;
};

export function waitlistWelcomeEmailConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): BookingConfirmationEmailConfig | null {
  const apiKey = readEnv("RESEND_API_KEY")?.trim() ?? "";
  const from = (readEnv("WAITLIST_CONFIRMATION_EMAIL_FROM") ??
    readEnv("BOOKING_CONFIRMATION_EMAIL_FROM") ?? "").trim();
  if (apiKey.length < 16 || from.length < 3) return null;
  return { apiKey, from };
}

export function waitlistWelcomeEmailContent() {
  const subject = "Welcome to the Workloop launch list";
  const plainText = `Hi,

Thanks for joining the Workloop launch list. You are all set.

Workloop brings clients, bookings, tasks, notes and money into one calm mobile workspace, helping solo business owners spend less time on admin and more time doing the work.

What happens next

• We will email you when a beta place or public access is ready.
• Private beta access is free and does not require payment details.
• Public access is planned with 30 days free, then £14.99 monthly or £149.99 annually.

What you will be able to do

• See your day and what needs attention.
• Keep client details, booking history, notes and tasks connected.
• Track money made, spent and owed without a complicated finance system.

Read your practical welcome pack: https://workloop.uk/help/welcome

Questions? Contact support@workloop.uk.

You can leave the launch list at any time by emailing support@workloop.uk.

Workloop
The business operating system for one.`;
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><style>@font-face{font-family:Manrope;src:url('https://workloop.uk/Manrope-Variable.ttf') format('truetype');font-weight:100 900}</style></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:'Manrope',Arial,sans-serif"><div style="display:none;max-height:0;overflow:hidden">You are on the Workloop launch list.</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5edd9"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px;overflow:hidden"><tr><td style="padding:34px 34px 20px"><div style="font-size:26px;font-weight:650;letter-spacing:-.04em;color:#443c32">workloop</div></td></tr><tr><td style="padding:0 34px 34px"><p style="margin:0 0 12px;color:#286280;font-size:12px;font-weight:600;letter-spacing:.08em;padding:10px 12px;background:#c3d7e4;border:1px solid #8d8070;border-radius:5px;color:#443c32">YOU ARE ON THE LIST</p><h1 style="margin:0 0 18px;font-size:34px;line-height:1.08;letter-spacing:-.03em">Thanks. You are all set.</h1><p style="margin:0 0 24px;color:#665c50;font-size:17px;line-height:1.6">Workloop brings clients, bookings, tasks, notes and money into one calm mobile workspace, so you can spend less time on admin and more time doing the work.</p><div style="padding:22px;background:#f0d18b;border-radius:6px;border:1px solid #8d8070"><h2 style="margin:0 0 12px;font-size:19px">What happens next</h2><p style="margin:0 0 10px;line-height:1.55">✓ We will email you when a beta place or public access is ready.</p><p style="margin:0 0 10px;line-height:1.55">✓ Existing beta testers keep free lifetime access. Joining this launch list does not activate a trial or a subscription.</p><p style="margin:0;line-height:1.55">✓ Public access is planned with 30 days free, then £14.99 monthly or £149.99 annually.</p></div><h2 style="margin:28px 0 10px;font-size:19px">One place for the working day</h2><p style="margin:0 0 22px;color:#665c50;line-height:1.6">See the day ahead, call a client, tick off tasks, complete bookings and keep an eye on money made, spent and owed.</p><a href="https://workloop.uk/help/welcome" style="display:inline-block;padding:15px 22px;background:#91b4c8;color:#443c32;text-decoration:none;border-radius:6px;border:1px solid #443c32;font-weight:700">Open your welcome pack</a><p style="margin:30px 0 0;color:#665c50;font-size:14px;line-height:1.6">Questions? Contact <a href="mailto:support@workloop.uk" style="color:#286280">support@workloop.uk</a>.<br>You can leave the launch list at any time by emailing us.</p></td></tr></table></td></tr></table></body></html>`;
  return withWorkloopOperator({ subject, plainText, html });
}

export async function drainWaitlistWelcomeEmails(input: {
  client: BookingConfirmationRpcClient;
  config: BookingConfirmationEmailConfig;
  limit?: number;
  fetcher?: typeof fetch;
}) {
  const { data, error } = await input.client.rpc(
    "claim_waitlist_welcome_emails",
    {
      p_limit: input.limit ?? 20,
    },
  );
  if (error) throw new Error(`waitlist_email_claim_failed:${error.code ?? ""}`);
  const claims = Array.isArray(data) ? data as Claim[] : [];
  let sent = 0;
  let pending = 0;
  let failed = 0;
  for (const claim of claims) {
    let providerMessageId = "";
    let delivered = false;
    let failure = "";
    try {
      const content = waitlistWelcomeEmailContent();
      const provider = await (input.fetcher ?? fetch)(
        "https://api.resend.com/emails",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${input.config.apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `launch-waitlist-joined/${claim.outbox_id}`,
          },
          body: JSON.stringify({
            from: input.config.from,
            reply_to: "support@workloop.uk",
            to: [claim.recipient_email],
            subject: content.subject,
            text: content.plainText,
            html: content.html,
          }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!provider.ok) {
        throw new Error(`email_provider_http_${provider.status}`);
      }
      const body = await provider.json().catch(() => ({}));
      providerMessageId = typeof body?.id === "string" ? body.id : "";
      if (!providerMessageId) {
        throw new Error("email_provider_invalid_response");
      }
      delivered = true;
    } catch (error) {
      failure = error instanceof Error
        ? error.message.slice(0, 500)
        : "email_provider_unavailable";
    }
    const completion = await input.client.rpc("finish_waitlist_welcome_email", {
      p_outbox_id: claim.outbox_id,
      p_lease_token: claim.lease_token,
      p_sent: delivered,
      p_provider_message_id: providerMessageId || null,
      p_error: failure || null,
    });
    if (completion.error) {
      throw new Error(
        `waitlist_email_finish_failed:${completion.error.code ?? ""}`,
      );
    }
    if (completion.data === "sent") sent++;
    else if (completion.data === "failed") failed++;
    else pending++;
  }
  return { processed: claims.length, sent, pending, failed };
}
