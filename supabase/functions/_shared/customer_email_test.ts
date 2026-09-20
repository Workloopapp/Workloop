import { accountJourneyEmail } from "./account_journey_email.ts";
import {
  bookingReminderEmail,
  drainBookingReminderEmails,
} from "./booking_reminder_email.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
Deno.test("all account templates have working destinations, unsubscribe and escaped links", () => {
  for (
    const step of [
      ...Array.from({ length: 9 }, (_, i) => i + 10),
      100,
      101,
      102,
      ...Array.from({ length: 12 }, (_, i) => 1005 + i),
    ]
  ) {
    const mail = accountJourneyEmail({
      step,
      unsubscribeUrl: 'https://example.test/?a=1&b="x"',
    });
    assert(
      mail.html.includes("a=1&amp;b=&quot;x&quot;"),
      "escaped unsubscribe",
    );
    assert(mail.text.includes("Unsubscribe"), "unsubscribe");
    assert(mail.text.includes("https://workloop.uk/"), "real destination");
    assert(
      !mail.text.includes("You requested"),
      "does not falsely claim opt-in",
    );
    assert(mail.html.length < 25000, "bounded message size");
  }
});
Deno.test("reminder correctly renders UK summer time without leaking private notes", () => {
  const mail = bookingReminderEmail({
    business_name: "A & B",
    customer_name: "<script>x</script>",
    booking_title: "Visit",
    start_time: "2026-09-06T09:00:00Z",
    end_time: "2026-09-06T10:00:00Z",
    timezone: "Europe/London",
    minutes_before: 60,
    notes: "PRIVATE-NOTE",
  }, "https://example.test/unsubscribe");
  assert(mail.text.includes("10:00"), "business time");
  assert(mail.text.includes("1 hour"), "duration");
  assert(mail.html.includes("&lt;script&gt;"), "escape customer");
  assert(!mail.html.includes("PRIVATE-NOTE"), "private notes excluded");
  assert(
    !mail.text.includes("business tip"),
    "no unrelated marketing to clients",
  );
  assert(mail.text.includes("does not cancel"), "clear preference effect");
});
Deno.test("reminder handles winter and invalid timezone safely", () => {
  for (const timezone of ["Europe/London", "Not/AZone"]) {
    const mail = bookingReminderEmail({
      start_time: "2026-12-06T09:00:00Z",
      end_time: "2026-12-06T10:00:00Z",
      timezone,
      minutes_before: 1440,
    }, "https://example.test");
    assert(mail.text.includes("09:00"), "winter/UTC time");
    assert(mail.subject.includes("24 hours"), "day lead");
  }
});
Deno.test("revoked reminder lease never reaches provider", async () => {
  let calls = 0;
  const client = {
    rpc: async (name: string) => ({
      data: name === "claim_booking_reminder_emails"
        ? [{ outbox_id: "id", lease_token: "lease" }]
        : false,
      error: null,
    }),
  };
  const result = await drainBookingReminderEmails({
    client,
    config: { from: "Workloop <hello@workloop.uk>", apiKey: "test" },
    supabaseUrl: "https://example.test",
    fetcher: (() => {
      calls++;
      throw new Error("must not send");
    }) as typeof fetch,
  });
  assert(calls === 0 && result.skipped === 1, "revoked send blocked");
});
Deno.test("provider failures are durable and retry uses stable idempotency", async () => {
  const seen: Record<string, unknown>[] = [];
  let completion: Record<string, unknown> | undefined;
  const client = {
    rpc: async (name: string, params?: Record<string, unknown>) => {
      if (name === "finish_booking_reminder_email") completion = params;
      return {
        data: name === "claim_booking_reminder_emails"
          ? [{
            outbox_id: "id",
            lease_token: "lease",
            recipient_email: "customer@example.test",
            reply_email: "owner@example.test",
            unsubscribe_token: "token",
            payload: { minutes_before: 120 },
          }]
          : name === "customer_email_contact"
          ? { email: "owner@example.test" }
          : true,
        error: null,
      };
    },
  };
  const fetcher = (async (_url: unknown, init: RequestInit) => {
    seen.push(JSON.parse(String(init.body)));
    assert(
      new Headers(init.headers).get("Idempotency-Key") ===
        "booking-reminder/id",
      "stable idempotency",
    );
    return new Response("{}", { status: 503 });
  }) as typeof fetch;
  const result = await drainBookingReminderEmails({
    client,
    config: { from: "Workloop <hello@workloop.uk>", apiKey: "test" },
    supabaseUrl: "https://example.test",
    fetcher,
  });
  assert(
    result.failed === 1 && completion?.p_provider_message_id === null,
    "failed delivery never marked sent",
  );
  assert(completion?.p_error === "provider_http_503", "sanitised retry cause");
  assert(seen[0].reply_to === "owner@example.test", "reply routes to owner");
});
