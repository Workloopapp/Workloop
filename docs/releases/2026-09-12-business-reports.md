# Business reports — 12 September 2026

Reports is available from **Business → Run your business → Reports**. It helps
an owner review performance, inspect the underlying records and take a portable
copy of their business figures.

## Delivered reports

- Business overview: net receipts, expenses, cash surplus, booking activity,
  newly created client records and monthly activity breakdown.
- Payments & refunds: dated cash movements, including partial receipts,
  refunds and legacy paid records.
- Expenses: totals by category and individual expense records with notes.
- Bookings: completed, cancelled and no-show counts, resolved-booking completion
  rate, completed booking value and recorded hours.
- Service performance: completed service/add-on item counts, saved item values,
  averages and hours; multi-service bookings use their saved item snapshots.
- Client activity: clients served, returning clients, newly created records,
  booking counts and net receipts per client.
- Outstanding money: current unpaid remainders and overdue ageing bands.
- Work & follow-ups: tasks due in the period and their current status, plus a
  separate count of undated open tasks.

Dates support week/month/quarter/year to date, last month, all recorded history
and an inclusive custom range. Comparisons use the immediately preceding equal
number of calendar days, with the actual comparison dates shown. Outstanding
money is explicitly a current snapshot; its date selector is hidden.

## Data and trust

Reports reuse the existing paginated workspace providers/repositories. There is
no schema migration, new package, remote rendering service or persisted report
snapshot. All required collections must load before a report is shown; failures
show a retry state rather than partial zero totals. Refresh reloads the inputs.

Receipt movements are rounded to pennies before summing. Timestamped receipts,
bookings and client creation dates use the saved business timezone. Date-only
expense/issue/due fields retain their civil dates. Future-dated receipts and
expenses are excluded. Dates are compared as civil calendar days across DST.

Booking/item value is not collected revenue. Cash surplus is receipts less logged
expenses, before tax, and is not accounting profit or a bank balance. Reports do
not claim tax deductibility, reconstruct historical outstanding balances, infer
true retention, or infer when tasks were completed. Each report includes its
calculation basis in both the screen and exports.

The report route is pinned to the opening account/workspace. Sign-out or a
workspace change revokes the visible report, and export checks current identity
again. PDF uses the existing account-scoped private document viewer.

## Exports and layout

CSV contains metadata, calculation basis, summary metrics, all detail rows and
record IDs; it does not stop at the first page or the 30 visible screen rows.
Free-text CSV cells are escaped and protected against spreadsheet formulas;
numeric cells retain their numeric meaning. The system share sheet lets the
owner save or choose where to send the export.

PDF is an in-memory summary with up to 40 metrics and 40 records. It explicitly
identifies the limit and shortened text, and directs users to CSV for complete
data. It uses the existing embedded Manrope document fonts. Screens use the
shared Quiet + Warm controls/panels and support both themes and enlarged text.

## Files and reasons

- `lib/features/reports/report_models.dart`: typed report definitions, civil-date
  periods and penny/cell formatting.
- `lib/features/reports/report_builder.dart`: pure report calculations and rows.
- `lib/features/reports/reports_provider.dart`: complete, workspace-filtered input
  collection using existing providers.
- `lib/features/reports/reports_screen.dart`, `report_widgets.dart`: report/date
  selection, current-state presentation, refresh, export and accessible layout.
- `lib/features/reports/report_export.dart`: portable CSV and bounded PDF output.
- `lib/features/business/business_screen.dart`: Reports entry point.
- `test/reports_test.dart`, `test/reports_screen_test.dart`: arithmetic/date/
  export tests, provider failure/isolation, account change, navigation and narrow
  phone/light/dark/large-text checks.
- `test/golden/files/more-workspaces.png`, `more-workspaces-light.png`: reviewed
  Business references including the new Reports row.

## Verification

- Reports analysis: clean (`flutter analyze --no-pub` on report files, Business
  screen and the two report test files).
- 14 calculation/export tests and 12 report screen/provider/navigation tests pass;
  four existing Work/Business navigation/responsive tests also pass (30 focused
  checks total). Regression coverage includes one service appearing in legacy,
  primary-item and additional-item bookings, which must aggregate to one row.
- Light/dark screens at 390px and 320px/2x text were rendered and inspected. PDF
  summary pages were generated and inspected, including long customer names and
  bounded detail tables. Both changed Business golden references were inspected,
  updated, and rerun without `--update-goldens`: 2/2 pass.
- `git diff --check`: pass.
- The complete `.env` Flutter suite ran: 1,299 passed, 1 skipped, 5 failed.
  Two expected Business golden mismatches were resolved as above. The two
  `connected_navigation_audit_test.dart` failures passed on a focused recheck
  after concurrent work in the shared checkout. One failure remains outside
  reporting: `task_finance_failure_safety_test.dart` — “failed task deletion
  keeps confirmation open and announced” (expected one delete call, observed
  zero after a missed-tap warning).
- Full-checkout analysis at verification time had seven informational lints in
  concurrently edited appointment/client/attachment/note files; none in reports.
- The required `flutter build ios --profile --dart-define-from-file=.env` was
  attempted twice but Xcode reported unresolved existing Swift package products.
  Package resolution succeeded. An isolated Xcode Profile build then exposed the
  generated plugin package's iOS 13 default against Firebase's iOS 15 minimum.
  The build succeeded using the app's existing iOS 15 target as a command-line
  override, without editing native project configuration:
  `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Profile -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/workloop-reports-derived IPHONEOS_DEPLOYMENT_TARGET=15.0 build`.
  Artifact: `/tmp/workloop-reports-derived/Build/Products/Profile-iphoneos/Runner.app`.

No installation, TestFlight upload, native share delivery or live-business report
comparison is implied by these local checks.

## Follow-up

Validate reports against a consenting beta owner's known business records and
exercise native Save to Files/share on a physical phone before the next release.
If report volume eventually makes the existing complete provider reads expensive,
profile them before introducing server aggregation with identical calculation
semantics and workspace authorization.

Suggested commit: `feat: add business reports with date filters and PDF/CSV exports`
