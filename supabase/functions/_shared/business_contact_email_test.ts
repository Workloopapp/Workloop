import {
  businessContactEmail,
  loadBusinessEmailContact,
} from "./business_contact_email.ts";
import { exceptionEmail, exceptionEmailCases } from "./exception_email.ts";
import { bookingConfirmationEmailContent } from "./booking_confirmation_email.ts";
import { bookingReminderEmail } from "./booking_reminder_email.ts";
import {
  customerEventEmail,
  drainCustomerEventEmails,
} from "./customer_event_email.ts";
const assert = (v: unknown, m: string) => {
  if (!v) throw Error(m);
};
const payload = {
  minutes_before: 60,
  business_name: "Example & Co",
  business_contact: {
    email: "business@example.test",
    phone: "+44 7700 900123",
    website: "https://workloop.uk/example",
  },
  reference: "EXAMPLE-1",
  details: "Verified example only <script>",
  start_time: "2026-09-10T10:00:00Z",
  amount_minor: 4500,
  checkout_url: "https://checkout.stripe.com/c/pay/example",
};
Deno.test("all customer templates show direct business contact and never ask for replies", () => {
  const mails = [
    bookingConfirmationEmailContent({ payload } as never),
    bookingReminderEmail(payload, "https://example.test/stop"),
    ...[
      "request_received",
      "request_declined",
      "booking_changed",
      "booking_cancelled",
      "payment_request",
    ].map((e) => customerEventEmail(e as never, payload)),
    ...exceptionEmailCases.filter((c) => c[1] === "customer").map((c) =>
      exceptionEmail(c[0], payload)
    ),
  ];
  for (const m of mails) {
    const text = "text" in m ? m.text : m.plainText;
    assert(text.includes("business@example.test"), "direct email");
    assert(text.includes("+44 7700 900123"), "business phone");
    assert(!/\brepl(y|ies)\b/i.test(text), "no reply prompt");
    assert(m.html.includes("mailto:"), "actionable email");
  }
});
Deno.test("contact block rejects hostile links and invalid contacts", () => {
  const c = businessContactEmail({
    business_contact: {
      email: "a<>@example.test",
      phone: "-------",
      website: "https://workloop.uk.evil.test/",
      instagram: "javascript:alert(1)",
      facebook: "https://user@facebook.com/a",
      tiktok: "http://tiktok.com/a",
    },
  });
  assert(c.text.includes("unavailable"), "no invented contacts");
  assert(!c.html.includes("href="), "no unsafe link");
  const escaped = businessContactEmail({
    business_contact: {
      email: 'a"b@example.test',
      instagram: "https://www.instagram.com/example?x=1&y=2",
    },
  });
  assert(!escaped.html.includes('a"b'), "HTML attribute escaped");
  assert(escaped.html.includes("&amp;"), "URL escaped");
});
Deno.test("each prepared exception requires verified details and reference", () => {
  assert(
    new Set(exceptionEmailCases.map((c) => c[0])).size ===
      exceptionEmailCases.length,
    "unique cases",
  );
  for (const [id] of exceptionEmailCases) {
    const m = exceptionEmail(id, payload);
    assert(m.html.includes("&lt;script&gt;"), "safe interpolation");
    assert(!m.html.includes("<script>"), "no injection");
    assert(m.text.includes("EXAMPLE-1"), "reference");
    for (const override of [{ reference: "" }, { details: "" }]) {
      let rejected = false;
      try {
        exceptionEmail(id, { ...payload, ...override });
      } catch {
        rejected = true;
      }
      assert(rejected, "cannot compose unverified placeholder");
    }
  }
});
Deno.test("contact lookup failures prevent provider delivery and record a retry", async () => {
  let sends = 0;
  let finished = false;
  const client = {
    rpc: async (name: string) => {
      if (name === "customer_email_contact") {
        return { data: null, error: { code: "P0001" } };
      }
      if (name === "finish_customer_event_email") finished = true;
      return {
        data: name === "claim_customer_event_emails"
          ? [{
            id: "id",
            lease_token: "lease",
            event: "request_received",
            email: "test@example.test",
            payload,
          }]
          : true,
        error: null,
      };
    },
  };
  const result = await drainCustomerEventEmails({
    client,
    config: { from: "test@example.test", apiKey: "test" },
    fetcher: (async () => {
      sends++;
      return Response.json({ id: "bad" });
    }) as typeof fetch,
  });
  assert(
    sends === 0 && result.failed === 1 && finished,
    "safe retry without incomplete send",
  );
  let rejected = false;
  try {
    await loadBusinessEmailContact(client, "event", "id");
  } catch {
    rejected = true;
  }
  assert(rejected, "lookup error propagated");
});
