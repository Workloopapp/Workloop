import twilio from "npm:twilio@6.1.0";
import {
  bookingReminderSms,
  bookingSmsCapabilities,
  type BookingSmsConfig,
  bookingSmsConfig,
  bookingSmsWebhookConfig,
  drainBookingReminderSms,
  type SmsRpcClient,
} from "../_shared/booking_sms.ts";
import { handleBookingSmsWebhook } from "../_shared/booking_sms_webhook.ts";

const assert = (value: unknown, message = "Assertion failed") => {
  if (!value) throw new Error(message);
};
const equal = (actual: unknown, expected: unknown) =>
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
const config: BookingSmsConfig = {
  accountSid: "AC" + "1".repeat(32),
  authToken: "2".repeat(32),
  messagingServiceSid: "MG" + "3".repeat(32),
  webhookBase:
    "https://project.example.test/functions/v1/sms-booking-reminders",
  globalDailyLimit: 1000,
  workspaceDailyLimit: 100,
  phoneDailyLimit: 6,
};
const envValues: Record<string, string> = {
  TWILIO_ACCOUNT_SID: config.accountSid,
  TWILIO_AUTH_TOKEN: config.authToken,
  TWILIO_REMINDER_MESSAGING_SERVICE_SID: config.messagingServiceSid,
  TWILIO_SMS_WEBHOOK_BASE_URL: config.webhookBase,
};
const outbox = "c5000000-0000-4000-8000-000000000001";
const dispatch = "c6000000-0000-4000-8000-000000000001";
const sid = "SM" + "4".repeat(32);
const payload = {
  start_time: "2026-09-05T16:00:00Z",
  timezone: "Europe/London",
  minutes_before: 60,
  business_name: "Valet Studio",
  business_phone: "+44 7700 900999",
};
const now = () => new Date("2026-09-05T15:05:00Z");

function fixture(
  overrides: Record<string, unknown> = {},
  before: unknown = undefined,
) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client: SmsRpcClient = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === "claim_booking_reminder_sms") {
        return {
          data: [{ outbox_id: outbox, lease_token: "lease" }],
          error: null,
        };
      }
      if (name === "begin_booking_reminder_sms") {
        return {
          data: before === undefined
            ? {
              dispatch_token: dispatch,
              recipient_phone: "+447700900123",
              payload,
              ...overrides,
            }
            : before,
          error: null,
        };
      }
      return { data: null, error: null };
    },
  };
  return {
    calls,
    client,
    finish: () =>
      calls.find((c) => c.name === "finish_booking_reminder_sms")?.args,
  };
}
const response = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.test("SMS is unavailable until all provider configuration and both explicit enable flags exist", async () => {
  equal(
    bookingSmsCapabilities(() => undefined).reason,
    "provider_not_configured",
  );
  equal(bookingSmsConfig((key) => envValues[key]), null);
  assert(
    bookingSmsWebhookConfig((key) => envValues[key]) !== null,
    "STOP remains available when sending is paused",
  );
  const oneFlag = { ...envValues, BOOKING_SMS_ENABLED: "true" };
  equal(bookingSmsConfig((key) => oneFlag[key as keyof typeof oneFlag]), null);
  const enabled: Record<string, string> = {
    ...oneFlag,
    TWILIO_REMINDER_SERVICE_READY: "true",
    BOOKING_SMS_PHONE_DAILY_LIMIT: "5000",
  };
  equal(bookingSmsConfig((key) => enabled[key])?.phoneDailyLimit, 6);
  equal(bookingSmsCapabilities((key) => enabled[key]).available, true);
  enabled.TWILIO_SMS_WEBHOOK_BASE_URL += "?action=inbound";
  equal(bookingSmsConfig((key) => enabled[key]), null);
  const f = fixture();
  equal(
    (await drainBookingReminderSms({ client: f.client, config: null }))
      .disabled,
    true,
  );
  equal(f.calls.length, 0);
});

Deno.test("template uses actual business timezone and minimal service content", () => {
  const summer = bookingReminderSms({
    ...payload,
    customer_name: "PRIVATE NAME",
    title: "PRIVATE TREATMENT",
    notes: "PRIVATE NOTES",
  });
  assert(summer.includes("17:00") && summer.includes("BST"));
  assert(
    summer.includes("Workloop for Valet Studio") &&
      summer.includes("Reply STOP"),
  );
  assert(!summer.includes("PRIVATE"));
  const winter = bookingReminderSms({
    ...payload,
    start_time: "2026-12-05T16:00:00Z",
    business_phone: "",
  });
  assert(
    winter.includes("16:00") && winter.includes("GMT") &&
      winter.includes("Contact the business directly"),
  );
  const distant = bookingReminderSms({
    ...payload,
    timezone: "America/New_York",
  });
  assert(distant.includes("12:00"));
  assert(
    bookingReminderSms({ ...payload, business_name: "é".repeat(80) }).length <=
      200,
  );
  for (
    const patch of [{ timezone: "Invalid/Zone" }, { start_time: "bad" }, {
      minutes_before: 120,
    }]
  ) {
    let rejected = false;
    try {
      bookingReminderSms({ ...payload, ...patch });
    } catch {
      rejected = true;
    }
    assert(rejected, "Invalid current booking must not produce a text");
  }
});

