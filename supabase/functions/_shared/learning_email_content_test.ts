import {
  confirmationEmail,
  LEARNING_DAYS,
  learningEmail,
} from "./learning_email_content.ts";
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
Deno.test("learning emails escape tokens and provide a finite consented series", () => {
  assert(
    LEARNING_DAYS.join(",") === "0,2,4,7,10,14,18,23,28",
    "spaced schedule",
  );
  for (const stage of ["exploring", "using"] as const) {
    for (let step = 0; step < 9; step++) {
      const email = learningEmail({
        step,
        stage,
        unsubscribeUrl: 'https://example.com/?a=1&b="test"',
      });
      assert(
        email.html.includes("a=1&amp;b=&quot;test&quot;"),
        "escape unsubscribe link",
      );
      assert(email.html.includes("Unsubscribe"), "every lesson can be stopped");
      assert(
        email.text.includes("workloop.uk/help/welcome"),
        "real guide destination",
      );
      assert(email.html.length < 25000, "email stays compact");
    }
  }
});
Deno.test("learning confirmation states scope and expires", () => {
  const email = confirmationEmail("https://example.com/confirm");
  assert(email.text.includes("24 hours"), "expiry");
  assert(email.text.includes("eight practical tips"), "scope");
  assert(
    email.text.includes("will not be subscribed"),
    "no unsolicited enrolment",
  );
});
