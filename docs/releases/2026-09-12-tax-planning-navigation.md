# Tax planning in Business — 12 September 2026

Tax planning now opens from **Business → Run your business**, directly after
Reports. Its shortcut has been removed from the Money overview.

## Changes and reasons

- `lib/features/business/business_screen.dart`: adds the existing tax screen
  through the shared Business module row and navigation helper. The description
  is shortened to fit a phone: “Estimate tax and what to put aside”.
- `lib/features/finance/finance_screen.dart`: removes the old shortcut, unused
  import and its leading gap.
- `test/money_history_hierarchy_test.dart` and
  `test/feature_hierarchy_refinement_test.dart`: update existing navigation and
  screen hierarchy expectations for the extra Business row.
- Two Business golden images: record the new row in light and dark appearances.

Tax calculation, eligibility checks, saved inputs and workspace protections are
unchanged. No migration, new dependency or data change is involved. The lower
Business items remain available by scrolling.

## Verification

- `flutter analyze --no-pub`: no issues. Formatting and `git diff --check` passed.
- All 26 focused Money hierarchy and Business navigation/layout tests passed.
- Full `flutter test --dart-define-from-file=.env`: 1,340 passed, one skipped,
  two Business golden failures. That run compiled the earlier description before
  it was shortened; inspected differences are confined to that text. All four
  Money/Business golden checks passed on the final source and reviewed baselines.
- The required `flutter build ios --profile --dart-define-from-file=.env`
  succeeded. It was repeated after the final wording edit and succeeded again.
- Strict signature verification passed. The final build was installed on
  Ismaeel's iPhone 15 Pro Max and launched successfully through `devicectl` at
  15:10 on 12 September. A physical on-screen walkthrough was not observed.

No feature follow-up is required.

Suggested commit: `refactor: move tax planning from Money to Business`
