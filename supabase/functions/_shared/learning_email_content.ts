import { withWorkloopOperator, withWorkloopOperatorHtml } from "./workloop_operator_email.ts";
export type LearningStage = "exploring" | "using";
export const LEARNING_CONSENT_VERSION = "workloop-learning-2026-09-v1";
export const LEARNING_CONSENT_TEXT =
  "Email me the Workloop welcome pack and eight practical tips over four weeks. I can unsubscribe at any time.";
export const LEARNING_DAYS = [0, 2, 4, 7, 10, 14, 18, 23, 28];

type Lesson = {
  subject: string;
  heading: string;
  paragraphs: string[];
  steps: string[];
  prompt: string;
  path: string;
  cta: string;
};
export const LESSONS: Lesson[] = [
  {
    subject: "Your Workloop welcome pack",
    heading: "Start with one real working day.",
    paragraphs: [
      "You work for yourself, by yourself. Workloop gives the clients, bookings, tasks and money around your work one calmer home.",
      "You asked for this welcome pack and eight practical tips over the next four weeks. Start small; you do not need to move your whole business today.",
    ],
    steps: [
      "Add one real client.",
      "Add your next booking and check its date, duration and service.",
      "Save one useful detail you will want next time.",
    ],
    prompt: "What is the next real job I want to make easier?",
    path: "/help/welcome",
    cta: "Open your welcome pack",
  },
  {
    subject: "Before your first client: a short check",
    heading: "Give the day a clear starting point.",
    paragraphs: [
      "Open Today before the first job. Look for what is next and anything that needs your attention. A small check is easier to keep than a perfect routine.",
    ],
    steps: [
      "Check your next booking.",
      "Review waiting requests and overdue tasks.",
      "Choose one useful follow-up.",
    ],
    prompt: "What is the one thing I should sort before I start?",
    path: "/help/welcome#today",
    cta: "See the morning check",
  },
  {
    subject: "A useful note for your next visit",
    heading: "Leave future you the right detail.",
    paragraphs: [
      "A good client note is short, factual and relevant to the work. Keep it with the client so you can find it before the next conversation.",
      "Only record information you need and are entitled to hold. Avoid passwords, bank-card details or unnecessary sensitive information.",
    ],
    steps: [
      "Open Clients and choose the client.",
      "Record what was agreed and anything to prepare.",
      "Add a clear next step if one is needed.",
    ],
    prompt: "What would I otherwise need to search for next time?",
    path: "/help/welcome#clients",
    cta: "Keep the client context",
  },
  {
    subject: "Make your next booking easier to trust",
    heading: "Check the details before you confirm.",
    paragraphs: [
      "A clear booking tells you who the work is for, what was agreed and when it fits. Include enough time for preparation and travel when your day needs them.",
      "A customer request still needs your review and confirmation. An exported calendar event is a snapshot, not a promise of live two-way syncing.",
    ],
    steps: [
      "Check the client, service and duration.",
      "Check the time, location and surrounding work.",
      "Confirm only when the details work for you.",
    ],
    prompt: "Have I left enough room to do this job well?",
    path: "/help/welcome#bookings",
    cta: "Review the booking checklist",
  },
  {
    subject: "Turn “must remember” into one action",
    heading: "Make the follow-up specific.",
    paragraphs: [
      "Tasks are easier to start when the next action is clear. “Clients” asks you to think again. “Ask Jo whether Tuesday works for the next visit” tells you what to do.",
    ],
    steps: [
      "Open Work, then Tasks.",
      "Write the action and the person it concerns.",
      "Choose a sensible due date and link the context where available.",
    ],
    prompt: "Who, what and when?",
    path: "/help/welcome#work",
    cta: "Make the next step clear",
  },
  {
    subject: "A full diary is not the same as being paid",
    heading: "Keep the money record close to the work.",
    paragraphs: [
      "Check work completed and money received as two separate things. Money helps you keep track of what was made, spent and is still owed.",
      "Only mark a payment received after checking it actually arrived. Workloop is not a replacement for your accountant or full accounting records. Card collection depends on the business's payment setup and available device features.",
    ],
    steps: [
      "Review the record linked to the work.",
      "Check the amount and payment status.",
      "Record the real payment or leave an appropriate next step.",
    ],
    prompt: "What has actually arrived, and what is still waiting?",
    path: "/help/welcome#money",
    cta: "Use the money check",
  },
  {
    subject: "Check your booking page as a customer",
    heading: "Give people a clear way to ask.",
    paragraphs: [
      "Your public booking page should help a customer understand what you offer and make a request. Check the page after changing services or normal hours.",
    ],
    steps: [
      "Open Business and review your booking page.",
      "Check services, prices and working hours.",
      "Open the public link and read it as a new customer would.",
    ],
    prompt: "Would someone new know what to request?",
    path: "/help/welcome#business",
    cta: "Check the customer-facing details",
  },
  {
    subject: "A small reset for next week",
    heading: "Leave yourself an easier restart.",
    paragraphs: [
      "You do not need an empty task list to finish the week. Decide what each open item needs next and leave a clear place to restart.",
    ],
    steps: [
      "Review unfinished tasks and unanswered requests.",
      "Check money records against what really happened.",
      "Look at the next seven days and choose the first useful action.",
    ],
    prompt: "What can I decide now so Monday takes less thinking?",
    path: "/help/welcome#weekly-reset",
    cta: "Save the weekly reset",
  },
  {
    subject: "What has made your working day easier?",
    heading: "Keep the habits that earn their place.",
    paragraphs: [
      "That is the last email in this welcome series. The aim was a few useful habits, not another thing to keep up with.",
      "Keep what helps your real working day. If something in Workloop is confusing, tell us what you were trying to do and where you got stuck. Please leave private client details out of feedback.",
    ],
    steps: [
      "Choose the daily check you want to keep.",
      "Remove or simplify a routine that is not helping.",
      "Share one specific piece of feedback if you would like to.",
    ],
    prompt: "What is easier now, and what still takes too much effort?",
    path: "/help/welcome#feedback",
    cta: "Find help and share feedback",
  },
];

