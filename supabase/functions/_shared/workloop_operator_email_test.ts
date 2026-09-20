import { accountWelcomeEmailContent } from "./account_welcome_email.ts";
import { accountDeletionEmailContent } from "./account_deletion_email.ts";
import { waitlistWelcomeEmailContent } from "./waitlist_welcome_email.ts";
import { bookingConfirmationEmailContent } from "./booking_confirmation_email.ts";
import { bookingReminderEmail } from "./booking_reminder_email.ts";
import {
  type CustomerEvent,
  customerEventEmail,
} from "./customer_event_email.ts";
import { accountJourneyEmail } from "./account_journey_email.ts";
import { ownerContextEmail } from "./owner_context_email.ts";
import { exceptionEmail, exceptionEmailCases } from "./exception_email.ts";
import { operationalAlertEmailContent } from "./workloop_automations.ts";
import {
  confirmationEmail,
  emailFrame,
  learningEmail,
} from "./learning_email_content.ts";
import {
  withWorkloopOperator,
  withWorkloopOperatorHtml,
  WORKLOOP_OPERATOR_HTML,
  WORKLOOP_OPERATOR_TEXT,
} from "./workloop_operator_email.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const disclosure = "Workloop is a trading name of Haani Enterprise Limited.";
const unsubscribeUrl = "https://example.test/unsubscribe?token=fixture";
const payload = {
  business_name: "Alex Services",
  customer_name: "Jamie <Sample>",
  business_contact: { email: "owner@example.test", phone: "+44 7700 900123" },
  booking_title: "Window clean",
  start_time: "2026-09-10T09:30:00Z",
  end_time: "2026-09-10T10:15:00Z",
  timezone: "Europe/London",
  price: 45,
  invoice_number: "PAY-001",
  amount_minor: 4500,
  checkout_url: "https://checkout.stripe.com/c/pay/example",
};
type Email = {
  subject: string;
  html: string;
  text?: string;
  plainText?: string;
};

Deno.test("every owner, customer, marketing, exception and operations variant identifies the operator in both formats", () => {
  const emails: Email[] = [
    accountWelcomeEmailContent(),
    accountDeletionEmailContent("deletion_requested"),
    accountDeletionEmailContent("account_deleted"),
    waitlistWelcomeEmailContent(),
    bookingConfirmationEmailContent({ payload }),
    confirmationEmail("https://example.test/confirm"),
    ...[1440, 120, 60].map((minutes_before) =>
      bookingReminderEmail({ ...payload, minutes_before }, unsubscribeUrl)
    ),
    ...([
      "request_received",
      "request_declined",
      "booking_changed",
      "booking_cancelled",
      "payment_request",
    ] as CustomerEvent[]).map((event) => customerEventEmail(event, payload)),
    ...["using", "exploring"].flatMap((stage) =>
      Array.from(
        { length: 9 },
        (_, step) =>
          learningEmail({
            step,
            stage: stage as "using" | "exploring",
            unsubscribeUrl,
          }),
      )
    ),
    ...[
      ...Array.from({ length: 9 }, (_, n) => n + 10),
      ...Array.from({ length: 12 }, (_, n) => n + 1005),
      100,
      101,
      102,
    ].map((step) => accountJourneyEmail({ step, unsubscribeUrl })),
    ...["finish_workspace", "add_service", "add_client", "add_booking"].map((
      setup_step,
    ) =>
      ownerContextEmail({ step: 10, unsubscribeUrl, context: { setup_step } })
    ),
    ownerContextEmail({
      step: 1005,
      unsubscribeUrl,
      context: {
        business_name: "Alex Services",
        summary: { completed_bookings: 3 },
      },
    }),
    ...exceptionEmailCases.map(([id]) =>
      exceptionEmail(id, {
        ...payload,
        reference: "QA-001",
        details: "Verified sample outcome only.",
      })
    ),
    ...["warning", "critical"].map((severity) =>
      operationalAlertEmailContent({
        alert_id: "sample",
        alert_key: "sample-queue-health",
        category: "email_delivery",
        severity: severity as "warning" | "critical",
        message: "Synthetic monitoring example.",
        first_seen_at: "2026-09-06T12:00:00Z",
      })
    ),
  ];
  assert(emails.length === 89, "all 89 non-Auth variants are covered");
  for (const email of emails) {
    const text = email.text ?? email.plainText ?? "";
    assert(
      email.html.split(disclosure).length === 2,
      `${email.subject}: one HTML operator disclosure`,
    );
    assert(
      text.split(disclosure).length === 2,
      `${email.subject}: one plain-text operator disclosure`,
    );
    for (
      const value of [
        "15758586",
        "England and Wales",
        "35 Well Lane, Batley, WF17 5HQ, England",
        "support@workloop.uk",
      ]
    ) {
      assert(
        email.html.includes(value) && text.includes(value),
        `${email.subject}: complete legal/contact identity`,
      );
    }
    assert(
      !email.html.includes("57 Tanfield") && !text.includes("57 Tanfield"),
      "unregistered proposed address is never substituted",
    );
    assert(
      !email.subject.includes("Haani"),
      "Workloop and tenant subject branding is preserved",
    );
  }
});

