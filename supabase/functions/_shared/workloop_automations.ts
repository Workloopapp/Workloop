import { withWorkloopOperator } from "./workloop_operator_email.ts";
import type { BookingConfirmationEmailConfig } from "./booking_confirmation_email.ts";
import { escapeHtml } from "./booking_confirmation_email.ts";

type DeletionRequest = { id: string };
type OperationalAlert = {
  alert_id: string;
  alert_key: string;
  category: string;
  severity: string;
  message: string;
  first_seen_at: string;
};
type RpcError = { code?: string; message?: string };
type DeletionQuery = {
  in: (column: string, values: string[]) => DeletionQuery;
  order: (
    column: string,
    options: { ascending: boolean },
  ) => DeletionQuery;
  limit: (
    value: number,
  ) => PromiseLike<{ data: unknown; error: RpcError | null }>;
};

export type AutomationClient = {
  from: (table: string) => {
    select: (columns: string) => DeletionQuery;
  };
  rpc: (
    name: string,
    params?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: RpcError | null }>;
};

export type AutomationAlertConfig = BookingConfirmationEmailConfig & {
  recipient: string;
};

export function automationAlertConfig(
  readEnv: (name: string) => string | undefined = Deno.env.get,
): AutomationAlertConfig | null {
  const apiKey = readEnv("RESEND_API_KEY")?.trim() ?? "";
  const from = readEnv("BOOKING_CONFIRMATION_EMAIL_FROM")?.trim() ?? "";
  const recipient = readEnv("OPERATIONS_ALERT_EMAIL")?.trim().toLowerCase() ??
    "";
  if (
    apiKey.length < 16 || from.length < 3 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)
  ) return null;
  return { apiKey, from, recipient };
}

export async function processAccountDeletions(input: {
  client: AutomationClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  adminToken: string;
  fetcher?: typeof fetch;
  limit?: number;
}) {
  if (input.adminToken.length < 32) {
    return {
      configured: false,
      examined: 0,
      completed: 0,
      deferred: 0,
      failed: 0,
    };
  }
  const { data, error } = await input.client
    .from("account_deletion_requests")
    .select("id")
    .in("status", ["requested", "processing"])
    .order("requested_at", { ascending: true })
    .limit(input.limit ?? 20);
  if (error) throw new Error(`account_deletion_claim_failed:${error.code}`);

  const requests = (data ?? []) as DeletionRequest[];
  let completed = 0;
  let deferred = 0;
  let failed = 0;
  const fetcher = input.fetcher ?? fetch;
  for (const request of requests) {
    try {
      const result = await fetcher(
        `${input.supabaseUrl}/functions/v1/complete-account-deletion`,
        {
          method: "POST",
          headers: {
            apikey: input.serviceRoleKey,
            Authorization: `Bearer ${input.serviceRoleKey}`,
            "Content-Type": "application/json",
            "x-admin-token": input.adminToken,
          },
          body: JSON.stringify({
            requestId: request.id,
            notes: "Completed by the scheduled Workloop automation worker.",
          }),
          signal: AbortSignal.timeout(25_000),
        },
      );
      if (result.ok) completed++;
      else if (result.status === 409) deferred++;
      else failed++;
    } catch (_) {
      failed++;
    }
  }
  return {
    configured: true,
    examined: requests.length,
    completed,
    deferred,
    failed,
  };
}

export async function runDatabaseAutomations(client: AutomationClient) {
  const { data, error } = await client.rpc("run_workloop_automations");
  if (error) throw new Error(`workloop_automation_rpc_failed:${error.code}`);
  const deletionEmailHealth = await client.rpc(
    "refresh_account_deletion_email_alerts",
  );
  if (deletionEmailHealth.error) {
    throw new Error(
      `account_deletion_email_health_failed:${deletionEmailHealth.error.code}`,
    );
  }
  return { business: data, deletionEmailAlerts: deletionEmailHealth.data };
}

export function operationalAlertEmailContent(alert: OperationalAlert) {
  const severity = alert.severity === "critical" ? "Critical" : "Warning";
  const subject = `[Workloop ${severity}] ${
    alert.category.replaceAll("_", " ")
  }`;
  const plainText =
    `${severity} operational alert\n\n${alert.message}\n\nAlert key: ${alert.alert_key}\nFirst seen: ${alert.first_seen_at}`;
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>@font-face{font-family:Manrope;src:url('https://workloop.uk/Manrope-Variable.ttf') format('truetype');font-weight:100 900}</style></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:'Manrope',Arial,sans-serif"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:32px"><div style="font-size:26px;font-weight:650;letter-spacing:-.04em">workloop</div><p style="margin:28px 0 20px;padding:10px 12px;background:#f0d18b;border:1px solid #8d8070;border-radius:5px;font-size:12px;letter-spacing:.08em">SYSTEM NOTICE</p><h1 style="font-size:28px;line-height:1.2">${
      escapeHtml(severity)
    } operational alert</h1><p style="font-size:16px;line-height:1.6">${
      escapeHtml(alert.message)
    }</p><p style="padding:18px;background:#c3d7e4;border:1px solid #8d8070;border-radius:6px;line-height:1.6;overflow-wrap:anywhere"><strong>Alert key:</strong> ${
      escapeHtml(alert.alert_key)
    }<br><strong>First seen:</strong> ${
      escapeHtml(alert.first_seen_at)
    }</p></td></tr></table></td></tr></table></body></html>`;
  return withWorkloopOperator({ subject, plainText, html });
}

export async function deliverOperationalAlerts(input: {
  client: AutomationClient;
  config: AutomationAlertConfig | null;
  fetcher?: typeof fetch;
  limit?: number;
  now?: Date;
}) {
  if (input.config === null) {
    return { configured: false, claimed: 0, sent: 0, failed: 0 };
  }
  const { data, error } = await input.client.rpc("claim_operational_alerts", {
    p_limit: input.limit ?? 20,
  });
  if (error) throw new Error(`operational_alert_claim_failed:${error.code}`);
  const alerts = Array.isArray(data) ? data as OperationalAlert[] : [];
  const fetcher = input.fetcher ?? fetch;
  const window = Math.floor((input.now ?? new Date()).getTime() / 21_600_000);
  let sent = 0;
  let failed = 0;

  for (const alert of alerts) {
    const content = operationalAlertEmailContent(alert);
    let delivered = false;
    try {
      const response = await fetcher("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${input.config.apiKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `operational-alert/${alert.alert_id}/${window}`,
        },
        body: JSON.stringify({
          from: input.config.from,
          to: [input.config.recipient],
          subject: content.subject,
          text: content.plainText,
          html: content.html,
        }),
        signal: AbortSignal.timeout(10_000),
      });
      delivered = response.ok;
    } catch (_) {
      delivered = false;
    }
    const finish = await input.client.rpc(
      "finish_operational_alert_delivery",
      { p_alert_id: alert.alert_id, p_sent: delivered },
    );
    if (finish.error) {
      throw new Error(`operational_alert_finish_failed:${finish.error.code}`);
    }
    if (delivered) sent++;
    else failed++;
  }
  return { configured: true, claimed: alerts.length, sent, failed };
}
