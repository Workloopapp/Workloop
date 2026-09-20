# Account-access hierarchy — local refinement, 9 September 2026

The sign-in screen previously treated every normal iPhone as a compact window
and left spare space beneath the last button. It now distributes that space
above the welcome/form section and before a quieter legal footer. The boxed
brand panel becomes an open wordmark/illustration row, the welcome heading gains
clearer emphasis, and the form uses shared page gutters with a bounded width.

Account creation remains next to the primary sign-in workflow. Existing password,
social, email-link, phone, reset and legal-navigation handlers are preserved.
Short windows, keyboards and larger text retain scrollable access.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/auth/auth_screen.dart` | Responsive spacing, open brand row, heading hierarchy and legal footer. Only product source file changed in this refinement. |
| `test/auth_screen_compact_test.dart` | Protect normal-phone fit, large-phone hierarchy, small-phone and keyboard access, doubled text, and registration details after legal navigation. |
| `test/golden/launch_surfaces_golden_test.dart` | Add explicit iOS light/dark screenshots including the Apple button. |
| `test/golden/files/auth-login.png`, `auth-register.png`, `auth-ios-dark-hierarchy.png`, `auth-ios-light-hierarchy.png` | Reviewed screenshot baselines for the updated layout. |
| `docs/UIDesignSystem.md`, `docs/DecisionsLog.md`, `docs/CurrentState.md`, this report | Record the layout rule, verification and local-only release boundary. |

## Verification

After `source scripts/dev_env.sh`:

- `flutter analyze` passed with no issues.
- `flutter test --dart-define-from-file=.env` passed: **1,196 tests**, ten existing skips.
- `flutter build ios --profile --dart-define-from-file=.env` passed; local app at
  `build/ios/iphoneos/Runner.app` (79.8 MB).
- Four authentication golden candidates were visually inspected before accepting
  their baselines; the full suite subsequently compared and passed them.
- `git diff --check` passed.

Previews: [dark iPhone](../../test/golden/files/auth-ios-dark-hierarchy.png) and
[light iPhone](../../test/golden/files/auth-ios-light-hierarchy.png). These are
deterministic widget renders, not physical-device captures. The headless test
engine uses bundled Manrope for the Apple button's unavailable system font;
the app's native Apple button font is unchanged.

## Limits and release boundary

No new device install, TestFlight upload, tester assignment, website deployment,
backend change or version bump was performed. The source version remains
`1.0.0+19`; these local changes are not present in the previously uploaded build.
Native keyboard and VoiceOver behavior were not rechecked on a physical phone.
The profile build retains the existing Swift Package Manager adoption warnings
for `device_calendar` and `flutter_local_notifications`; they did not block it.

Fold this refinement into the next combined release after the remaining
owner-requested tweaks and the normal device check.

Suggested commit: `Refine account access spacing and visual hierarchy`