export function escapeEmail(value: string) {
  return value.replace(
    /[&<>"']/g,
    (
      c,
    ) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );
}
export function emailFrame(
  input: { heading: string; preview: string; body: string; footer: string },
) {
  return withWorkloopOperatorHtml(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"></head><body style="margin:0;background:#f5edd9;color:#443c32;font-family:Arial,sans-serif"><div style="display:none;max-height:0;overflow:hidden">${
    escapeEmail(input.preview)
  }</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:24px 12px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fbf7ed;border:1px solid #8d8070;border-radius:8px"><tr><td style="padding:25px 28px;background:#c3d7e4;border-bottom:1px solid #8d8070;font-size:27px;font-weight:bold">workloop</td></tr><tr><td style="padding:28px"><p style="font-family:monospace;font-size:12px;letter-spacing:1px">A NOTE FOR THE BUSINESS OF ONE</p><h1 style="font-size:30px;line-height:1.16;margin:20px 0">${
    escapeEmail(input.heading)
  }</h1>${input.body}</td></tr><tr><td style="padding:22px 28px;border-top:1px solid #8d8070;font-size:13px;line-height:1.6;color:#665c50">${input.footer}</td></tr></table></td></tr></table></body></html>`);
}
function button(url: string, label: string) {
  return `<p style="margin:25px 0"><a href="${
    escapeEmail(url)
  }" style="display:inline-block;padding:15px 20px;border:1px solid #443c32;border-radius:6px;background:#91b4c8;color:#443c32;text-decoration:none;font-weight:bold">${
    escapeEmail(label)
  }</a></p>`;
}
export function learningEmail(
  input: { step: number; stage: LearningStage; unsubscribeUrl: string },
) {
  const lesson = LESSONS[input.step];
  if (!lesson) throw new Error("unknown_learning_step");
  const intro = input.stage === "exploring"
    ? "Still exploring Workloop? You can use these checks with your current tools. See current availability on the website; this series does not grant app access."
    : "Already using Workloop? Try this with one real client or job. Menu availability can depend on your app version and setup.";
  const url = `https://workloop.uk${
    lesson.path.split("#")[0]
  }?utm_source=resend&utm_medium=email&utm_campaign=welcome_series&utm_content=lesson_${input.step}${
    lesson.path.includes("#") ? "#" + lesson.path.split("#")[1] : ""
  }`;
  const text = `${lesson.heading}\n\n${intro}\n\n${
    lesson.paragraphs.join("\n\n")
  }\n\n${
    lesson.steps.map((s, i) => `${i + 1}. ${s}`).join("\n")
  }\n\nA prompt for today: ${lesson.prompt}\n\n${lesson.cta}: ${url}\n\nHelp: support@workloop.uk\nYou requested the Workloop welcome series. Unsubscribe: ${input.unsubscribeUrl}`;
  const body = `<p style="font-size:14px;line-height:1.6;color:#665c50">${
    escapeEmail(intro)
  }</p>${
    lesson.paragraphs.map((p) =>
      `<p style="font-size:17px;line-height:1.65">${escapeEmail(p)}</p>`
    ).join("")
  }<ol style="font-size:17px;line-height:1.65;padding-left:24px">${
    lesson.steps.map((s) =>
      `<li style="margin:0 0 10px">${escapeEmail(s)}</li>`
    ).join("")
  }</ol><div style="background:#f0d18b;border:1px solid #8d8070;border-radius:6px;padding:18px;font-size:17px;line-height:1.5"><strong>A prompt for today</strong><br>${
    escapeEmail(lesson.prompt)
  }</div>${button(url, lesson.cta)}`;
  return withWorkloopOperator({
    subject: lesson.subject,
    text,
    html: emailFrame({
      heading: lesson.heading,
      preview: lesson.subject,
      body,
      footer: `You requested this nine-part Workloop welcome series. <a href="${
        escapeEmail(input.unsubscribeUrl)
      }" style="color:#286280">Unsubscribe</a> at any time.<br>Questions? <a href="mailto:support@workloop.uk" style="color:#286280">Contact Workloop</a>.`,
    }),
  });
}
export function confirmationEmail(confirmUrl: string) {
  const heading = "Would you like the Workloop welcome series?";
  return withWorkloopOperator({
    subject: "Confirm your Workloop welcome series",
    text:
      `${heading}\n\n${LEARNING_CONSENT_TEXT}\n\nConfirm here within 24 hours: ${confirmUrl}\n\nIf you did not request this, ignore this email. You will not be subscribed.\nWorkloop | support@workloop.uk`,
    html: emailFrame({
      heading,
      preview: "One click to confirm your optional email series.",
      body: `<p style="font-size:17px;line-height:1.65">${
        escapeEmail(LEARNING_CONSENT_TEXT)
      }</p>${
        button(confirmUrl, "Confirm my email series")
      }<p style="font-size:15px;line-height:1.6">This link expires in 24 hours. If you did not request this, ignore it. You will not be subscribed.</p>`,
      footer:
        "Workloop · For the business of one.<br>Help: support@workloop.uk",
    }),
  });
}
