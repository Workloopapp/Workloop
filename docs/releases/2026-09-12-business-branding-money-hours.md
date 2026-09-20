# Business branding, payments and compact working hours — 12 September 2026

Business owners can add an optional PNG/JPEG logo during onboarding or in
Settings → Business details. The shared picker supports change/remove and keeps
onboarding Continue disabled while saving. Workspace branding appears on the
public booking page and is copied into new invoice/quote snapshots. Issued
PDFs retain their original immutable logo; logo loading failures offer a retry
instead of silently producing an unbranded document.

Money now exposes Card & contactless payments near the top of Overview and in
Settings. Hosted card setup defaults enabled, matching recent release defines;
an explicit false build flag, server availability, and merchant readiness checks
remain in force. Contactless status is visible before Stripe setup and uses the
actual device availability reason. Tap to Pay remains disabled because the
current iPhone signing entitlement does not grant proximity-reader acceptance.
The live workspace payment-account table is empty at this check: businesses
still need to complete Stripe setup; no payment was attempted.

The invoice/quote create action lives in Money's top-right header and follows the
selected document type. Cash summary totals select the corresponding income or
expense timeline, clear stale search and reveal history within the selected
period. Working hours shows all seven days with a fixed Save action on standard
small phones; detailed hours and split blocks open in the shared day sheet.
Large accessibility text can scroll rather than shrink text or touch targets.

## Files and reasons

- `lib/shared/widgets/business_logo_editor.dart`, logo repository, Workspace
  model, onboarding state/profile/completion, Settings business section and
  public-profile repository/view: one reusable scoped branding flow.
- Document editor/PDF: persist branding with each document and render it safely.
- `finance_screen.dart`, its widget part and document list: cash drill-down and
  consistent header action placement.
- Payment capabilities, collection sheet and Settings: visible setup and honest
  device/merchant activation status.
- `working_hours_editor.dart`: compact weekly list with the existing detailed
  editor and shared sheet/picker.
- Focused model, PDF, Money, document, payment, accessibility and hours tests;
  six reviewed Money/Settings visual baselines updated.

## Backend and website

Migration `20260912110151_business_logos.sql` is applied to the existing project.
It adds a public 2 MiB PNG/JPEG bucket, own-user-folder INSERT policy, MFA and
pending-deletion checks, and an auth-row deletion guard. No table columns were
added; existing `workspaces.logo_url` is reused. Objects are immutable to clients
so issued documents keep their branding. Account deletion removes the user's
entire logo folder, including pre-workspace onboarding uploads.

`get-public-profile` v29 and `complete-account-deletion` v34 are deployed with JWT
verification preserved. Compared with live source before deployment, their only
changes expose the logo and clean its storage folder. Public-profile HTTP check
returned 200 with `logoUrl` and without exposing the workspace id. Ten SQL
assertions passed in rolled-back transactions, including onboarding ownership,
cross-user rejection, immutability, size/type settings and MFA step-up. Deno type
checks and two receipt-cleanup tests passed. Security advisors report existing
private-table information notices and six existing public SECURITY DEFINER
warnings; none names the new logo guard.

The separate Workloop Website checkout now displays the logo with initials as a
fallback. URL validation allows only this project's public logo bucket. Sites
version 41 deployed from `fb32aff778b903c99eb1ffa0dbebb202acae2397`; public audience
preserved. A clean isolated checkout excludes existing unrelated duplicate files.
Its TypeScript check, build, 23 rendered-page tests and three booking-logo smoke
cases passed (valid logo, no logo, rejected external URL). Production URL:
https://workloop-os.ismaeelsmiley.chatgpt.site

The original website's direct typecheck encountered an unrelated `page 2.tsx`
duplicate missing a timezone prop. It was preserved; the exact committed source
passed in isolation. The Sites build helper also rejected the pre-existing dual
lockfiles, so validation used the existing Vinext build command and dependencies.

## Verification and release boundary

Final Flutter analysis, full test and signed iOS profile build receipts follow.
The first integrated run passed 1,261 tests with one skip and nine failures:
six intended visual changes, two offscreen test interactions, and one hours sheet
not yet using the shared launcher. Those were corrected before final verification.

App source remains uncommitted alongside existing user changes. No TestFlight
upload or live payment is included. The app changes need the next installed build;
Apple Tap to Pay approval and real-device payment/refund QA remain separate gates.

Suggested commit: `feat: add business branding and improve money and hours flows`

## Final checks

- `flutter analyze`: no issues.
- `flutter test --dart-define-from-file=.env`: **1,271 passed, one disabled-build-only skip**.
- Explicit `PAYMENT_COLLECTION_ENABLED=false` payment contract run: **17 passed**, including the disabled setup explanation.
- All six reviewed updated golden baselines passed in the final full run.
- Live `workloop.uk/cleancarcrazyvaleting` returned the booking page and its deployed stylesheet contained the new logo class. The backend returned the additive logo field; existing orphan-profile protection still returned 404 for an orphaned record.
- Live migration history is `20260912110151`; the CLI-created migration file was renamed to match the applied server version without changing its SQL.
- Security advisor reference for the existing public function warnings: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- `flutter build ios --profile --dart-define-from-file=.env`: **passed**, signed `build/ios/iphoneos/Runner.app` (80.1 MB), Xcode build 45.7 seconds. Existing nonblocking Swift Package Manager notices remain for device_calendar and flutter_local_notifications.
- Final `git diff --check`: passed. No physical-device install or TestFlight upload performed.
