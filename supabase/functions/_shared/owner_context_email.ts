import { withWorkloopOperator } from "./workloop_operator_email.ts";
import { accountJourneyEmail } from "./account_journey_email.ts";
import { emailFrame, escapeEmail } from "./learning_email_content.ts";
export function ownerContextEmail(
  input: {
    step: number;
    unsubscribeUrl: string;
    context: Record<string, unknown>;
  },
) {
  const setup = String(input.context.setup_step ?? "");
  const steps: Record<
    string,
    { title: string; text: string; steps: string[] }
  > = {
    finish_workspace: {
      title: "Finish your business setup, one step at a time",
      text:
        "Your business workspace is not set up yet. Open Workloop and continue the setup screens. Start with the details you know; you can refine the rest later.",
      steps: [
        "Confirm your business name.",
        "Choose the service and working hours that match your real work.",
        "Finish setup to open your workspace.",
      ],
    },
    add_service: {
      title: "Give your first service a clear name",
      text:
        "Your workspace is ready, but it does not yet have an active service. A clear service name, realistic duration and price give your bookings a useful starting point.",
      steps: [
        "Open Business and find Services.",
        "Add one service you actually offer.",
        "Check its duration and price before sharing your booking page.",
      ],
    },
    add_client: {
      title: "Start with one real client",
      text:
        "You have a service ready, but no clients saved in this workspace yet. You do not need to move your entire address book to try Workloop.",
      steps: [
        "Open Clients.",
        "Add one person you are genuinely working with.",
        "Save only the contact details and work information you need.",
      ],
    },
    add_booking: {
      title: "Put your next real job in Workloop",
      text:
        "Your service and client records are in place. The next useful step is a booking, so Today can help you see what comes next.",
      steps: [
        "Choose a client and service.",
        "Add the agreed date, time and location.",
        "Check the booking in Today or your calendar.",
      ],
    },
  };
  if ([10, 12].includes(input.step) && steps[setup]) {
    const tip = steps[setup];
    const subject = `A small setup step: ${tip.title}`;
    const footer =
      `You receive Workloop getting-started help and tips. <a href="${
        escapeEmail(input.unsubscribeUrl)
      }">Unsubscribe</a> any time. Essential account messages are unaffected. Contact support@workloop.uk directly for help.`;
    return withWorkloopOperator({
      subject,
      text: `${tip.title}\n\n${tip.text}\n\n${
        tip.steps.join("\n")
      }\n\nOpen Workloop to continue, or read https://workloop.uk/help/welcome\nContact: support@workloop.uk\nUnsubscribe: ${input.unsubscribeUrl}`,
      html: emailFrame({
        heading: tip.title,
        preview: subject,
        body: `<p style="font-size:17px;line-height:1.65">${
          escapeEmail(tip.text)
        }</p><ol style="font-size:17px;line-height:1.65">${
          tip.steps.map((s) => `<li>${escapeEmail(s)}</li>`).join("")
        }</ol><p>Open Workloop to continue, or <a href="https://workloop.uk/help/welcome">read the welcome guide</a>.</p>`,
        footer,
      }),
    });
  }
  const content = accountJourneyEmail(input);
  const summary = input.context.summary as Record<string, unknown> | undefined;
  if (input.step < 1000 || !summary) return content;
  const count = (key: string) =>
    Number.isFinite(Number(summary[key]))
      ? Math.max(0, Math.floor(Number(summary[key])))
      : 0;
  const business = String(input.context.business_name ?? "your business");
  const entries = [
    ["Completed bookings in the last seven days", count("completed_bookings")],
    ["Bookings in the next seven days", count("upcoming_bookings")],
    ["Requests waiting for a response", count("waiting_requests")],
    ["Overdue tasks", count("overdue_tasks")],
  ];
  const text =
    `Your weekly check for ${business}\nFigures reflect your saved Workloop records when this email was prepared.\n${
      entries.map(([label, n]) => `${label}: ${n}`).join("\n")
    }\n\n`;
  const html =
    `<div style="background:#c3d7e4;border:1px solid #8d8070;border-radius:6px;padding:20px;margin-bottom:24px"><h2 style="font-size:22px;margin-top:0">Your weekly check for ${
      escapeEmail(business)
    }</h2>${
      entries.map(([label, n]) =>
        `<p style="line-height:1.5"><strong>${n}</strong> ${
          escapeEmail(String(label))
        }</p>`
      ).join("")
    }<p style="font-size:12px">A snapshot of your saved Workloop records when this email was prepared.</p></div>`;
  return {
    ...content,
    subject: `Your Workloop weekly check — ${business}`,
    text: text + content.text,
    html: content.html.replace("<h1 style=", html + "<h1 style="),
  };
}
