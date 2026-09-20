# Reports wording and cashflow forecast — 12 September 2026

Reports now explains business figures in everyday language and adds a forward
view of cash for the next 30, 60 or 90 days. The existing report calculations
remain unchanged; the forecasting calculation is separate from recorded results.

## Wording and presentation

- Report choices describe the question they answer. “Net received” becomes
  “Money received after refunds”, “Cash surplus” becomes “Money left after
  expenses”, and “Outstanding money” becomes “Money owed to you”.
- Dates read as “12 Sep 2026”. Comparisons say how much more/less than the actual
  earlier dates. A zero change says “Same as”. Spreadsheet detail dates retain
  ISO formatting where suitable for sorting.
- Each report explains what counts and what does not, without database language.
  “PDF summary” and “Export spreadsheet” explain the two ways to take a copy.
  PDF and CSV include the same revised explanations as the screen.
- The Business entry says “Understand your money and plan ahead”.

## Cashflow forecast

The horizon starts today in the saved business timezone and includes exactly
30, 60 or 90 calendar days. A daily model drives the chart, weekly breakdown,
expected inflows/outflows, cash change, ending cash and lowest cash. A shortfall
is checked each day, even when a later payment restores the weekly balance.

Owners can adjust these local scenario inputs:

- Cash available now, including a negative amount if appropriate. Blank remains
  unknown; it is never treated as a bank balance of zero.
- Extra weekly costs, spread by day with penny-conserving rounding. Blank shows
  an explicit missing-costs message; entering zero means no extra costs expected.
- Include/exclude upcoming bookings without a linked payment.
- Include/exclude overdue and undated payments. Off by default. Including them
  explicitly assumes collection today, plus any chosen delay.
- Payment timing: expected date, one week later or two weeks later.

“Update forecast” validates and applies changes. Inputs are not written to
business records and reset when the report route closes. The chart is semantic,
uses existing theme colours, and supports negative values and enlarged text.

## Calculation rules

- Supported unpaid payment statuses contribute their remaining amount on the due
  date. Paid, cancelled, declined, draft and unsupported statuses are excluded.
- Unpaid deposits use their separate deposit due date where supplied, and are
  subtracted from the final balance. The same penny is never counted twice.
- Future scheduled/confirmed bookings without **any** linked payment are estimated
  at their saved price on the booking date. Past/completed/cancelled/no-show
  bookings are excluded. A linked payment controls that booking's estimate even
  if it was separately recorded as a deposit; this conservative limitation is
  stated in the report and requires accurate remaining balances.
- Delayed collections can leave the horizon; they are not moved back into it.
- Positive future-dated expense records are included. The ordinary expense editor
  currently records past/today expenses, so weekly costs are the main way to allow
  for planned spending. Today's expenses are not subtracted again from the cash
  the owner enters now; negative corrections are not projected cash refunds.
- Weekly costs are additional to future-dated expense records. The form and
  exported assumptions explain how to avoid counting a cost twice.
- Forecasts do not infer new customers, future bookings, bank balances, taxes,
  withdrawals or recurring costs. Owners must allow for unrecorded outgoings.
- Daily balances assume that day's receipts and costs have cleared. Intraday
  timing can still create a temporary shortfall; this is stated in the report.

CSV and PDF preserve the dates, chosen assumptions, missing-input/uncertain-income
notes, totals and weekly breakdown. PDF remains a bounded summary; CSV retains
all rows. Existing account/workspace revocation and export guards remain active.

## Files changed and reasons

- `cashflow_forecast.dart`: pure daily forecast calculation and scenario inputs.
- `cashflow_widgets.dart`: reviewed-input form and accessible cash trend chart.
- `report_models.dart`, `report_builder.dart`: plain-language report labels,
  descriptions, formatting and explanations; forecast report dispatch.
- `reports_screen.dart`, `report_widgets.dart`, `report_export.dart`: date/horizon
  controls, forecast assumptions and notices, readable records, matching exports.
- `business_screen.dart`: clearer Reports entry description.
- `cashflow_forecast_test.dart`, `reports_test.dart`, `reports_screen_test.dart`:
  deposit/delay/status/date/rounding/export tests and interactive form, navigation,
  privacy, light/dark and large-text checks.
- Two Business golden files: updated Reports description only.

No database migration or new dependency is required. Existing paginated providers
remain the business data source.

## Verification

- `flutter analyze --no-pub`: no issues. Formatting and `git diff --check` passed.
- All 39 focused report calculation, export, access-boundary and screen tests
  passed. The 14 report/export tests also passed after correcting the forecast
  PDF fixture to use its forward-looking date range.
- Light/dark report screens at normal and 2x text size, a negative cash chart,
  and the generated forecast PDF were visually inspected. The two Business
  golden differences were inspected before updating; both golden checks passed.
- The required `flutter build ios --profile --dart-define-from-file=.env` failed
  with local Xcode error 74. An isolated Xcode Profile build succeeded using
  `/tmp/workloop-reports-derived` and `IPHONEOS_DEPLOYMENT_TARGET=15.0`, without
  changing native project settings. Strict signature verification passed, and
  the compiled Flutter framework postdates every changed feature source file.
- That signed build was installed on Ismaeel's iPhone 15 Pro Max and successfully
  launched through `devicectl` at 13:07 on 12 September. Installation and launch
  are verified; an interactive walkthrough on the physical phone was not observed.

- Full `flutter test --dart-define-from-file=.env`: **1,342 passed, 1 skipped**;
  no failures (4 minutes 24 seconds).

## Follow-up

Consider saved forecast scenarios if owners need to revisit the same assumptions.
The current form intentionally keeps these inputs local to the report screen.
The separate local Xcode build-path issue remains to be diagnosed.

Suggested commit: `feat: clarify reports and add cashflow forecasting`
