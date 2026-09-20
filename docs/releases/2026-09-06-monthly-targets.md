# Monthly income targets — 6 September 2026

Today’s At a glance and Money now use the same calendar-month receipts and
saved monthly target. Money’s Week, Month and Custom filters continue to control
its history and cash chart; they no longer convert or hide the monthly goal.

## Progress contract

| Progress | Colour |
| --- | --- |
| Below 50% | Red |
| 50% to below 100% | Amber |
| 100% and above | Green |
| No target or unavailable progress | Neutral |

Both surfaces share one native progress indicator and existing light/dark
semantic colours. Figures and spoken status accompany colour. The ring stops
at full, while the percentage may exceed 100%. Percentages below the goal are
floored so 99.9% is not presented as 100%. Comparisons use penny precision, so
five £19.99 receipts correctly reach a £99.95 target despite floating-point sums.

The monthly-only editor saves the existing `revenue_target` setting directly,
without the old 4.345 weekly conversion. Zero removes the target; negative,
invalid and nonfinite entries get an explanation. It supports retry, prevents
duplicate saves, and scrolls with large text and the keyboard. Its field now
belongs to the editor State and is disposed only after the closing animation.
The regression tests found the prior early-disposal exception and verified its
repair.

## Files and reasons

- `lib/shared/providers/finance_provider.dart`: one calendar-month receipt sum
  used by FinanceSummary and Money; retains partial collections and receipt dates.
- `lib/shared/widgets/income_target_indicator.dart`: shared bounded ring,
  percentage, colour thresholds and accessible status.
- `lib/shared/utils/currency_format.dart`: shared penny-precision rounding.
- `lib/features/dashboard/dashboard_screen.dart`: replaces its separate target
  dial with the shared indicator.
- `lib/features/finance/finance_screen.dart` and `finance_screen_widgets.dart`:
  monthly progress across history filters, calendar-day refresh and shared ring.
- `lib/features/finance/widgets/monthly_target_editor.dart`: monthly-only form
  with controller lifetime, keyboard, validation and save-state ownership.
- `test/monthly_target_consistency_test.dart`: 26 new cases covering the real
  screens, receipt boundaries, partial income, filters, saves/retry/zero,
  fractional totals, light/dark colour thresholds and spoken status.
- `test/money_history_hierarchy_test.dart`: current monthly-target expectations,
  including visibility while a custom history range is selected.
- Four reviewed reference images in `test/golden/files`: both Today appearances,
  empty Money and populated light Money.

## Verification at source handoff

- Analysis: no issues.
- Focused tests: **38 passed** (26 new, 11 Money history, one provider-isolation).
- Protected launch-surface golden tests: **27 passed**, after visual inspection
  of the four intentional reference changes.
- Full-suite and exact-source native receipts will be appended below.
- Logs: `/tmp/workloop-monthly-target-focused.log`,
  `/tmp/workloop-monthly-target-goldens-final.log`.

No schema, provider configuration, existing user target value, or store release
is changed by this implementation. The iPhone/TestFlight evidence remains
separate from source and widget tests.

Separate existing follow-up: Money’s receipt history/cash chart currently filter
to fully paid invoices, although its totals and these monthly targets correctly
include partial collections. That history-row representation needs a separate
partial-receipt pass; it has not been changed by the monthly-target request.

Suggested commit: `Keep monthly income targets consistent across Today and Money`

## Final integration — 6 September 00:57 BST

- Clean full analysis and **784 passing Flutter tests**. Six capability-gated
  payment cases skip in the default environment; an additional **18 checks with
  payment collection enabled** passed, including those cases.
- All protected goldens pass in the full suite. The new focused tests also
  verify the editor at 320×568, 2× text and a 230-pixel keyboard inset.
- Signed iOS profile build **74.1 MB**, with successful signature verification.
  Existing plugin Swift Package Manager compatibility warnings remain nonfatal.
- Android profile build **163.1 MB** passed.
- CoreDevice installed the fresh **1.0.0 (12)** app on the owner's iPhone 15 Pro
  Max at **00:56 BST**. Launch at 00:56:37 was denied because the phone was locked.
  The subsequent Mirroring attempt reported the Mac locked as well. Therefore
  installation is verified; launch and a physical target-screen check are not.
- `git diff --check` passed. No TestFlight/Play upload, commit or push.

Final logs: `/tmp/workloop-monthly-target-analyze-final.log`,
`/tmp/workloop-monthly-target-full-tests.log`,
`/tmp/workloop-monthly-target-enabled-tests.log`,
`/tmp/workloop-monthly-target-ios-build.log`,
`/tmp/workloop-monthly-target-android-build.log`,
`/tmp/workloop-monthly-target-device-install.log`, and
`/tmp/workloop-monthly-target-device-launch.log`.

The first focused fixture teardown hung while awaiting a live-style auth-client
dispose under widget-test fake time; it now uses a small auth fake. Another test
waits for the field's normal caret scroll before bringing Save into view. These
fixture corrections did not suppress the real early-controller-disposal bug;
the stateful editor repair is covered by actual save/retry/close interactions.

Artifact SHA-256:

- iOS Runner executable:
  `488c980bb6867cd307f045a59c44f6f1f4c3948a4c7d30cb8efe86aef361f101`
- Android APK:
  `b4f07b53ffdfeee2dd07c6706a24dd131e4cfb8d7fcdf0799ab971087da963e3`
