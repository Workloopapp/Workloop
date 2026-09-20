# Welcome organiser — local refinement, 9 September 2026

The welcome screen now introduces a working day through a single illustrated
paper organiser. The earlier four-node process diagram and repeated benefits
list are replaced by clear rows for bookings/tasks, client context and money.
The headline, shared wordmark, bounded content width and bottom action give the
screen a calmer hierarchy consistent with the revised account-access screen.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/onboarding/screens/ob_welcome.dart` | Replace the diagram and repeated list with existing calendar/client/receipt artwork and a shared paper panel; refine copy, spacing and heading semantics. |
| `test/ui_audit_onboarding_test.dart` | Check readable, accessible copy at double text size with realistic small-phone safe areas, and verify Get started invokes its existing callback once. |
| `test/golden/launch_surfaces_golden_test.dart` | Cover the new welcome screen in light and dark with the primary action inside the normal phone viewport. |
| `test/golden/files/onboarding-operating-loop-light.png`, `onboarding-business-organiser-dark.png` | Visually reviewed light and dark baselines. The light file retains its historical filename. |
| `docs/UIDesignSystem.md`, `docs/DecisionsLog.md`, `docs/CurrentState.md`, this report | Record the presentation change and local-only release status. |

## Verification

After `source scripts/dev_env.sh`:

- `flutter analyze` passed with no issues.
- `flutter test --dart-define-from-file=.env` passed: **1,197 tests**, ten existing skips.
- `flutter build ios --profile --dart-define-from-file=.env` passed (79.8 MB).
- The focused onboarding group passed all 13 tests; compact secondary surfaces
  also passed in both appearances at double text size.
- Both welcome screenshots were rendered to a temporary folder and visually
  inspected before accepting baselines. The full suite then compared them.
- `git diff --check` passed. The temporary screenshot harness was removed.

Previews: [dark](../../test/golden/files/onboarding-business-organiser-dark.png)
and [light](../../test/golden/files/onboarding-operating-loop-light.png).
These are deterministic widget renders, not device captures.

## Limits and next release

This changes presentation only. The onboarding steps, saved draft, business
details, providers and navigation callback are preserved. No packages, assets,
backend changes, installs, uploads or version bumps were introduced. Existing
Swift Package Manager adoption warnings for `device_calendar` and
`flutter_local_notifications` remain nonblocking. Physical-device VoiceOver
was not rechecked in this pass.

Hold this together with the account-access tweaks for the owner's next combined
release and normal device review. Source remains `1.0.0+19`; the new screen is
not part of the previously uploaded TestFlight build.

Suggested commit: `Replace welcome diagram with illustrated business organiser`
