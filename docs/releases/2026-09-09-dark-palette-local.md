# Dark palette refinement — local, 9 September 2026

The owner likes Light and requested a better Dark colour scheme. The previous
Dark palette combined brown/ochre surfaces, taupe text and bright beige outlines,
which made large screens feel muddy and frames compete with their content.

Dark now uses deep charcoal layers, soft ivory text, neutral secondary ink and
powder-blue accents. Quieter blue-grey frames preserve the paper structure.
Muted amber, green and coral distinguish status without colouring large neutral
areas. Layout, typography, imagery, workflows and the existing Light palette
remain unchanged.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/core/theme/app_theme.dart` | Refine only Dark token values, derived roles and matching immutable compatibility aliases. |
| `android/app/src/main/res/values-night/colors.xml` | Match the dark native launch/background to the new canvas. Keep the light resources and icon background unchanged. |
| `ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json` | Match only the dark launch colour; preserve the default cream entry. |
| `test/core/theme/app_theme_test.dart` | Update Dark expectations, protect all existing Light alias/semantic values, and check actual Dark text/action/control contrast. |
| `test/core/theme/dark_only_theme_test.dart` | Verify both appearance contracts and native light/dark launch values. |
| 33 Dark PNGs in `test/golden/files/` | Record the reviewed palette across the existing screen fixtures. The other 41 PNGs are byte-identical. |
| Brand/UI/decision/current-state documentation | Record the dark-only decision, palette roles and local release boundary. |

## Review and verification

After `source scripts/dev_env.sh`, `flutter analyze` passed with no issues,
`flutter test --dart-define-from-file=.env` passed **1,221 tests** with ten
existing skips, and `flutter build ios --profile --dart-define-from-file=.env`
passed (80.0 MB). All 26 focused theme checks passed. `git diff --check` passed.
The full suite compared the accepted screenshots successfully. Logs, exact
baseline hashes, changed-image manifest and contrast measurements are saved
under `build/dark-refinement-checks/`.

All 74 existing screenshot renders were generated separately before baseline
acceptance. Visual reviews covered Today, account access, welcome, working hours,
service editing, calendar, Money records, Settings, subscriptions, client empty
states, notification controls, booking requests and the public booking page.
The new frames, small text, focus/selected controls and status colours remained
clear. The 33 Dark baselines were then accepted; all 41 other PNGs, including all
36 light-named screenshots, retain their exact pre-change checksums.

The Light semantic block and direct compatibility/derived light colour values
were independently compared against the pre-change source. Exact tests protect
47 Light aliases and 41 Light semantic/derived roles. The default iOS launch
colour and Android light resources remain unchanged.

The dark contrast checks cover normal text on actual canvas/paper/raised/input/
header surfaces, disabled text, status-on-container pairs, primary actions and
input/check/focus boundaries. Mounted appearance-switch tests continue to cover
manual and System changes, unsaved working hours, open service descriptions,
date selection, controllers and focus. No theme-switch behavior was changed.
Across the tested dark surfaces, the minimum tertiary-text contrast is 4.69:1;
disabled text is at least 3.27:1, action text 8.77:1, and the default input frame
against its actual paper fill 3.22:1. Focused input contrast is 9.65:1.

The profile build retains the existing nonblocking Swift Package Manager
adoption warnings for `device_calendar` and `flutter_local_notifications`.

Previews: [Today](../../test/golden/files/dashboard-focus.png),
[sign in](../../test/golden/files/auth-ios-dark-hierarchy.png),
[working hours](../../test/golden/files/onboarding-hours-dark.png) and
[service editor](../../test/golden/files/onboarding-service-editor-dark.png).
These are widget renders, not physical-phone captures.

## Risks and release boundary

The visual change is shared across Dark screens. Light mode, data, navigation,
authentication, appearance preferences and documents are preserved. There is no
schema or backend work. Physical iPhone appearance/startup review is still part
of the next combined release's device validation.

No installation, version bump, deployment or TestFlight upload occurred. Source
remains `1.0.0+19`; the uploaded build does not contain this refinement. Hold this
with the other local tweaks until the owner is ready for the combined update.

Suggested commit: `style: refine dark mode with charcoal and powder blue`
