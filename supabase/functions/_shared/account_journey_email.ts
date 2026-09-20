import { withWorkloopOperator } from "./workloop_operator_email.ts";
import { emailFrame, escapeEmail, LESSONS } from "./learning_email_content.ts";

type Advice = {
  subject: string;
  heading: string;
  paragraphs: string[];
  steps: string[];
  prompt: string;
  cta?: string;
  path?: string;
};
export const BUSINESS_ADVICE: Advice[] = [
  {
    subject: "A five-minute reset for your business of one",
    heading: "Give the week a clear starting point.",
    paragraphs: [
      "A useful plan begins with the work already promised. Before filling the gaps, check what your current clients need from you.",
    ],
    steps: [
      "Review the next seven days in Workloop.",
      "Check waiting requests, open tasks and money still owed.",
      "Choose one follow-up that will make the week easier.",
    ],
    prompt: "What can I settle today instead of carrying it all week?",
  },
  {
    subject: "Make the next visit easier to arrange",
    heading: "Leave a clear next step.",
    paragraphs: [
      "When a job ends, decide what happens next. For repeat services, ask whether the customer would like another visit and agree a sensible time.",
    ],
    steps: [
      "Confirm what was completed.",
      "Record the next step with the client.",
      "Create a booking only once the timing is agreed.",
    ],
    prompt: "Which client needs a clear next step?",
  },
  {
    subject: "Your booking page deserves a quick check",
    heading: "Make it easy to understand what you do.",
    paragraphs: [
      "Read your public page as someone who has never met you. Clear services, realistic durations and current prices help people make a useful request.",
    ],
    steps: [
      "Review your service names and descriptions.",
      "Check durations and working hours.",
      "Open the public booking link and check it on your phone.",
    ],
    prompt: "Would a new customer know which service to choose?",
    path: "/help/welcome#business",
  },
  {
    subject: "Know someone who works for themselves?",
    heading: "Pass on a calmer way to run the day.",
    paragraphs: [
      "If Workloop is helping, you might know a friend or family member who runs a business on their own. Share the website with someone who would find it useful. There is no reward or obligation attached.",
    ],
    steps: [
      "Think of one person whose working day looks like yours.",
      "Tell them which Workloop habit has helped you.",
      "Share workloop.uk so they can check current availability.",
    ],
    prompt: "Who would appreciate having their work in one place?",
    cta: "Share the Workloop website",
    path: "/",
  },
  {
    subject: "Leave room between the jobs",
    heading: "Plan the whole job, including the gaps.",
    paragraphs: [
      "Travel, preparation and packing away take real time. A diary that looks full can still be unrealistic if those parts are missing.",
    ],
    steps: [
      "Look at the bookings either side of a new request.",
      "Allow time for travel and preparation.",
      "Check the day before confirming another booking.",
    ],
    prompt: "Where does my diary assume I can be in two places at once?",
  },
  {
    subject: "A better client note is usually a shorter one",
    heading: "Keep the detail you will actually use.",
    paragraphs: [
      "A useful note tells future you what was agreed and what to prepare. Keep it factual and relevant; leave out passwords, payment-card details and unnecessary sensitive information.",
    ],
    steps: [
      "Open a client you will see again soon.",
      "Check the latest agreement and useful preferences.",
      "Turn an unfinished promise into a dated task.",
    ],
    prompt: "What will save me searching through messages next time?",
  },
  {
    subject: "Give your follow-ups a finish line",
    heading: "One person. One action. One date.",
    paragraphs: [
      "“Sort marketing” is hard to finish. “Update my booking-page service description on Friday” gives you a clear next action.",
    ],
    steps: [
      "Choose one vague task.",
      "Rewrite it as an action you can finish.",
      "Add a realistic date and the relevant client or booking.",
    ],
    prompt: "What would completing this task actually look like?",
  },
  {
    subject: "Make your next customer conversation clearer",
    heading: "Confirm the details before the work.",
    paragraphs: [
      "A short, clear agreement helps both sides prepare. Use the booking record to check the service, timing, location and agreed price before you start.",
    ],
    steps: [
      "Check the customer and service.",
      "Confirm anything that has changed.",
      "Save relevant agreed details with the booking.",
    ],
    prompt: "What could be misunderstood if I leave it unstated?",
  },
  {
    subject: "Keep business admin small enough to finish",
    heading: "Choose a short closing routine.",
    paragraphs: [
      "A ten-minute check can be more useful than postponing everything for a perfect admin day. Give yourself a small stopping point.",
    ],
    steps: [
      "Mark completed work accurately.",
      "Check payment records against money actually received.",
      "Leave a task for anything that needs follow-up.",
    ],
    prompt: "What are the three things I want settled before I stop?",
  },
  {
    subject: "Help a customer recommend your work",
    heading: "Make the next introduction easy.",
    paragraphs: [
      "When a customer tells you they are happy with the work, thank them. If it feels appropriate, let them know they can share your public booking page with someone looking for the same service.",
    ],
    steps: [
      "Check your public page is current.",
      "Share the link in an existing conversation where it is welcome.",
      "Let the customer decide whether to pass it on.",
    ],
    prompt: "Is my booking page ready for someone new?",
  },
  {
    subject: "A practical Workloop habit to keep",
    heading: "Start in Today, then follow the work.",
    paragraphs: [
      "Start with what is next and what needs attention. From there, use the client, booking, task and money records to keep each job connected.",
    ],
    steps: [
      "Check Today before your first job.",
      "Open the next booking and its client details.",
      "Finish one attention item before adding another system.",
    ],
    prompt: "Which part of my day could use less switching between apps?",
  },
  {
    subject: "What would make next month easier?",
    heading: "Keep the habits that earn their place.",
    paragraphs: [
      "You do not need more admin to run a better business. Keep the small routines that help you remember less, follow through and trust your records.",
    ],
    steps: [
      "Choose one routine that helped this month.",
      "Simplify one that created extra work.",
      "Contact support@workloop.uk with one specific Workloop question if you need help.",
    ],
    prompt: "What do I want to spend less time chasing next month?",
  },
];
export const INACTIVITY_ADVICE: Advice[] = [
  {
    subject: "Pick up Workloop with one small step",
    heading: "Start with your next real job.",
    paragraphs: [
      "It has been a little while since you used Workloop. If your routine changed, you can restart with one client and one booking. There is no need to catch up on everything at once.",
    ],
    steps: [
      "Open Today and check what is still relevant.",
      "Review your next booking.",
      "Choose one useful follow-up.",
    ],
    prompt: "What is the next job I want to make easier?",
  },
  {
    subject: "Would a simpler setup help?",
    heading: "Use the parts that help your working day.",
    paragraphs: [
      "If Workloop felt like too much to set up, try starting with just your next client and booking. Add the rest when it earns its place. Contact support@workloop.uk if something is getting in the way.",
    ],
    steps: [
      "Keep one accurate client record.",
      "Add one real upcoming booking.",
      "Tell us where you got stuck, without including private customer details.",
    ],
    prompt: "What would make getting started feel easier?",
  },
  {
    subject: "We will give your inbox some space",
    heading: "Come back when it suits your business.",
    paragraphs: [
      "We have not seen recent app activity, so we will pause regular tips and reminders to return after this message. If you return to Workloop, useful tips can resume. You can unsubscribe below at any time.",
    ],
    steps: [
      "Keep the welcome guide for a future restart.",
      "Contact support@workloop.uk if you need help with your account.",
      "Unsubscribe if you no longer want Workloop tips and updates.",
    ],
    prompt: "What would I want ready before trying again?",
    cta: "Keep the welcome guide",
  },
];
export function accountJourneyEmail(
  input: { step: number; unsubscribeUrl: string },
) {
  let advice: Advice;
  if (input.step >= 10 && input.step <= 18) {
    const lesson = LESSONS[input.step - 10];
    advice = { ...lesson, paragraphs: [...lesson.paragraphs] };
    if (input.step === 10) {
      advice.paragraphs[1] =
        "Here is your welcome pack and a small first step. Over the next month we will help you find a useful working routine, followed by practical tips and occasional Workloop updates.";
    }
    if (input.step === 18) {
      advice.paragraphs[0] =
        "You have reached the end of the getting-started journey. From here, we will send a useful business tip about once a week while you are using Workloop.";
    }
  } else if (input.step >= 1000) {
    advice = BUSINESS_ADVICE[
      (input.step - 1005 + BUSINESS_ADVICE.length) % BUSINESS_ADVICE.length
    ];
  } else if (input.step >= 100 && input.step <= 102) {
    advice = INACTIVITY_ADVICE[input.step - 100];
  } else throw new Error("unknown_account_email_template");
  const url = new URL(advice.path ?? "/help/welcome", "https://workloop.uk");
  url.searchParams.set("utm_source", "resend");
  url.searchParams.set("utm_medium", "email");
  url.searchParams.set("utm_campaign", "account_journey");
  url.searchParams.set("utm_content", String(input.step));
  const cta = advice.cta ?? "Open the Workloop guide";
  const footer =
    `Workloop tips and product updates for your business of one. <a href="${
      escapeEmail(input.unsubscribeUrl)
    }" style="color:#286280">Unsubscribe</a> at any time. Essential account and booking emails are unaffected.<br>Contact Workloop for help: <a href="mailto:support@workloop.uk" style="color:#286280">support@workloop.uk</a>.`;
  return withWorkloopOperator({
    subject: advice.subject,
    text: `${advice.heading}\n\n${advice.paragraphs.join("\n\n")}\n\n${
      advice.steps.map((s, i) => `${i + 1}. ${s}`).join("\n")
    }\n\nA prompt for today: ${advice.prompt}\n\n${cta}: ${url}\n\nWorkloop | support@workloop.uk\nUnsubscribe from tips and product updates: ${input.unsubscribeUrl}\nEssential account and booking emails are unaffected.`,
    html: emailFrame({
      heading: advice.heading,
      preview: advice.subject,
      body: `${
        advice.paragraphs.map((p) =>
          `<p style="font-size:17px;line-height:1.65">${escapeEmail(p)}</p>`
        ).join("")
      }<ol style="font-size:17px;line-height:1.65;padding-left:24px">${
        advice.steps.map((s) =>
          `<li style="margin-bottom:10px">${escapeEmail(s)}</li>`
        ).join("")
      }</ol><div style="background:#f0d18b;border:1px solid #8d8070;border-radius:6px;padding:18px;line-height:1.5"><strong>A prompt for today</strong><br>${
        escapeEmail(advice.prompt)
      }</div><p style="margin:26px 0"><a href="${
        escapeEmail(url.toString())
      }" style="display:inline-block;background:#91b4c8;border:1px solid #443c32;border-radius:6px;padding:15px 20px;color:#443c32;text-decoration:none;font-weight:bold">${
        escapeEmail(cta)
      }</a></p>`,
      footer,
    }),
  });
}