Deno.test("dispatch sends a bounded fresh text through the distinct reminder service", async () => {
  const f = fixture();
  let sent = 0;
  const result = await drainBookingReminderSms({
    client: f.client,
    config,
    now,
    fetcher: async (url, init) => {
      sent++;
      assert(
        String(url).endsWith(`/Accounts/${config.accountSid}/Messages.json`),
      );
      const form = new URLSearchParams(String(init?.body));
      equal(form.get("To"), "+447700900123");
      equal(form.get("MessagingServiceSid"), config.messagingServiceSid);
      equal(form.get("ValidityPeriod"), "300");
      equal(form.get("AddressRetention"), null); // incompatible with Advanced Opt-Out
      equal(form.get("ContentRetention"), null); // no unconfigured paid feature
      assert(
        form.get("StatusCallback")?.includes(
          `outbox=${outbox}&dispatch=${dispatch}`,
        ),
      );
      assert(init?.signal !== undefined);
      return response(201, { sid });
    },
  });
  equal(sent, 1);
  equal(result.accepted, 1);
  equal(f.finish()?.p_outcome, "accepted");
  equal(f.finish()?.p_provider_message_id, sid);
});

Deno.test("latest eligibility rejection skips provider call; invalid mobile/time rejects before network", async () => {
  let sends = 0;
  const fetcher: typeof fetch = async () => {
    sends++;
    return response(201, { sid });
  };
  const stale = fixture({}, null);
  equal(
    (await drainBookingReminderSms({
      client: stale.client,
      config,
      now,
      fetcher,
    })).skipped,
    1,
  );
  equal(stale.finish(), undefined);
  for (
    const overrides of [{ recipient_phone: "+14155550123" }, {
      payload: { ...payload, start_time: "2026-09-05T15:00:00Z" },
    }]
  ) {
    const f = fixture(overrides);
    await drainBookingReminderSms({ client: f.client, config, now, fetcher });
    equal(f.finish()?.p_outcome, "rejected");
  }
  equal(sends, 0);
});

Deno.test("definite rate rejection may retry; ambiguous provider results never blindly retry", async () => {
  const cases: Array<
    { fetcher: typeof fetch; outcome: string; error: string }
  > = [
    {
      fetcher: async () => response(429, { code: 20429 }),
      outcome: "retry",
      error: "provider_http_429",
    },
    {
      fetcher: async () => response(400, { code: 21610 }),
      outcome: "rejected",
      error: "provider_21610",
    },
    {
      fetcher: async () => response(500, {}),
      outcome: "uncertain",
      error: "provider_outcome_unknown",
    },
    {
      fetcher: async () => response(201, {}),
      outcome: "uncertain",
      error: "provider_outcome_unknown",
    },
    {
      fetcher: async () => {
        throw new Error("Network lost after request");
      },
      outcome: "uncertain",
      error: "provider_outcome_unknown",
    },
  ];
  for (const sample of cases) {
    const f = fixture();
    await drainBookingReminderSms({
      client: f.client,
      config,
      now,
      fetcher: sample.fetcher,
    });
    equal(f.finish()?.p_outcome, sample.outcome);
    equal(f.finish()?.p_error, sample.error);
    equal(f.finish()?.p_provider_message_id, null);
  }
});

function webhookFixture(
  action: string,
  extra: Record<string, string>,
  mutate?: (value: { body: string; query: string; signature: string }) => void,
) {
  const params = {
    AccountSid: config.accountSid,
    MessagingServiceSid: config.messagingServiceSid,
    ...extra,
  };
  const query = action === "status"
    ? `?action=status&outbox=${outbox}&dispatch=${dispatch}`
    : "?action=inbound";
  const signed = {
    body: new URLSearchParams(params).toString(),
    query,
    signature: twilio.getExpectedTwilioSignature(
      config.authToken,
      config.webhookBase + query,
      params,
    ),
  };
  mutate?.(signed);
  const request = new Request(
    "http://internal-edge-proxy/sms-booking-reminders" + signed.query,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-Twilio-Signature": signed.signature,
      },
      body: signed.body,
    },
  );
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client: SmsRpcClient = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      return { data: null, error: null };
    },
  };
  return {
    calls,
    execute: () =>
      handleBookingSmsWebhook({
        request,
        config,
        client,
        validateSignature: twilio.validateRequest,
      }),
  };
}

Deno.test("real Twilio SDK validates canonical public callback URL through proxy", async () => {
  const f = webhookFixture("status", {
    MessageSid: sid,
    MessageStatus: "delivered",
    ExtraFutureField: "keep  all spaces",
  });
  equal((await f.execute()).status, 200);
  equal(f.calls[0].name, "record_booking_sms_status");
  equal(f.calls[0].args, {
    p_outbox_id: outbox,
    p_dispatch_token: dispatch,
    p_provider_message_id: sid,
    p_status: "delivered",
    p_error: null,
  });
});

