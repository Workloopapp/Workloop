export type SmsRpcClient = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: { code?: string } | null;
  }>;
};
type Env = (name: string) => string | undefined;
export type BookingSmsConfig = {
  accountSid: string;
  authToken: string;
  messagingServiceSid: string;
  webhookBase: string;
  globalDailyLimit: number;
  workspaceDailyLimit: number;
  phoneDailyLimit: number;
};
export const isUkSmsMobile = (value: string) =>
  /^\+44(7[1-57-9][0-9]{8}|7624[0-9]{6})$/.test(value);

function providerConfig(env: Env): BookingSmsConfig | null {
  const accountSid = env("TWILIO_ACCOUNT_SID") ?? "";
  const authToken = env("TWILIO_AUTH_TOKEN") ?? "";
  const messagingServiceSid = env("TWILIO_REMINDER_MESSAGING_SERVICE_SID") ??
    "";
  const webhookBase = env("TWILIO_SMS_WEBHOOK_BASE_URL") ?? "";
  if (
    !/^AC[0-9a-f]{32}$/i.test(accountSid) ||
    !/^[0-9a-f]{32}$/i.test(authToken) ||
    !/^MG[0-9a-f]{32}$/i.test(messagingServiceSid)
  ) return null;
  try {
    const url = new URL(webhookBase);
    if (
      url.protocol !== "https:" || url.username || url.password || url.search ||
      url.hash ||
      !url.pathname.endsWith("/functions/v1/sms-booking-reminders")
    ) return null;
  } catch {
    return null;
  }
  const bound = (name: string, maximum: number) => {
    const value = Number(env(name) ?? maximum);
    return Number.isInteger(value) && value >= 1
      ? Math.min(value, maximum)
      : maximum;
  };
  return {
    accountSid,
    authToken,
    messagingServiceSid,
    webhookBase,
    globalDailyLimit: bound("BOOKING_SMS_GLOBAL_DAILY_LIMIT", 1000),
    workspaceDailyLimit: bound("BOOKING_SMS_WORKSPACE_DAILY_LIMIT", 100),
    phoneDailyLimit: bound("BOOKING_SMS_PHONE_DAILY_LIMIT", 6),
  };
}

function validSmsLimits(env: Env) {
  return [
    "BOOKING_SMS_GLOBAL_DAILY_LIMIT",
    "BOOKING_SMS_WORKSPACE_DAILY_LIMIT",
    "BOOKING_SMS_PHONE_DAILY_LIMIT",
  ].every((name) => {
    const raw = env(name);
    return raw === undefined ||
      (Number.isInteger(Number(raw)) && Number(raw) >= 1);
  });
}

export function bookingSmsCapabilities(env: Env) {
  const configured = providerConfig(env) !== null;
  const limitsValid = validSmsLimits(env);
  const enabled = limitsValid && env("BOOKING_SMS_ENABLED") === "true" &&
    env("TWILIO_REMINDER_SERVICE_READY") === "true";
  return {
    available: configured && enabled,
    provider: "twilio",
    reason: !configured
      ? "provider_not_configured"
      : !limitsValid
      ? "invalid_limits"
      : enabled
      ? null
      : "disabled",
    supported_region: "UK mobile numbers",
    allowed_minutes: [1440, 60],
    customer_permission_required: true,
  };
}

export function bookingSmsConfig(env: Env): BookingSmsConfig | null {
  return bookingSmsCapabilities(env).available ? providerConfig(env) : null;
}

// Webhooks must continue accepting STOP and delivery reports when sends pause.
export const bookingSmsWebhookConfig = providerConfig;

function clean(value: unknown, limit: number) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(
    /\s+/g,
    " ",
  ).trim().slice(0, limit);
}

export function bookingReminderSms(payload: Record<string, unknown>) {
  if (![1440, 60].includes(Number(payload.minutes_before))) {
    throw new Error("invalid_reminder_interval");
  }
  const date = new Date(String(payload.start_time ?? ""));
  if (!Number.isFinite(date.getTime())) throw new Error("invalid_booking_time");
  const timezone = String(payload.timezone ?? "Europe/London");
  let time: string;
  try {
    time = new Intl.DateTimeFormat("en-GB", {
      timeZone: timezone,
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZoneName: "short",
    }).format(date);
  } catch {
    throw new Error("invalid_business_timezone");
  }
  const business = clean(payload.business_name, 40) || "your business";
  const phone = clean(payload.business_phone, 40);
  const contact = /^\+?[0-9 ()-]{7,40}$/.test(phone)
    ? `Contact ${phone}.`
    : "Contact the business directly.";
  // Omit customer names, service titles, addresses and private notes from texts.
  // No promotional copy; STOP affects reminders, never the booking itself.
  const body =
    `Workloop for ${business}: booking reminder, ${time}. ${contact} Reply STOP to stop reminders.`;
  if (body.length > 200) throw new Error("sms_too_long");
  return body;
}

