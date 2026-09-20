import { withWorkloopOperator } from "./workloop_operator_email.ts";
import type {
  BookingConfirmationEmailConfig,
  BookingConfirmationRpcClient,
} from "./booking_confirmation_email.ts";

export type AccountDeletionEmailEvent =
  | "deletion_requested"
  | "account_deleted";

type Claim = {
  outbox_id: string;
  lease_token: string;
  recipient_email: string;
  event: AccountDeletionEmailEvent;
  attempt_count: number;
};

export function accountDeletionEmailConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): BookingConfirmationEmailConfig | null {
  const apiKey = readEnv("RESEND_API_KEY")?.trim() ?? "";
  const from = (readEnv("ACCOUNT_DELETION_EMAIL_FROM") ??
    readEnv("ACCOUNT_WELCOME_EMAIL_FROM") ??
    readEnv("WAITLIST_CONFIRMATION_EMAIL_FROM") ??
    readEnv("BOOKING_CONFIRMATION_EMAIL_FROM") ?? "").trim();
  if (apiKey.length < 16 || from.length < 3) return null;
  return { apiKey, from };
}

export function accountDeletionEmailContent(event: AccountDeletionEmailEvent) {
  if (event === "deletion_requested") {
    const subject = "We received your Workloop deletion request";
    const plainText = `Hi,

We received your request to delete your Workloop account.

Your account has not been deleted yet. We will process the request through our protected deletion workflow and send another email when it is complete.

If you made this request, there is nothing else you need to do. If you did not request deletion, contact support@workloop.uk immediately.

Read our privacy notice: https://workloop.uk/privacy

Workloop
The business operating system for one.`;
    const html =
      `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><style>@font-face{font-family:Manrope;src:url('https://workloop.uk/Manrope-Variable.ttf') format('truetype');font-weight:100 900}</style></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:'Manrope',Arial,sans-serif"><div style="display:none;max-height:0;overflow:hidden">We received your Workloop account deletion request.</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5edd9"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:34px"><div style="font-size:26px;font-weight:650;letter-spacing:-.04em">workloop</div><p style="margin:30px 0 12px;color:#286280;font-size:12px;font-weight:600;letter-spacing:.08em;padding:10px 12px;background:#c3d7e4;border:1px solid #8d8070;border-radius:5px;color:#443c32">REQUEST RECEIVED</p><h1 style="margin:0 0 18px;font-size:34px;line-height:1.1">We have your deletion request.</h1><p style="color:#665c50;font-size:17px;line-height:1.6">Your account has <strong>not been deleted yet</strong>. We will process the request through our protected deletion workflow and email you again when it is complete.</p><div style="margin:24px 0;padding:20px;background:#f0d18b;border-radius:6px;border:1px solid #8d8070;line-height:1.6">If you made this request, there is nothing else you need to do. If you did not request deletion, contact us immediately.</div><a href="mailto:support@workloop.uk" style="display:inline-block;padding:15px 22px;background:#91b4c8;color:#443c32;text-decoration:none;border-radius:6px;border:1px solid #443c32;font-weight:700">Contact Workloop support</a><p style="margin:28px 0 0;color:#665c50;font-size:14px;line-height:1.6">You can read our <a href="https://workloop.uk/privacy" style="color:#286280">privacy notice</a> for more information.</p></td></tr></table></td></tr></table></body></html>`;
    return withWorkloopOperator({ subject, plainText, html });
  }

  const subject = "Your Workloop account has been deleted";
  const plainText = `Hi,

Your Workloop account and workspace data have been deleted. You can no longer sign in with this account.

Limited records may be retained where required for security, legal or financial obligations, as explained in our privacy notice.

Read our privacy notice: https://workloop.uk/privacy

If you have any questions, contact support@workloop.uk.

Workloop
The business operating system for one.`;
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><style>@font-face{font-family:Manrope;src:url('https://workloop.uk/Manrope-Variable.ttf') format('truetype');font-weight:100 900}</style></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:'Manrope',Arial,sans-serif"><div style="display:none;max-height:0;overflow:hidden">Your Workloop account deletion is complete.</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5edd9"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:34px"><div style="font-size:26px;font-weight:650;letter-spacing:-.04em">workloop</div><p style="margin:30px 0 12px;color:#286280;font-size:12px;font-weight:600;letter-spacing:.08em;padding:10px 12px;background:#c3d7e4;border:1px solid #8d8070;border-radius:5px;color:#443c32">DELETION COMPLETE</p><h1 style="margin:0 0 18px;font-size:34px;line-height:1.1">Your account has been deleted.</h1><p style="color:#665c50;font-size:17px;line-height:1.6">Your Workloop account and workspace data have been deleted. You can no longer sign in with this account.</p><div style="margin:24px 0;padding:20px;background:#f0d18b;border-radius:6px;border:1px solid #8d8070;color:#665c50;line-height:1.6">Limited records may be retained where required for security, legal or financial obligations, as explained in our privacy notice.</div><a href="https://workloop.uk/privacy" style="display:inline-block;padding:15px 22px;background:#91b4c8;color:#443c32;text-decoration:none;border-radius:6px;border:1px solid #443c32;font-weight:700">Read the privacy notice</a><p style="margin:28px 0 0;color:#665c50;font-size:14px;line-height:1.6">Questions? <a href="mailto:support@workloop.uk" style="color:#286280">support@workloop.uk</a></p></td></tr></table></td></tr></table></body></html>`;
  return withWorkloopOperator({ subject, plainText, html });
}

export async function drainAccountDeletionEmails(input: {
  client: BookingConfirmationRpcClient;
  config: BookingConfirmationEmailConfig;
  limit?: number;
  fetcher?: typeof fetch;
}) {
  const { data, error } = await input.client.rpc(
    "claim_account_deletion_emails",
    {
      p_limit: input.limit ?? 20,
    },
  );
  if (error) {
    throw new Error(`account_deletion_email_claim_failed:${error.code ?? ""}`);
  }
  const claims = Array.isArray(data) ? data as Claim[] : [];
  let sent = 0;
  let pending = 0;
  let failed = 0;
  for (const claim of claims) {
    let providerMessageId = "";
    let delivered = false;
    let failure = "";
    try {
      const content = accountDeletionEmailContent(claim.event);
      const provider = await (input.fetcher ?? fetch)(
        "https://api.resend.com/emails",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${input.config.apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `account-${claim.event}/${claim.outbox_id}`,
          },
          body: JSON.stringify({
            from: input.config.from,
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
    const completion = await input.client.rpc("finish_account_deletion_email", {
      p_outbox_id: claim.outbox_id,
      p_lease_token: claim.lease_token,
      p_sent: delivered,
      p_provider_message_id: providerMessageId || null,
      p_error: failure || null,
    });
    if (completion.error) {
      throw new Error(
        `account_deletion_email_finish_failed:${completion.error.code ?? ""}`,
      );
    }
    if (completion.data === "sent") sent++;
    else if (completion.data === "failed") failed++;
    else pending++;
  }
  return { processed: claims.length, sent, pending, failed };
}