Deno.test("tampered signature/body/query, duplicate form fields, and wrong account/service never write", async () => {
  const invalid = [
    webhookFixture(
      "status",
      { MessageSid: sid, MessageStatus: "delivered" },
      (s) => {
        s.signature = "invalid";
      },
    ),
    webhookFixture(
      "status",
      { MessageSid: sid, MessageStatus: "delivered" },
      (s) => {
        s.body = s.body.replace("delivered", "sent");
      },
    ),
    webhookFixture(
      "status",
      { MessageSid: sid, MessageStatus: "delivered" },
      (s) => {
        s.query += "&extra=changed";
      },
    ),
    webhookFixture(
      "status",
      { MessageSid: sid, MessageStatus: "delivered" },
      (s) => {
        s.body += "&MessageStatus=failed";
      },
    ),
    webhookFixture("status", {
      MessageSid: sid,
      MessageStatus: "delivered",
      AccountSid: "AC" + "9".repeat(32),
    }),
    webhookFixture("status", {
      MessageSid: sid,
      MessageStatus: "delivered",
      MessagingServiceSid: "MG" + "9".repeat(32),
    }),
  ];
  for (const f of invalid) {
    assert((await f.execute()).status >= 400);
    equal(f.calls.length, 0);
  }
});

Deno.test("STOP/START webhook records suppression but sends no duplicate confirmation or business reply", async () => {
  for (const type of ["STOP", "START", "HELP", ""]) {
    const f = webhookFixture("inbound", {
      From: "+447700900123",
      OptOutType: type,
      Body: "Any business conversation",
    });
    const result = await f.execute();
    equal(result.status, 200);
    equal(await result.text(), "<Response/>");
    if (type === "STOP" || type === "START") {
      equal(f.calls, [{
        name: "record_booking_sms_opt_out",
        args: { p_phone: "+447700900123", p_stopped: type === "STOP" },
      }]);
    } else equal(f.calls.length, 0);
  }
});

Deno.test("malformed delivery identifier and invalid inbound number fail closed", async () => {
  for (
    const f of [
      webhookFixture("status", { MessageSid: "wrong", MessageStatus: "sent" }),
      webhookFixture("inbound", { From: "07700900123", OptOutType: "STOP" }),
    ]
  ) {
    equal((await f.execute()).status, 400);
    equal(f.calls.length, 0);
  }
});

Deno.test("invalid operator cost limits close outbound sending while preserving STOP webhooks", () => {
  const enabled: Record<string, string> = {
    ...envValues,
    BOOKING_SMS_ENABLED: "true",
    TWILIO_REMINDER_SERVICE_READY: "true",
  };
  for (const value of ["0", "-1", "", "one", "1.5", "Infinity"]) {
    const settings = { ...enabled, BOOKING_SMS_GLOBAL_DAILY_LIMIT: value };
    equal(
      bookingSmsConfig((key) => settings[key as keyof typeof settings]),
      null,
    );
    equal(
      bookingSmsCapabilities((key) => settings[key as keyof typeof settings])
        .reason,
      "invalid_limits",
    );
    assert(
      bookingSmsWebhookConfig((key) =>
        settings[key as keyof typeof settings]
      ) !== null,
    );
  }
});

Deno.test("autumn DST duplicate clock hour remains unambiguous and provider validity shrinks near start", async () => {
  const before = bookingReminderSms({
    ...payload,
    start_time: "2026-10-25T00:30:00Z",
  });
  const after = bookingReminderSms({
    ...payload,
    start_time: "2026-10-25T01:30:00Z",
  });
  assert(before.includes("01:30") && before.includes("BST"));
  assert(after.includes("01:30") && after.includes("GMT"));
  const f = fixture();
  let validity = "";
  await drainBookingReminderSms({
    client: f.client,
    config,
    now: () => new Date("2026-09-05T15:59:30Z"),
    fetcher: async (_url, init) => {
      validity =
        new URLSearchParams(String(init?.body)).get("ValidityPeriod") ?? "";
      return response(201, { sid });
    },
  });
  equal(validity, "30");
});

Deno.test("failed database budget reservation cannot submit any provider request", async () => {
  const f = fixture();
  let submitted = false;
  const client: SmsRpcClient = {
    rpc: async (name, args) =>
      name === "begin_booking_reminder_sms"
        ? { data: null, error: { code: "XX000" } }
        : f.client.rpc(name, args),
  };
  let rejected = false;
  try {
    await drainBookingReminderSms({
      client,
      config,
      now,
      fetcher: async () => {
        submitted = true;
        return response(201, { sid });
      },
    });
  } catch {
    rejected = true;
  }
  assert(rejected);
  equal(submitted, false);
});