export async function drainBookingReminderSms(input: {
  client: SmsRpcClient;
  config: BookingSmsConfig | null;
  fetcher?: typeof fetch;
  now?: () => Date;
  limit?: number;
}) {
  const config = input.config;
  if (!config) {
    return { disabled: true, accepted: 0, failed: 0, uncertain: 0, skipped: 0 };
  }
  const call = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await input.client.rpc(name, args);
    if (error) throw new Error(`sms_rpc_${name}:${error.code ?? "unknown"}`);
    return data;
  };
  const claims = await call("claim_booking_reminder_sms", {
    p_limit: input.limit ?? 5,
  }) as Array<{ outbox_id: string; lease_token: string }>;
  let accepted = 0, failed = 0, uncertain = 0, skipped = 0;
  for (const claim of claims ?? []) {
    const dispatch = await call("begin_booking_reminder_sms", {
      p_outbox_id: claim.outbox_id,
      p_lease_token: claim.lease_token,
      p_global_daily_limit: config.globalDailyLimit,
      p_workspace_daily_limit: config.workspaceDailyLimit,
      p_phone_daily_limit: config.phoneDailyLimit,
    }) as {
      dispatch_token: string;
      recipient_phone: string;
      payload: Record<string, unknown>;
    } | null;
    if (!dispatch) {
      skipped++;
      continue;
    }
    let providerId: string | null = null;
    let outcome = "rejected";
    let error: string | null = null;
    let submitted = false;
    try {
      if (!isUkSmsMobile(dispatch.recipient_phone)) {
        throw new Error("invalid_mobile");
      }
      const body = bookingReminderSms(dispatch.payload);
      const start = new Date(String(dispatch.payload.start_time)).getTime();
      const now = (input.now ?? (() => new Date()))().getTime();
      const validity = Math.min(300, Math.floor((start - now) / 1000));
      if (validity < 6) throw new Error("booking_started");
      const callback = `${config.webhookBase}?action=status&outbox=${
        encodeURIComponent(claim.outbox_id)
      }&dispatch=${encodeURIComponent(dispatch.dispatch_token)}`;
      submitted = true;
      const response = await (input.fetcher ?? fetch)(
        `https://api.twilio.com/2010-04-01/Accounts/${config.accountSid}/Messages.json`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${
              btoa(`${config.accountSid}:${config.authToken}`)
            }`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({
            To: dispatch.recipient_phone,
            MessagingServiceSid: config.messagingServiceSid,
            Body: body,
            StatusCallback: callback,
            ValidityPeriod: String(validity),
          }),
          signal: AbortSignal.timeout(10000),
        },
      );
      const result = await response.json().catch(() => null) as {
        sid?: unknown;
        code?: unknown;
      } | null;
      if (
        response.ok && typeof result?.sid === "string" &&
        /^SM[0-9a-f]{32}$/i.test(result.sid)
      ) {
        providerId = result.sid;
        outcome = "accepted";
        accepted++;
      } else if (response.status === 429) {
        outcome = "retry";
        error = "provider_http_429";
        failed++;
      } else if (response.status >= 400 && response.status < 500) {
        outcome = "rejected";
        error = Number.isInteger(result?.code)
          ? `provider_${result!.code}`
          : `provider_http_${response.status}`;
        failed++;
      } else {
        outcome = "uncertain";
        error = "provider_outcome_unknown";
        uncertain++;
      }
    } catch (e) {
      outcome = submitted ? "uncertain" : "rejected";
      error = submitted
        ? "provider_outcome_unknown"
        : e instanceof Error && /^[a-z_]+$/.test(e.message)
        ? e.message
        : "invalid_sms_content";
      if (submitted) uncertain++;
      else failed++;
    }
    await call("finish_booking_reminder_sms", {
      p_outbox_id: claim.outbox_id,
      p_dispatch_token: dispatch.dispatch_token,
      p_provider_message_id: providerId,
      p_outcome: outcome,
      p_error: error,
    });
  }
  return { disabled: false, accepted, failed, uncertain, skipped };
}
