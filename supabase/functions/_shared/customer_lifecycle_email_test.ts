import {
  customerEventEmail,
  drainCustomerEventEmails,
} from "./customer_event_email.ts";
import { ownerContextEmail } from "./owner_context_email.ts";
const assert = (value: unknown, message: string) => {
  if (!value) throw Error(message);
};
const sample = {
  business_name: "A & B",
  customer_name: "<script>alert(1)</script>",
  booking_title: "Clean",
  start_time: "2026-09-10T09:00:00Z",
  end_time: "2026-09-10T10:00:00Z",
  timezone: "Europe/London",
  price: 45,
  notes: "PRIVATE",
  invoice_number: "PAY-1",
  amount_minor: 4500,
  checkout_url: "https://checkout.stripe.com/c/pay/example",
};
Deno.test("customer lifecycle templates escape data and distinguish request, change, cancellation and payment", () => {
  for (
    const event of [
      "request_received",
      "request_declined",
      "booking_changed",
      "booking_cancelled",
      "payment_request",
    ] as const
  ) {
    const c = customerEventEmail(event, sample);
    assert(c.html.includes("&lt;script&gt;"), "escaped customer");
    assert(!c.html.includes("PRIVATE"), "no private notes");
    assert(c.text.length > 100, "text version");
  }
  assert(
    customerEventEmail("request_received", sample).text.includes(
      "not confirmed yet",
    ),
    "pending is explicit",
  );
  assert(
    customerEventEmail("booking_changed", sample).text.includes("10:00"),
    "business timezone",
  );
  assert(
    customerEventEmail("booking_cancelled", sample).text.includes(
      "does not itself confirm a refund",
    ),
    "no invented refund",
  );
  assert(
    customerEventEmail("payment_request", sample).text.includes("£45.00"),
    "exact amount",
  );
});
Deno.test("payment email rejects unsafe destinations and amounts", () => {
  for (
    const checkout_url of [
      "https://checkout.stripe.com.evil.test/pay",
      "javascript:alert(1)",
      "http://checkout.stripe.com/c/pay",
      "https://user@checkout.stripe.com/pay",
    ]
  ) {
    let threw = false;
    try {
      customerEventEmail("payment_request", { ...sample, checkout_url });
    } catch {
      threw = true;
    }
    assert(threw, "unsafe checkout URL rejected");
  }
  for (const amount_minor of [0, -1, 1.2, NaN]) {
    let threw = false;
    try {
      customerEventEmail("payment_request", { ...sample, amount_minor });
    } catch {
      threw = true;
    }
    assert(threw, "invalid amount rejected");
  }
});
Deno.test("setup variants are conditional and retain unsubscribe", () => {
  for (
    const setup_step of [
      "finish_workspace",
      "add_service",
      "add_client",
      "add_booking",
    ]
  ) {
    const c = ownerContextEmail({
      step: 10,
      unsubscribeUrl: "https://example.test/stop",
      context: { setup_step },
    });
    assert(
      c.subject.startsWith("A small setup step:"),
      "specific setup subject",
    );
    assert(
      c.html.includes("https://example.test/stop"),
      "unsubscribe preserved",
    );
  }
  const c = ownerContextEmail({
    step: 10,
    unsubscribeUrl: "https://example.test/stop",
    context: {},
  });
  assert(
    c.subject === "Your Workloop welcome pack",
    "normal journey for completed setup",
  );
});
Deno.test("weekly summary combines aggregate counts with weekly advice", () => {
  const c = ownerContextEmail({
    step: 1005,
    unsubscribeUrl: "https://example.test/stop",
    context: {
      business_name: "<Example>",
      summary: {
        completed_bookings: 7,
        upcoming_bookings: 4,
        waiting_requests: 2,
        overdue_tasks: 1,
      },
    },
  });
  assert(c.subject.includes("weekly check"), "summary subject");
  assert(
    c.text.includes("Completed bookings in the last seven days: 7"),
    "actual metrics",
  );
  assert(c.html.includes("&lt;Example&gt;"), "escape business");
  assert(c.text.includes("A prompt for today"), "weekly advice retained");
  assert(c.html.includes("https://example.test/stop"), "unsubscribe retained");
});
Deno.test("revoked lifecycle events never reach provider", async () => {
  let calls = 0;
  const client = {
    rpc: async (name: string) => ({
      data: name === "claim_customer_event_emails"
        ? [{ id: "q", lease_token: "lease" }]
        : false,
      error: null,
    }),
  };
  const result = await drainCustomerEventEmails({
    client,
    config: { apiKey: "test", from: "test@example.test" },
    fetcher: (async () => {
      calls++;
      throw Error("must not send");
    }) as typeof fetch,
  });
  assert(calls === 0 && result.skipped === 1, "cancelled event blocked");
});
Deno.test("customer email retry preserves idempotency and records provider failure", async () => {
  const calls: Array<
    { name: string; args: Record<string, unknown> | undefined }
  > = [];
  let key = "";
  const client = {
    rpc: async (name: string, args?: Record<string, unknown>) => {
      calls.push({ name, args });
      return {
        data: name === "claim_customer_event_emails"
          ? [{
            id: "q1",
            lease_token: "lease",
            event: "request_received",
            email: "customer@example.test",
            payload: sample,
          }]
          : true,
        error: null,
      };
    },
  };
  const result = await drainCustomerEventEmails({
    client,
    config: { apiKey: "test", from: "test@example.test" },
    fetcher: (async (_url, init) => {
      key = new Headers(init?.headers).get("Idempotency-Key") ?? "";
      return new Response("unavailable", { status: 503 });
    }) as typeof fetch,
  });
  assert(key === "customer-event/q1", "stable idempotency");
  assert(result.failed === 1, "failure reported");
  assert(calls.at(-1)?.args?.p_provider_id === null, "not marked sent");
});

Deno.test("customer emails give direct contact details without reply prompts", async () => {
  for (const email of ["owner@example.test", null]) {
    const business_contact = email ? { email, phone: "07700 900123" } : {};
    const c = customerEventEmail("request_declined", {
      ...sample,
      business_contact,
    });
    assert(!/repl(y|ies)/i.test(c.text), "no reply instruction");
    assert(
      c.text.includes(email ?? "contact details are unavailable"),
      "honest contact details",
    );
    let destination = "";
    const client = {
      rpc: async (name: string) => ({
        data: name === "claim_customer_event_emails"
          ? [{
            id: "q2",
            lease_token: "lease",
            event: "request_declined",
            email: "customer@example.test",
            payload: sample,
          }]
          : name === "customer_email_contact"
          ? business_contact
          : true,
        error: null,
      }),
    };
    await drainCustomerEventEmails({
      client,
      config: { apiKey: "test", from: "test@example.test" },
      fetcher: (async (_url, init) => {
        destination = JSON.parse(String(init?.body)).reply_to;
        return Response.json({ id: "provider" });
      }) as typeof fetch,
    });
    assert(
      destination === (email ?? "support@workloop.uk"),
      "header still handles accidental replies",
    );
  }
});
