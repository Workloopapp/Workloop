# Money: net profit and searchable timeline — 6 September 2026

The owner asked for income after expenses in the former Cash movement chart,
and one searchable Payments history containing both income and expenses.

## Result

- Overview replaces the Made tab label because this view now includes spending.
  Spent retains its category breakdown, and Owed retains the collection queue.
- Net profit is recorded received income minus recorded expenses for the selected
  week, month or custom dates. Signed bars use a zero line: losses extend below
  it, gains above it. Negative amounts also have minus signs and accessible text.
- Payments combines existing received-income and expense records, newest first,
  with All / Income / Expenses filters. Search checks names, payment references,
  descriptions, categories, amounts and dates across the whole selected period
  before the five-entry preview is applied. Active search shows up to 25 matches
  immediately, the complete match count and View all results for longer lists;
  broad searches do not mount thousands of rows by default. Clearing search
  returns to the recent five-entry view.
- Spent and Owed have their own search fields. Search/filter changes do not
  change the overview totals or monthly income target. Chart, target and card
  collection setup stay above history, including with long histories.
- Part-payments now appear in received history using the amount collected. Their
  remaining balance stays in Owed, and their action sheet clearly distinguishes
  received and remaining amounts. Negative refund adjustments remain negative.
  Detail dates now use the actual recorded receipt date rather than issue date.
- The timeline uses flat rows with signed amounts and explicit entry types;
  expense editing and deletion remain accessible without hidden long-press-only
  actions. Existing payment links, receipt/refund actions and record routes stay
  connected to the original records.

## Data and failure boundaries

This is a computed view of existing income and expense records, not a new
ledger. The current payment model contains the cumulative collected amount per
record; this change does not invent separate historic instalment events.
Unpaid amounts are excluded from received income. Recorded expenses are the
deductions; no unrecorded fees, tax or costs are inferred.

Expenses must load before net profit or a complete mixed timeline is shown.
If they fail, the app shows Retry instead of treating them as zero. The Income
filter still allows access to known receipts, and Owed remains independent.
Calendar boundaries use calendar days across daylight-saving changes.

No database migration, backend/provider configuration, notification preference,
customer message or store upload is part of this change.

## Files and reasons

- `lib/features/finance/finance_screen.dart`: integrate chart/timeline, scoped
  search/filter/disclosure, dates and correct part-payment detail amounts.
- `lib/features/finance/finance_screen_widgets.dart`: replace the chart with
  signed net-profit presentation and remove the superseded expense-row widget.
- `lib/features/finance/money_profit.dart`: pure calendar-bucket profit calculation.
- `lib/features/finance/money_timeline.dart`: pure merged chronology and search.
- `lib/features/finance/widgets/money_timeline_widgets.dart`: shared flat expense
  row, readable signed amount/date and accessible actions.
- `lib/features/finance/widgets/payment_cards.dart`: explicit received-entry
  mode while preserving default collection-row behaviour.
- Focused new tests and updated existing Money regressions cover calculations,
  search, full-history reachability, partial/refund states and layout.

## Verification

Final test, visual review and native build/install receipts will be appended
after the implementation is checked.

Visual review covered the populated light and empty dark overview, mixed
Payments timeline in light/dark and a filtered search. The two existing
overview baselines intentionally changed and three new timeline baselines were
added only after reviewing their rendered images. The net-profit header total
was aligned to the right during this review. The five accepted visual cases
passed together.

The focused feature/payment batch passed **76/76**. The initial full run exposed
six older monthly-target tests whose selectors assumed a unique amount label
and a single text field on Money. Their assertions are now scoped to the
received-income panel and the monthly-target editor; the complete **26/26**
monthly-target suite passed afterward. No target calculation/save behaviour
was changed to satisfy those tests. The final whole-app rerun is recorded below.

## Final receipt

- `flutter analyze`: no issues found.
- `flutter test --dart-define-from-file=.env`: **863 passed, six configuration
  skips**. The separate **76/76** focused run had card collection enabled and
  included the skipped payment/receipt-email cases.
- All five reviewed Money visual baselines passed again in the whole-app run.
  No other visual baselines were updated for this task.
- Twelve net-profit cases also passed under `TZ=Europe/London`, including both
  daylight-saving transitions. The final full run covers the updated chart
  header alignment and the 25-result search disclosure.
- iOS profile: **74.2 MB**, successful build and strict deep signature check.
  Android profile: **163.2 MB**, successful build. Both enable existing card
  collection and keep Tap to Pay disabled; the local iOS profile uses sandbox
  push credentials. Provider settings were not changed.
- Local **1.0.0 (12)** installed successfully on the owner's iPhone on
  **6 September 2026 at 02:02 BST**. Launch at **02:02:41–42** was denied with
  `RequestDenied / Locked`. Mirroring reported the Mac locked. Installation is
  confirmed; hands-on Money navigation/search on the device remains unobserved.
- `git diff --check`: passed. Existing dirty work was retained, with the starting
  inventory recorded in `/tmp/workloop-money-timeline-start-status.txt`.
- No TestFlight/Play upload, production deployment, live payment or customer
  message was sent.

Artifact SHA-256:

```text
iOS Runner: b178f94650a86bc5c66861066a18aaae7f87c8d9664940c8c27a815fbd055505
Android APK: aca698b308e985f42e1652de5a5cb877b8ce1c65cf70bf683bf23abe5289dc17
```

Remaining manual check: open Money on the iPhone, compare a known received
payment and recorded expense with the chart, search the timeline, and open both
record types. Android has build/test evidence, not a physical-device check.

Previews: [mixed timeline light](../../test/golden/files/money-timeline-light.png),
[mixed timeline dark](../../test/golden/files/money-timeline-dark.png),
[search](../../test/golden/files/money-timeline-search-light.png).

Suggested commit: `Show net profit and searchable income and expense timeline`
