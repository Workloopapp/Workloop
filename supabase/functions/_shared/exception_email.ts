import { withWorkloopOperator } from "./workloop_operator_email.ts";
import { emailFrame, escapeEmail } from "./learning_email_content.ts";
import { businessContactEmail } from "./business_contact_email.ts";
// Prepared templates, deliberately not enrolled in a marketing or automatic queue.
// A named source event or reviewed support case must confirm the facts before use.
export const exceptionEmailCases = [
  [
    "request_more_information",
    "customer",
    "More information is needed for your booking request",
    "The business needs a little more information before it can decide on your request. Your booking is not confirmed.",
    "Business reviews a pending request and specifies the missing information.",
  ],
  [
    "booking_reinstated",
    "customer",
    "Your booking has been reinstated",
    "The business has confirmed that the previously cancelled booking is active again. Please check the agreed details below.",
    "A previously cancelled booking is explicitly restored and its details are verified.",
  ],
  [
    "booking_manual_confirmation",
    "customer",
    "Your booking details",
    "The business has confirmed the booking arranged directly with you. Please check the agreed details below.",
    "Owner deliberately sends confirmation for a manually arranged booking; never assume every imported record needs an email.",
  ],
  [
    "booking_attendance_followup",
    "customer",
    "Please check your recent booking with us",
    "The business needs to clarify what happened with this booking. Please contact it directly using the details below.",
    "Owner reviews an attendance issue; do not infer a no-show from an incomplete appointment.",
  ],
  [
    "payment_processing",
    "customer",
    "Your payment is still being processed",
    "The payment provider has not confirmed the final result yet. Please do not pay again while the business checks its status.",
    "Provider reports a genuinely pending asynchronous payment.",
  ],
  [
    "payment_failed",
    "customer",
    "Your payment was not completed",
    "The payment provider reported that this payment attempt did not complete. If a pending bank entry appears, ask the business to check before trying again.",
    "Provider failure is final and reconciled; check there is no later successful attempt.",
  ],
  [
    "payment_link_expired",
    "customer",
    "Your payment link has expired",
    "This payment link can no longer be used. Contact the business directly if you still need to arrange payment.",
    "Checkout session expiry confirmed; invoice remains unpaid and no replacement has completed.",
  ],
  [
    "payment_partial",
    "customer",
    "A payment has been recorded against your balance",
    "The business has recorded a part payment. Check the verified payment and remaining balance below.",
    "Reconciled part-payment with verified amount and outstanding balance; avoid duplicating the provider receipt.",
  ],
  [
    "payment_balance_corrected",
    "customer",
    "Your payment balance has been updated",
    "The business has corrected the balance for this reference. Please check the updated information before making another payment.",
    "Owner verifies a balance correction and explains it; not triggered by every edit.",
  ],
  [
    "refund_pending",
    "customer",
    "Your refund is being processed",
    "The provider has accepted a refund request, but it has not yet confirmed completion. Bank posting times can vary.",
    "Provider reports an accepted pending refund; not merely a local refund button tap.",
  ],
  [
    "refund_failed",
    "customer",
    "An update on your refund",
    "The provider could not complete this refund attempt. Please contact the business directly so it can arrange the next step.",
    "Provider confirms refund failed or cancelled and owner reviews the remedy.",
  ],
  [
    "refund_partial",
    "customer",
    "A partial refund has been confirmed",
    "The provider has confirmed a partial refund. Check the amount and reference below. This does not mean the entire original payment was refunded.",
    "Verified successful partial refund; use only when a processor receipt is not already being sent.",
  ],
  [
    "refund_completed",
    "customer",
    "Your refund has been confirmed",
    "The provider has confirmed the refund shown below. It may take additional time to appear with your bank.",
    "Verified successful refund; alternative to, not an additional copy of, a Stripe refund receipt.",
  ],
  [
    "payment_review_required",
    "owner",
    "A customer payment needs your attention",
    "A payment status needs checking before you collect more money or mark this balance settled. Review the provider record and the Workloop balance.",
    "Conflicting or unresolved provider reconciliation identified by monitoring or support.",
  ],
  [
    "dispute_opened",
    "owner",
    "A payment dispute needs your attention",
    "The payment provider has opened a dispute. Review the verified deadline and requirements in your provider dashboard. Workloop has not submitted evidence on your behalf.",
    "Verified dispute event and deadline; owner only, no automated accusation to the customer.",
  ],
  [
    "payout_problem",
    "owner",
    "Your payment provider needs attention",
    "A provider requirement or payout issue needs your review. Check your own Stripe dashboard before relying on a payout date.",
    "Verified provider requirement or payout failure; never request bank credentials by email.",
  ],
  [
    "customer_email_undeliverable",
    "owner",
    "A customer email could not be delivered",
    "The provider could not deliver a customer email. Check the saved address and contact the customer another way if the booking is urgent.",
    "Confirmed permanent bounce or exhausted delivery retries; do not send this to the bouncing address.",
  ],
  [
    "business_contact_missing",
    "owner",
    "Add customer-facing contact details",
    "Your customer emails need clear business contact details. Add a business email or phone in Settings → Notification preferences → Business contact details.",
    "No usable customer-facing contact method; the settings must be available in the installed app before sending.",
  ],
  [
    "import_partial",
    "owner",
    "Your import needs a quick review",
    "Some records need review before your import can be considered complete. Check the verified result below and avoid importing the same file again until you know what was saved.",
    "Import job confirms partial success with safe counts and actionable errors.",
  ],
  [
    "import_failed",
    "owner",
    "Your import could not be completed",
    "This import did not finish as expected. Check the verified result below before retrying, especially whether any records were saved.",
    "Import job or support verifies failure and committed record count.",
  ],
  [
    "export_ready",
    "owner",
    "Your requested data export is ready",
    "Your requested export is ready. Use the secure access instructions below. Keep your export private because it may contain business and customer information.",
    "Authenticated export workflow completes; include only its valid access instructions, never an unverified link.",
  ],
  [
    "deletion_delayed",
    "owner",
    "Your account deletion is taking longer than expected",
    "Your deletion request is still being processed. It has not been marked complete. The verified update below explains what happens next.",
    "Deletion worker remains pending or escalates; do not promise a deadline without a confirmed plan.",
  ],
  [
    "support_acknowledged",
    "owner",
    "We have received your support request",
    "Workloop support has received your request. Your reference and the next step are below.",
    "An incoming support case is recorded; avoid mail loops and repeated acknowledgements.",
  ],
  [
    "support_resolved",
    "owner",
    "An update on your support request",
    "Workloop support has recorded the outcome below. Please check the result and contact support@workloop.uk directly if you still need help.",
    "Human-reviewed support resolution with evidence; never infer resolution from ticket inactivity.",
  ],
  [
    "service_interruption",
    "owner",
    "A Workloop service needs attention",
    "A confirmed service issue may affect the workflow described below. Please follow the verified guidance while recovery is in progress.",
    "Incident verified; send only to affected users and state known impact without speculation.",
  ],
  [
    "service_restored",
    "owner",
    "The affected Workloop service is available again",
    "The service described below has recovered. Please check any work that was interrupted using the guidance provided.",
    "Recovery and impact verified; do not claim lost data was recovered without evidence.",
  ],
] as const;
export type ExceptionEmailId = typeof exceptionEmailCases[number][0];
export function exceptionEmail(
  id: ExceptionEmailId,
  p: Record<string, unknown>,
) {
  const entry = exceptionEmailCases.find((c) => c[0] === id);
  if (!entry) throw Error("unknown_exception_email");
  const reference = String(p.reference ?? "").trim(),
    details = String(p.details ?? "").trim();
  if (!reference || !details) {
    throw Error("verified_reference_and_details_required");
  }
  const [, audience, title, intro] = entry;
  const business = String(p.business_name ?? "The business");
  const subject = audience === "customer" ? `${title} — ${business}` : title;
  const contact = audience === "customer" ? businessContactEmail(p) : {
    text: "For help, contact Workloop directly: support@workloop.uk",
    html:
      '<p>For help, contact Workloop directly: <a href="mailto:support@workloop.uk">support@workloop.uk</a>.</p>',
  };
  return withWorkloopOperator({
    subject,
    text:
      `${title}\n\n${intro}\n\nReference: ${reference}\n${details}\n\n${contact.text}`,
    html: emailFrame({
      heading: title,
      preview: subject,
      body: `<p style="font-size:17px;line-height:1.65">${
        escapeEmail(intro)
      }</p><div style="padding:20px;border:1px solid #8d8070;background:#f5edd9;line-height:1.65"><strong>Reference: ${
        escapeEmail(reference)
      }</strong><br>${
        escapeEmail(details).replaceAll("\n", "<br>")
      }</div>${contact.html}`,
      footer: audience === "customer"
        ? `Sent by Workloop on behalf of ${
          escapeEmail(business)
        }. This is a service message.`
        : "Workloop · Service and support update",
    }),
  });
}
