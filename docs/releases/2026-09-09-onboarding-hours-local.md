# Onboarding working hours — local refinement, 9 September 2026

The working-hours step previously put each day's name, switch and times on two
tall rows, so the owner had to scroll between weekdays and Continue. Its legacy
palette also produced poor contrast in the owner's light-mode screenshot.

The complete week now sits in one paper frame with a day toggle and From/Until
controls on each row. Row spacing adapts to the available phone height, with
Continue fixed below the weekly body. Closed days keep their row height and
retain their times for reopening. The screen uses the active theme's colours.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/onboarding/screens/ob_hours.dart` | Compact seven-day table, pinned Continue, active-theme contrast and accessible controls. |
| `test/onboarding_hours_test.dart` | Protect full-week visibility with the real onboarding header, touch targets, large text, toggling, picker cancellation/confirmation and saved values. |
| `test/golden/onboarding_hours_golden_test.dart` and two screenshot baselines | Review the complete light and dark step with phone safe areas and the shipped fonts. |
| `docs/UIDesignSystem.md`, `docs/DecisionsLog.md`, `docs/CurrentState.md` | Record the layout contract and local release boundary without replacing earlier history. |

## Verification

After `source scripts/dev_env.sh`, `flutter analyze` passed with no issues,
`flutter test --dart-define-from-file=.env` passed **1,212 tests** with ten
existing skips, and `flutter build ios --profile --dart-define-from-file=.env`
passed (79.8 MB). Both light/dark candidates were visually reviewed before
accepting their baselines; the full suite subsequently compared them. Formatting
and `git diff --check` passed. Logs are under `build/onboarding-hours-checks/`.

The 12 focused working-hours and onboarding accessibility checks passed. At
320 × 568, 390 × 844 and 430 × 932 with their phone safe areas and standard
text size, all seven enabled days and Continue are visible and hit-testable;
the weekly scroll extent is zero. Controls retain at least 44-point targets.
At 320 × 568 with 2× text, the week scrolls while Continue remains fixed, and
time values retain their full requested text size.

Tests exercise the existing time picker, confirm and cancel actions, zero-padded
saved times, preserved values on closed days, and advancing to step five. The
first picker check exposed a test-only expected-map type mismatch; the fixture
was corrected. Preview font loading was corrected before visual acceptance.

Previews: [light](../../test/golden/files/onboarding-hours-light.png) and
[dark](../../test/golden/files/onboarding-hours-dark.png). These are widget
renders, not physical-phone captures.

The profile build retains the existing nonblocking Swift Package Manager
adoption warnings for `device_calendar` and `flutter_local_notifications`.

## Risks and release boundary

Defaults, providers, navigation, the shared picker and the saved-hours format
are unchanged. No schema, package or backend change is needed. Larger
accessibility text intentionally permits scrolling rather than reducing text
size or touch targets. Physical iPhone and VoiceOver checks were not repeated.

No installation, version bump, deployment or TestFlight upload is included.
Source remains `1.0.0+19`; the uploaded build does not contain these changes.
Hold this with the other local onboarding and account-access tweaks for the
owner's next combined release. Check the complete onboarding flow on the phone
as part of that release's device validation.

Suggested commit: `fix: fit onboarding working hours on one screen`
