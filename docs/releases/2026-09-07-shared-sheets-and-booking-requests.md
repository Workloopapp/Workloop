# Shared sheets and booking requests — 7 September 2026

## Implemented locally

The shared modal route now draws one edge-attached paper sheet with the existing
quiet/warm colours, rounded top corners, consistent outline and reduced-motion
support. `SlateSheetFrame` supplies safe-area spacing rather than drawing a
second floating card. The route owns keyboard clearance once, so callers cannot
accidentally apply the keyboard inset twice.

Short pickers fit their contents; long/searchable pickers keep the header and
results in one scrollable list. Date and time pickers remain usable on a small
landscape display with enlarged text. The date picker clamps its initial visible
date to the allowed range without changing a record until the owner confirms.
Ordinary primary actions use light haptics; successful booking conversion gives
success feedback only after the operation succeeds.

Booking requests now use plain service/time/message rows and a clear primary
booking action. The conversion form uses the shared sheet, scrolls above the
keyboard, validates finite prices and optional customer email, captures an
immutable submission, and prevents editing or dismissal during a pending save.
Closing a changed draft asks whether to keep editing, discard or save. Invalid
request time zones produce an actionable error rather than crashing. Conversion
preserves the original requested instant through repeated daylight-saving time;
past request dates and requests within the next 366 days open the picker safely.

Eighteen compact existing sheets explicitly opt into the shared scrolling frame:
client actions/tasks, task actions, business settings, booking actions, MFA,
contact/CSV imports, payment/expense actions and map choices. Existing controlled
or already-scrollable sheet bodies retain their own scrolling.

## Files

- `lib/shared/widgets/slate_ui.dart`: shared route/frame/header, pickers, haptics.
- `lib/features/public_profile/booking_requests_screen.dart`: request details,
  conversion layout and draft/submission safety.
- `lib/features/clients/client_detail_screen.dart`,
  `lib/features/clients/widgets/client_tasks_tab.dart`,
  `lib/features/settings/widgets/settings_business_tab.dart`,
  `lib/features/tasks/tasks_screen.dart`,
  `lib/features/appointments/appointment_detail_screen.dart`,
  `lib/features/auth/mfa_screens.dart`,
  `lib/features/imports/csv_import_screen.dart`,
  `lib/features/imports/contacts_import_screen.dart`,
  `lib/features/finance/finance_screen.dart`,
  `lib/shared/utils/maps_launcher.dart`: scrolling opt-in only for this pass.
- `test/shared_sheet_experience_test.dart`,
  `test/booking_request_conversion_recovery_test.dart`,
  `test/golden/shared_sheet_experience_golden_test.dart`, and six
  `test/golden/files/sheet-*.png` baselines: behavioural and visual coverage.

## Verification and limits

- 78/78 focused tests passed with `.env`, including pickers, enlarged-text
  controls, schedule editors, settings safety, secondary surfaces, existing
  workflows, maps, booking conversion, the new sheet goldens and tomorrow brief.
- Scoped Dart analysis passed; scoped `git diff --check` passed.
- All six new light/dark snapshots were inspected before baseline creation;
  the same golden suite passed again afterward. The initial capture run failed
  only because the six new baselines did not yet exist.
- Whole-app analysis/tests, signed builds, native keyboard/touch/haptics checks
  and release distribution belong to the parent release pass. This record does
  not claim an installed or uploaded build or a completed physical-device check.

The principal integration risk is shared modal sizing with any caller not in
the focused matrix; the physical iPhone pass should include a long form with its
keyboard open and a searchable picker. No backend, consent, schema or payment
behaviour was changed by this UI pass.

Suggested commit message: `Polish shared sheets and protect booking confirmation drafts`.
