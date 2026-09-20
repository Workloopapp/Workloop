# Workloop company operator — app and local legal pages

Effective 6 September 2026. The owner authorised Workloop to be presented as a
trading name of **Haani Enterprise Limited**, company **15758586**, registered in
**England and Wales**. The current registered office supplied and verified by the
lead agent is **35 Well Lane, Batley, WF17 5HQ, England**. A proposed address
change is unfiled and is not used in any customer-facing artifact.

This report covers the Flutter app and this repository's `web/` static files.
It does not claim a public website deployment, an app upload, company filings,
intellectual-property transfer, copyright ownership or provider-account conversion.
The separate marketing website, emails and provider accounts are owned by the
lead agent and companion work.

## What changed

- The Workloop brand, app name and package/bundle identities remain intact.
  `WorkloopAppInfo` now supplies the company name, number, jurisdiction, registered
  office, effective date and shared disclosure text.
- Help & support displays selectable company details below its existing About
  links. The address is expressly the registered office, with support directed
  to `support@workloop.uk`; it is not presented as an invitation to send post.
- In-app privacy identifies Haani Enterprise Limited as controller for Workloop
  account/service administration, security, diagnostics, communications and
  support. A business using Workloop remains controller for its own client
  records; the company processes those records on that business's behalf.
- Terms identify the company as the Workloop contracting party. The business
  using Workloop remains the provider of its booked services. Existing content
  ownership/IP language is preserved without asserting that company registration
  transfers ownership of Workloop's intellectual property.
- Local privacy/terms/deletion pages and their footers carry the same disclosure
  and effective date. The Flutter web entry point identifies the operator in
  author metadata while retaining the Workloop title.
- The older local static privacy/terms bodies now match actual current app
  email and weather information and the new Crashlytics disclosure. Reports
  include native technical data and installation/session identifiers and are
  explicitly not described as fully anonymous. The diagnostic paragraph was
  shared with the marketing-policy agent for parity.
- Export/deletion directions now name **Settings > Privacy & data**, and owner
  email preferences name **Settings > Emails to you**. The public deletion page
  distinguishes deleting a Workloop account from a customer's request about a
  business's client records.
- Existing styling is preserved. Static legal text permits long URLs/email
  addresses to wrap so the new disclosures do not create horizontal overflow.

## Files

| File | Reason |
| --- | --- |
| `lib/core/workloop_app_info.dart` | Shared, explicit operator facts and date; support/brand constants retained. |
| `lib/features/settings/legal_document_screen.dart` | Company/controller/contract wording and current data-feature disclosures. |
| `lib/features/settings/support_screen.dart` | Readable, selectable operator details in the existing Help/About surface. |
| `web/privacy.html`, `web/terms.html`, `web/delete-account.html` | Consistent local public legal copies, footers and current settings directions. |
| `web/index.html` | Operator author metadata, no name or package change. |
| `web/legal.css` | Text wrapping only; no palette/layout redesign. |
| `test/workloop_operator_identity_test.dart` | Static identity parity, company/tenant responsibility boundaries, compact large-text UI and Help→Privacy route. |
| `test/features/settings/legal_document_screen_test.dart` | Current effective-date expectation and scrolling to the existing data section after the longer operator introduction. |

## Verification

Scoped Dart analysis and `git diff --check` pass. Standard HTML parser checks
pass for all three legal pages: balanced elements and intact link destinations.
The focused Flutter batch passes **10/10**:

```sh
source scripts/dev_env.sh
flutter test test/workloop_operator_identity_test.dart \
  test/features/settings/legal_document_screen_test.dart \
  test/secondary_surface_visual_test.dart --dart-define-from-file=.env
```

Output: `/tmp/workloop-company-operator-focused.log`. New UI checks exercise
320×568 at 2× text in light and dark appearances, selectable operator text and
the existing Help→Privacy action. The broader secondary-screen matrix also
passes. No golden baselines were changed. Full analysis/tests/native builds
after the parallel company changes remain the lead agent's integration step.
These tests do not establish live legal-page publication, provider identity
changes or a new installed app binary.

The preserved dirty-state receipt is
`/tmp/workloop-company-operator-start-status.txt`. Shared CurrentState and
DecisionsLog documents were left to the lead agent.

## References and limits

The disclosure fields follow [GOV.UK company publication guidance](https://www.gov.uk/running-a-limited-company/signs-stationery-and-promotional-material).
The controller/processor wording separates the party deciding how client records
are used from the service processing them on its behalf, consistent with the
[ICO role definitions](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/controllers-and-processors/controllers-and-processors/what-are-controllers-and-processors/).
Company facts were supplied through the owner's instruction and the lead
agent's register verification; this subtask did not make a company filing.

Follow-up: publish the approved copies through the respective app/website
release workflows, align provider and store identities using their actual
verification processes, and update the address only after its filed status is
confirmed. This source change does not complete those external steps.

Suggested commit: `Identify Haani Enterprise Limited as the Workloop operator`.

## Lead integration and live rollout — 6 September 2026

Full Flutter analysis is clean. Full tests pass: **885 passed, 6 skipped**.
The signed iOS profile build succeeds at 75.3 MB with explicit crash-reporting
configuration. Existing SPM compatibility warnings for device_calendar and
flutter_local_notifications did not fail the build. No device install,
TestFlight upload or App Store submission was performed for this change.

The public marketing website is live with company details on its footer,
booking/payment pages, structured data and all legal routes. Twenty-one live
route checks passed, including extensionless, .html and slash legal variants
and www aliases. Workloop OS was published privately; its homepage and privacy
route were verified using the existing authorised private access.

Marketing source commit: 224376bbc7fb0839673892bc2a9c59ef8d1c48aa, Sites version34.
Private OS source commit: 3bb692b26e471d20b1f754d35d674beb30827d14, Sites version18.
Both checkouts are clean after their scoped commits. Marketing typecheck,
lint and 21 tests (including production build) pass. OS typecheck, production
build and its test pass; OS lint retains the pre-existing next/no-img-element
error in app/workloop-shell.tsx:1068. The newly added layout link passes lint.

Live email functions and all 13 hosted Auth templates have matching company
footers; see 2026-09-06-email-operator.md for exact deployment and verification.
Provider name/billing updates do not themselves prove membership conversion,
asset assignment, legal contract novation, or company-preservation completion.
The private company folder contains the provider-by-provider status, DUNS
confirmation and website/email deployment receipts. Apple/Play company
verification and Stripe company-type conversion remain separately gated.
