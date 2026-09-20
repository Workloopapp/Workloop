# Consistent appearance changes — local fix, 9 September 2026

Switching appearance could leave a dark card beneath light-mode text. A
regression test reproduced this on the mounted Services screen: the requested
light fill was `#FBF7ED`, while the painted pixels remained dark `#2F2D27`.

The compatibility palette used constant Color objects whose channels changed
through global state. Flutter could therefore consider old and new decorations
equal and retain the previous background Paint. A fresh-screen screenshot or
inspection of the colour getter alone did not expose the fault.

The palette now returns normal immutable colours from each widget's local
Theme. All 47 existing light/dark colour pairs are preserved. Screens, sheets
and dialogs subscribe to their own theme, including older presentation code.
The shared surface no longer replaces its child subtree when brightness changes,
so controllers, focus, selection and unsaved edits survive.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/core/theme/app_theme.dart` | Replace the mutable Color subclass/global palette with immutable local-theme aliases; place the shared sheet frame in BottomSheetTheme. |
| `lib/main.dart` | Let MaterialApp handle System/Light/Dark without global palette synchronization. Preserve the existing appearance provider, router and zero-duration theme change. |
| `lib/features/**` | Migrate colour reads and presentation helpers to local widget/modal contexts; resolve constructor defaults and email styles at build time. Remove four forced-dark date-picker wrappers. |
| `lib/shared/widgets/slate_ui.dart` | Preserve child state in SlateSurface, resolve runtime colour defaults, and let open sheets inherit their current background and frame. |
| `lib/shared/widgets/business_feed_list.dart`, `lib/shared/utils/maps_launcher.dart` | Resolve feed and chooser colours in their mounted contexts. |
| `lib/shared/notifications/local_reminder_service.dart` | Use the existing fixed brand blue for native notifications, which have no Flutter widget context. |
| `test/theme_switch_consistency_test.dart`, palette tests and existing test/integration fixtures | Assert painted results and retained state after theme changes; remove obsolete global setup. |
| `test/golden/files/dashboard-focus-light.png` | Correct the old baseline's retained dark-mode icon and chevron on the light dashboard; reviewed before updating. |
| `docs/UIDesignSystem.md`, `docs/DecisionsLog.md`, `docs/CurrentState.md` | Record the corrected theme contract and local release boundary. |

The mechanical migration covered 1,283 colour references. In total, 81 existing
product files changed; names, colours, layout and business behavior are preserved
apart from the necessary theme/state corrections above. No packages or new
appearance state system were introduced.

## Verification

After `source scripts/dev_env.sh`, `flutter analyze` passed with no issues,
all **1,218 tests** passed with ten existing skips, and the required
`flutter build ios --profile --dart-define-from-file=.env` passed (80.0 MB).
All 26 focused theme tests passed, including pure operating-system appearance
changes with no extra observer or forced parent rebuild in the harness.
`git diff --check` and the source audit for cached palette fields passed.
Logs, pre-fix evidence, screenshot hashes and the 81-file product manifest are
saved under `build/theme-toggle-checks/`.

Focused coverage checks the actual Services card pixels, the complete working
week through manual and System changes, unsaved day changes and exact Continue
values, nested controller/focus/selection retention, an already-open service
description editor, and an open date picker retaining its selected date. Palette
tests compare all 47 light/dark pairs and retain the existing contrast checks.
System-only checks change the phone's brightness repeatedly without writing the
appearance provider or manually rebuilding the app.

The initial reproduction needed an in-memory preferences fixture before it
could reach the valid pixel failure. Intermediate analysis caught the expected
runtime constructor defaults, context-free helpers and cached email text styles;
these were corrected. Final verification uses the repaired source, without
weakening the painted-colour or state assertions.

The first full-suite run exposed one outdated dashboard Light baseline. Its
constant icon widget had retained dark-mode ink after the test changed from
Dark to Light. The reviewed difference is confined to the small attention icon,
its tint and the chevron (0.37% of the image); the new image uses the existing
Light palette correctly. Only that affected baseline was accepted. The Dark
dashboard and other screenshot baselines were retained. The accepted Light PNG
matches the visually reviewed failure candidate exactly; the Dark PNG retained
its original checksum. The subsequent full suite passed all screenshot checks.

The profile build retains the existing nonblocking Swift Package Manager
adoption warnings for `device_calendar` and `flutter_local_notifications`.

## Risks and release boundary

This touches many presentation files because the faulty compatibility mechanism
was shared across the app. Colour identity and theme dependencies change;
business data, repositories, routing and persisted appearance choices do not.
No backend or schema work is required. Physical iPhone switching and VoiceOver
were not repeated during this local pass; include them in the next combined
release's device validation.

No installation, version bump, deployment or TestFlight upload is included.
Source remains `1.0.0+19`, and the uploaded build does not contain this fix.
The owner has asked to bundle the current tweaks before another upload.

Suggested commit: `fix: keep theme changes consistent without resetting screens`
