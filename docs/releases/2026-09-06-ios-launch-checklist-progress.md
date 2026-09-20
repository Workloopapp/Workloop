# iOS launch checklist progress — 6 September 2026

The user approved completing the public-launch checklist. Company preservation
then became the priority after the proposed legal operator was found to have
an active compulsory strike-off proposal. Workloop remains the intended brand;
company filing work and legal/provider ownership changes are not complete.

## Integrated local verification

- Full `flutter analyze`: clean.
- Full `flutter test --dart-define-from-file=.env`: 879 passed, six skipped,
  zero failures. Do not count those skipped configuration cases as passing in
  this run.
- iPhone 17e simulator signed-out integration smoke: passed, including create
  account, return to sign-in, and password-reset navigation. Dummy Supabase
  configuration was used; no live authentication request was submitted.
- Signed physical-device profile compilation with `.env` and
  `WORKLOOP_CRASH_REPORTING_ENABLED=true`: passed; `Runner.app` 75.3 MB,
  Xcode build 74.7 seconds. This is a development-signed build, not an archive or
  a TestFlight upload.
- `git diff --check`: clean.

The obsolete sign-in-return selector was corrected in the integration smoke.
The standalone diagnostic probe now skips ordinary debug integration discovery;
its profile/explicit-enable assertions remain intact.

Logs:

- `/tmp/workloop-ios-launch-smoke-fixed-20260906.log`
- `/tmp/workloop-launch-readiness-analyze-20260906.log`
- `/tmp/workloop-launch-readiness-full-tests-20260906.log`
- `/tmp/workloop-launch-readiness-profile-20260906.log`

## Completed source work and remaining evidence

- [Crash reporting](2026-09-06-crash-reporting.md): integrated source/native
  compilation now passes. The iOS Firebase console still showed the SDK setup
  landing page during inspection. No real diagnostic report or readable-stack
  receipt has been verified; a successful symbol-upload build phase is not proof
  of receipt.
- [Stripe owner alerts](2026-09-06-stripe-payment-notifications.md): local
  migration and tests complete; 93 migrations and 743 database assertions,
  eight upgrade assertions and 30 provider/push tests passed in isolated
  validation. No production migration was applied in this pass.
- [Store submission pack](2026-09-06-ios-store-submission.md): prepared locally.
  Public App Store fields, review account, native screenshots and final privacy
  declarations still need completion/verification.

Fresh App Store Connect inspection showed Build 11 as the current testing build,
with 13 testers in the group, and public version 1.0 in Prepare for Submission.
No new build was uploaded or installed on the physical phone in this pass.

Public launch still requires the company/legal-operator work, provider identity
alignment, a genuine merchant card payment/refund, production push/device
verification, live crash diagnostic receipt, reviewer access, final store assets
and a distribution artifact. The website's existing subscription pricing also
needs reconciliation with the planned free-app submission before publication.

Suggested commit message for the combined reviewed code changes:
`Complete iOS launch diagnostics and Stripe owner notification wiring`
