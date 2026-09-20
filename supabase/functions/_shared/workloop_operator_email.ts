// Workloop is the product brand; this disclosure identifies its operator.
// A customer's own business identity and contact details stay in the message.
export const WORKLOOP_OPERATOR_EFFECTIVE_DATE = "2026-09-06";
export const WORKLOOP_OPERATOR_TEXT =
  "Workloop is a trading name of Haani Enterprise Limited.\n" +
  "Registered in England and Wales. Company number: 15758586.\n" +
  "Registered office: 35 Well Lane, Batley, WF17 5HQ, England.\n" +
  "Workloop support: support@workloop.uk\n" +
  "Privacy: https://workloop.uk/privacy\n" +
  "Terms: https://workloop.uk/terms";

export const WORKLOOP_OPERATOR_HTML =
  `<!-- workloop-operator:start --><table role="presentation" width="100%" cellspacing="0" cellpadding="0" data-workloop-operator="${WORKLOOP_OPERATOR_EFFECTIVE_DATE}"><tr><td align="center" style="padding:0 12px 24px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px"><tr><td style="padding:18px 24px;border-top:1px solid #8d8070;color:#665c50;font-family:Arial,sans-serif;font-size:12px;line-height:1.6;overflow-wrap:anywhere"><p style="margin:0">Workloop is a trading name of Haani Enterprise Limited.</p><p style="margin:8px 0 0">Registered in England and Wales. Company number: 15758586.<br>Registered office: 35 Well Lane, Batley, WF17 5HQ, England.</p><p style="margin:8px 0 0">Workloop support: <a href="mailto:support@workloop.uk" style="color:#286280">support@workloop.uk</a><br><a href="https://workloop.uk/privacy" style="color:#286280">Privacy</a> · <a href="https://workloop.uk/terms" style="color:#286280">Terms</a></p></td></tr></table></td></tr></table><!-- workloop-operator:end -->`;

export function withWorkloopOperatorHtml(html: string): string {
  if (html.includes("<!-- workloop-operator:start -->")) return html;
  if (!/<\/body\s*>/i.test(html)) {
    throw new Error("Email HTML requires a body for the operator disclosure");
  }
  return html.replace(/<\/body\s*>/i, WORKLOOP_OPERATOR_HTML + "$&");
}

export function withWorkloopOperator<
  T extends { html: string; text?: string; plainText?: string },
>(content: T): T {
  const append = (text: string) =>
    text.endsWith(WORKLOOP_OPERATOR_TEXT)
      ? text
      : text + "\n\n" + WORKLOOP_OPERATOR_TEXT;
  return {
    ...content,
    html: withWorkloopOperatorHtml(content.html),
    ...(content.text === undefined ? {} : { text: append(content.text) }),
    ...(content.plainText === undefined
      ? {}
      : { plainText: append(content.plainText) }),
  };
}
