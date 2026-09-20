# A calmer Money overview — 12 September 2026

Money now brings its three cash figures into one panel instead of stacking
separate figures, a chart, history controls and planning content down the page.
Unpaid money remains the first actionable item.

## What changed

- Net profit leads the cash panel; received and spent sit side by side. At larger
  text sizes or narrow widths they stack naturally, without reducing text size.
- **Profit trend** opens the existing signed chart on demand. Empty periods do
  not invent a trend. The chart retains its negative values and spoken summary.
- **Payments** opens the existing mixed income/expense history, search, filters
  and full-history actions. Tapping a received/spent total opens its matching
  history directly. Closing the history returns to the compact overview.
- The separate **Plan ahead** heading and target card are removed. The monthly
  target remains a flat, editable row using the shared progress indicator.
- Card/contactless settings become a compact footer action, with the same setup
  sheet and payment capability checks.
- Spent keeps its total and expense list, with categories expandable and mileage
  available through a compact text action.
- Choosing a Money section returns to its top, including the Owed shortcut.

The representative 390 × 844 phone fixture shows the cash figures and payment
history entry above the bottom navigation. Enlarged text can still scroll;
supporting details expand only when requested. Expansion state lasts for the
current Money screen and does not alter business records.

## Files and reasons

- `finance_screen.dart`: grouping, disclosure state, direct history access and
  section scroll reset; existing providers/calculations/editors are reused.
- `finance_screen_widgets.dart`: compact figures, flat accessible disclosure
  controls and the quieter shared monthly-target presentation.
- `payment_collection_sheet.dart`: optional compact setup entry; existing callers
  retain the original card presentation.
- `widgets/money_summary_widgets.dart`: optional category heading, preventing a
  duplicate heading when expanded.
- Money hierarchy, priority, history/search, chart and golden tests: open the
  detail under test explicitly, exercise disclosures and section return, and
  guard the main phone layout. Five reviewed golden images change.
- Receipt-row and failed-income-deletion tests now open Payments before checking
  records; their receipt identity and failure-recovery assertions are preserved.

No dependencies, migrations, tax/payment rules or stored data change. Detailed
history takes a tap to reveal; the totals provide direct filtered shortcuts.

## Verification

- `flutter analyze`: no issues. Formatting and `git diff --check` are clean.
- Focused checks cover 72 tests across Money priority, history, search, signed
  chart and shared target behaviour. Disclosure/navigation checks passed after
  correcting the retained scroll offset when opening Owed at large text sizes.
- Five visual baselines were reviewed and updated: empty/populated overview,
  light/dark payments and searched payments. The phone-layout assertion keeps the
  main figures and history entry above the bottom navigation; normal and 2x
  text fixtures preserve readability and interactive disclosures.
- `flutter build ios --profile --dart-define-from-file=.env` succeeded. Strict
  signature verification passed; the Flutter framework postdates all changed
  feature source files.
- The signed app installed on Ismaeel's iPhone 15 Pro Max and launched via
  `devicectl` at 15:19 on 12 September. A physical on-screen walkthrough was not
  observed; the visual checks above use deterministic fictional-data fixtures.
- Full `flutter test --dart-define-from-file=.env`: 1,340 passed, one skipped,
  two failures in tests that expected payment history to be open on arrival.
  Both were updated to open Payments explicitly before exercising the original
  assertions. All 13 tests in those two files then passed, including both
  previously failing cases. No verification failures remain unresolved.

No additional feature work is required for this layout change.

Suggested commit: `refactor: simplify Money overview and reveal details on demand`

## Follow-up — custom-date control

A selected date range was being used as the Custom tab label. Because tab widths
are calculated from the longest label, a range such as “1 May 2026 - 12 Sep 2026”
made all three tabs wider and pushed the selected tab off-screen.

`widgets/money_summary_widgets.dart` now keeps Week / Month / Custom as stable
labels. Selected custom dates wrap on a separate full-width row, with a Change
action that reopens the date picker. Switching to Week or Month hides that row.
The existing scrolling accommodation for enlarged-text tabs remains unchanged.
No dates, filtering or financial calculations change.

`test/money_ui_test.dart` adds regression cases at 390px, 320px and 320px with
2x text, checking stable tab width, visible wrapped dates, reopening Change and
switching back to Week. The three fixtures were rendered and inspected; all 53
focused Money/date/target tests passed, and final analysis is clean.

The required iOS profile build succeeded and passed strict signature verification.
It was installed on Ismaeel's iPhone 15 Pro Max and launched successfully through
`devicectl` at 15:28 on 12 September. An interactive physical-device date-picker
walkthrough was not observed. Full `flutter test --dart-define-from-file=.env`
passed: **1,345 tests passed, one skipped**, with no failures (2 minutes 51 seconds).

Suggested fix commit: `fix: keep custom date ranges outside Money tabs`
