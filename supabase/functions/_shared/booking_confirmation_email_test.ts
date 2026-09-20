import {
  bookingConfirmationEmailConfig,
  bookingConfirmationEmailContent,
  drainBookingConfirmationEmails,
  escapeHtml,
  sendBookingConfirmationEmail,
  validBookingConfirmationDrainToken,
} from "./booking_confirmation_email.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("transactional email config fails closed", () => {
  assert(bookingConfirmationEmailConfig(() => undefined) === null, "missing");
  assert(
    bookingConfirmationEmailConfig((name) =>
      name === "RESEND_API_KEY" ? "short" : "Workloop <mail@example.com>"
    ) === null,
    "short key",
  );
});

Deno.test("scheduled drain requires an exact 32+ character secret", () => {
  assert(!validBookingConfirmationDrainToken("a", "a"), "short rejected");
  const configured = "12345678901234567890123456789012";
  assert(
    validBookingConfirmationDrainToken(configured, configured),
    "exact accepted",
  );
  assert(
    !validBookingConfirmationDrainToken(configured, `${configured}x`),
    "long mismatch rejected",
  );
  assert(
    !validBookingConfirmationDrainToken(
      configured,
      "22345678901234567890123456789012",
    ),
    "same-length mismatch rejected",
  );
});

Deno.test("confirmation content escapes public and owner supplied values", () => {
  const content = bookingConfirmationEmailContent({
    payload: {
      customer_name: "<Ada>",
      business_name: "A&B Studio",
      booking_title: 'Cut "and" finish',
      start_time: "2026-08-14T09:30:00Z",
      end_time: "2026-08-14T10:30:00Z",
      timezone: "Europe/London",
      location: "1 <High> Street",
    },
  });
  assert(
    content.plainText.includes("Duration: 1 hour"),
    "duration computed",
  );
  assert(content.html.includes("&lt;Ada&gt;"), "customer escaped");
  assert(content.html.includes("A&amp;B"), "business escaped");
  assert(!content.html.includes("1 <High>"), "location escaped");
  assert(content.html.includes("#f5edd9"), "Workloop paper background");
  assert(content.html.includes("#c3d7e4"), "Workloop blue title strip");
  assert(content.html.includes("BOOKING CONFIRMED"), "specific email purpose");
  assert(escapeHtml("'\"<>&") === "&#39;&quot;&lt;&gt;&amp;", "escape order");
});

Deno.test("Resend call uses stable request idempotency without logging payloads", async () => {
  let key = "";
  const providerId = await sendBookingConfirmationEmail(
    {
      outbox_id: "outbox",
      booking_request_id: "request-123",
      lease_token: "lease",
      recipient_email: "client@example.com",
      payload: { business_name: "Studio" },
      attempt_count: 1,
    },
    { apiKey: "re_1234567890123456", from: "Workloop <mail@example.com>" },
    (_url, init) => {
      key = new Headers(init?.headers).get("Idempotency-Key") ?? "";
      return Promise.resolve(
        new Response(JSON.stringify({ id: "email-123" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );
  assert(key === "booking-request-confirmed/outbox", "stable outbox key");
  assert(providerId === "email-123", "provider id");
});

Deno.test("drain acknowledges provider failure as a retry, not a booking failure", async () => {
  const calls: Array<{ name: string; params?: Record<string, unknown> }> = [];
  const result = await drainBookingConfirmationEmails({
    client: {
      rpc(name, params) {
        calls.push({ name, params });
        if (name === "claim_booking_confirmation_emails") {
          return Promise.resolve({
            data: [{
              outbox_id: "outbox",
              booking_request_id: "request",
              lease_token: "lease",
              recipient_email: "client@example.com",
              payload: {},
              attempt_count: 1,
            }],
            error: null,
          });
        }
        return Promise.resolve({ data: "pending", error: null });
      },
    },
    config: { apiKey: "re_1234567890123456", from: "mail@example.com" },
    fetcher: () =>
      Promise.resolve(new Response("unavailable", { status: 503 })),
  });
  assert(result.pending === 1, "retry remains pending");
  assert(calls.length === 3, "claim, frozen contact lookup and finish");
  assert(calls[2].params?.p_sent === false, "failure acknowledged");
});