Deno.test("customer merchant contact and unsubscribe routes remain separate from platform identity", () => {
  const email = bookingReminderEmail(
    { ...payload, minutes_before: 60 },
    unsubscribeUrl,
  );
  assert(
    email.subject.includes("Alex Services"),
    "subject identifies the booked business",
  );
  assert(
    email.text.includes("Sent by Workloop on behalf of Alex Services."),
    "tenant remains the service business",
  );
  assert(
    email.html.includes("owner%40example.test") &&
      email.text.includes("owner@example.test"),
    "direct business contact preserved",
  );
  assert(
    email.html.includes("+447700900123"),
    "direct business phone preserved",
  );
  assert(
    email.text.includes(unsubscribeUrl) && email.html.includes(unsubscribeUrl),
    "original customer stop link preserved",
  );
  assert(
    email.html.indexOf("Contact the business directly") <
      email.html.indexOf(disclosure),
    "business action remains ahead of platform footer",
  );
  assert(
    !email.html.includes("Jamie <Sample>"),
    "existing customer escaping preserved",
  );
});

Deno.test("nested renderer composition adds a footer once without changing the original content or headers", () => {
  const original = {
    subject: "Workloop",
    html: "<html><body><p>Original content</p></body></html>",
    text: "Original content",
    reply_to: "owner@example.test",
  };
  const wrapped = withWorkloopOperator(original);
  const twice = withWorkloopOperator(wrapped);
  assert(
    wrapped.html === twice.html && wrapped.text === twice.text,
    "idempotent composition",
  );
  assert(
    wrapped.reply_to === original.reply_to &&
      wrapped.subject === original.subject,
    "unrelated fields preserved",
  );
  assert(
    original.text === "Original content" && !original.html.includes(disclosure),
    "original content not mutated",
  );
  assert(
    wrapped.html.replace(WORKLOOP_OPERATOR_HTML, "") === original.html,
    "HTML body unchanged outside footer",
  );
  assert(
    wrapped.text === original.text + "\n\n" + WORKLOOP_OPERATOR_TEXT,
    "plaintext only appends operator details",
  );
  const framed = emailFrame({
    heading: "Status",
    preview: "Status",
    body: "<p>Saved</p>",
    footer: "Existing footer",
  });
  assert(
    framed.includes(WORKLOOP_OPERATOR_HTML),
    "direct frame callers are covered too",
  );
  let failed = false;
  try {
    withWorkloopOperatorHtml("<p>No body</p>");
  } catch {
    failed = true;
  }
  assert(failed, "malformed email cannot silently omit the disclosure");
});

Deno.test("all 13 Auth templates retain security variables and the synchronised operator footer", async () => {
  const variables: Record<string, string[]> = {
    confirmation: ["ConfirmationURL"],
    email_change: ["ConfirmationURL", "NewEmail"],
    email_changed: ["Email", "OldEmail"],
    identity_linked: ["Provider"],
    identity_unlinked: ["Provider"],
    invite: ["ConfirmationURL", "Email"],
    magic_link: ["ConfirmationURL"],
    mfa_enrolled: ["FactorType"],
    mfa_unenrolled: ["FactorType"],
    password_changed: [],
    phone_changed: ["OldPhone", "Phone"],
    reauthentication: ["Token"],
    recovery: ["ConfirmationURL"],
  };
  let count = 0;
  for await (
    const file of Deno.readDir(new URL("../../templates/", import.meta.url))
  ) {
    if (!file.name.endsWith(".html")) continue;
    count++;
    const html = await Deno.readTextFile(
      new URL("../../templates/" + file.name, import.meta.url),
    );
    assert(
      html.includes(WORKLOOP_OPERATOR_HTML),
      `${file.name}: exact current legal footer`,
    );
    assert(
      html.split(disclosure).length === 2,
      `${file.name}: no duplicate disclosure`,
    );
    const actual = [
      ...new Set(
        [...html.matchAll(/{{\s*\.([A-Za-z]+)\s*}}/g)].map((m) => m[1]),
      ),
    ].sort();
    const expected = variables[file.name.replace(".html", "")];
    assert(
      expected && actual.join(",") === expected.sort().join(","),
      `${file.name}: unchanged security template variables`,
    );
    assert(
      html.indexOf(WORKLOOP_OPERATOR_HTML) < html.indexOf("</body>"),
      `${file.name}: footer inside body`,
    );
  }
  assert(count === 13, "every configured Auth/security template reviewed");
});
