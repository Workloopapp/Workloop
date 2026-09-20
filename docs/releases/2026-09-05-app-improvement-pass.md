# App improvement pass — 5 September 2026

Scope: reliability, loading/navigation, all-screen source review and shared
Quiet + Warm polish before the next beta. The owner's TestFlight hold remains.
Existing uncommitted app/backend/brand/email changes were preserved.

## Changes and reasons

| Area | Improvement | Main implementation |
| --- | --- | --- |
| Page transitions | Opaque page backgrounds prevent Money/other old content showing through pushed forms and the keyboard. Main tabs change immediately and retain their state; native back interactions remain. | `main.dart`, `app_theme.dart`, `slate_ui.dart` |
| Startup | Removed the artificial launch delay and the full-dashboard gate. Navigation appears after workspace verification; sections own their loading/error states. | `main.dart`, dashboard |
| Shared records | Client views, dashboard attention, booking details, settings and Money share canonical collections. Finance reads run concurrently. A shared clock recalculates date-based state without refetching every minute. | `shared/providers`, client/booking detail providers |
| Refresh | Pull-to-refresh waits for results. Empty/short lists support it. Authenticated resume and foreground push refresh the workspace; renamed/deleted clients refresh joined booking/payment/task/note names. | `workspace_refresh.dart`, feature lists, `remote_push_bootstrap.dart` |
| Draft safety | Prevent double submits and back/discard during pending saves. Booking detail updates outside editing, preserving active drafts; service-load failures show Retry. | Client, booking, income and expense editors |
| Offline return | Known verified content stays mounted under a blocking retry screen on temporary verification failures. Invalid identities/changed workspaces remove old protected state. | Auth/Workspace gates |
| Today hierarchy | Next booking includes future days; single-card natural height. Removed duplicate Coming up and visible Business Feed. Attention uses flat rows, and failures do not pretend the day is clear. | `dashboard_screen.dart`, legacy feed redirect |
| Notifications | Retained useful incoming updates; removed self-alerts after manual money/cancel/no-show actions. Older unread items can be marked read; rapid taps cannot open duplicate routes. | Notification screen, money/detail actions |
| Business readiness | Failed data reads no longer look like unfinished setup. Current and legacy weekday keys show saved working hours correctly. | Business/Profile screens |
| Retro UI | Continuous bottom bar without vertical separators; selected blue marker/label; corrected scroll clearance. Stronger uninterrupted panel corners and single-frame segmented controls. | Theme/shared components |
| Weather | Opt-in current-hour forecast, matching illustration, optional device location/manual UK area, caching and explicit unavailable states. | `features/weather`, `functions/local-weather` |
| Disclosures | Native and public website privacy/terms explain location/provider handling and controls; store preparation documents reflect platform precision classifications. | Legal screen, StoreSubmission, website privacy/terms |

## Review coverage

The detailed [screen/workflow inventory](2026-09-05-screen-workflow-review.md)
covers Today, Clients, Bookings/requests/calendar, Tasks, Notes, Money,
Business/profile/booking page, Notifications, Auth/onboarding, Settings/legal,
imports and calendar tools. It records source/testing coverage and limits.

## Verification record

Final results are recorded below after the combined verification run. Earlier
failures during this pass included intentional golden changes, obsolete
transition expectations, one async auth-event test race and missing in-memory
storage fixtures in newly added gate tests; these were corrected rather than
hidden. New raster regressions check actual page pixels during native iOS
transitions and keyboard resizing. Golden diffs were visually inspected before
updating expected images.

## Deployment and release limits

- Weather function deployed as `local-weather` v1, ACTIVE, JWT verification on.
  Unauthenticated calls return 401. Four proxy tests and a direct public London
  MET Norway request passed. Authenticated app-to-function evidence is separate.
- Website privacy/terms deployed as version 33; the actual workloop.uk privacy
  page returns the optional weather/provider/retention text.
- No TestFlight upload. No live card charge/refund, account deletion or bulk
  customer email was performed during this app pass.
- Physical device behavior, measured performance and external-provider delivery
  must be distinguished from source/unit/golden/build checks. This is not a
  claim that no possible bug remains.

Suggested app commit after review: `Fix workspace freshness and navigation; polish Quiet + Warm UI`.

### Account boundary follow-up

The final review found that a newly opened route could briefly reuse a previous
account's cached workspace after switching accounts. The app-level auth listener
now reloads verification/workspace providers on actual user-ID changes before
route listeners render, and gates use current SDK identity and only preserve
error-state data they previously verified. Same-user token refreshes keep caches.
Five focused gate regressions pass, including an unmounted old gate followed by
a fresh gate for an account whose workspace request is pending or failed.

### Combined automated results

- Static analysis: no issues.
- Full Flutter suite: **542 passed, 6 configuration-dependent skips**.
- Explicit payment-collection configuration: **8 passed**, covering both mobile
  platforms, restricted/ready connected accounts, receipt/refund access and
  deliberate payment-request email. Native Tap to Pay remains disabled pending
  its separate real-device/provider entitlement requirements.
- Weather proxy: **4 passed**.
- Both golden suites passed within the full suite after inspected visual updates.
- Whitespace/diff check passed.

Native build and installed-device evidence follows below.

### Final navigation preference

After seeing the physical build, the owner preferred restoring the dividers and
reducing the bar height. The final revision uses a 64-point row (previously 76),
lower icons and continuous dividers through the home-indicator safe area. This
supersedes the separator removal noted earlier. The blue selected marker/label
and usable touch targets remain. Final revision verification is recorded below.

### Final revision verification and installed devices

- Static analysis: **no issues**. Full Flutter suite: **550 passed, six
  configuration-dependent skips**. Eight new bottom-navigation checks verify
  the 64-point row, full-height dividers, safe-area handling, enlarged text,
  light/dark pixels and tap-through behavior. Inspected golden images were
  updated, then the full suite passed. `git diff --check` passed.
- Final signed iOS profile build: **73.9 MB**, version **1.0.0 (12)**, card
  collection enabled. Installed on the paired iPhone at 18:57 and launched
  successfully at 18:58 on 5 September. **No TestFlight upload.**
- Final Android profile APK: **162.6 MB**, card collection enabled. Installed
  and cold-launched on a fresh API 36 Pixel 8 emulator. The signed-out screen
  rendered correctly, the process remained running, and the captured Android
  runtime/Flutter error log was empty. The existing QA emulator had a different
  signing key; its app and data were preserved rather than uninstalled.
- Physical iPhone checks on the first improved build verified navigation
  through Today, Clients, Money and Business, correct saved working hours,
  next-day booking selection after today's work, and Money → Record income
  without previous-screen text showing through. No records were saved during
  these checks. Keyboard resizing/native transitions also have raster coverage.
- The physical iPhone showed **16° · Partly cloudy · Near you** after optional
  location setup, with the matching illustration. Approximate location was
  selected in the OS prompt. This verifies the authenticated installed app →
  deployed weather function → forecast path, beyond anonymous endpoint probes.
- The final shorter, divided bar was installed after those physical checks.
  Its appearance was verified in golden/raster tests; another physical visual
  check was unavailable because iPhone Mirroring reported the phone in use.

### Remaining validation limits

This pass did not measure a before/after performance trace, run every feature
physically, test on a real Android phone, or verify live charges/refunds and
external push delivery. Payment configuration checks are automated, not proof
of a real business's Stripe activation. Follow-up release QA should focus on
those device/provider paths and the owner's review of the installed compact
navigation before the separately authorized TestFlight upload.

Build warnings remain for plugins that currently fall back to CocoaPods rather
than Swift Package Manager, plus Android deprecated-API notices. Both native
builds succeeded; these warnings were not suppressed.


### Further refinement: setup, access, proportions and edge cases

This section supersedes the earlier 64-point navigation measurement for the
current source. The navigation row is now 52 points plus the device safe area;
its dividers continue to the bottom, icons are smaller, and enlarged text can
increase row height. Touch targets remain at least 44 points. Working screens
omit the repeated wordmark; Today retains it. Shared title size is 26 points and
content starts higher. Business now prioritises booking requests and the booking
page in a compact panel, followed by services, hours, profile and reminders.

New users get a skippable, resumable five-step guide after successful setup;
Settings offers replay. It opens real workflows and creates no demonstration
records. Mobile valeting/detailing is available, while Other accepts a custom
occupation. Skipping optional setup clears stale choices. A committed workspace
stays successful when optional name/reminder preferences fail, and persistent
setup errors let the user return to edit.

Email/password, Google and native Apple remain available, with passwordless
email in More options. Phone and Apple browser sign-in have explicit deployment
gates. Phone-first accounts must verify an account email before setup, enforced
both in Flutter and the deployed onboarding RPC. Delayed invalid-session cleanup
cannot sign out a newly authenticated account. Native callbacks have one owner
so GoRouter and app_links do not compete for the same link.

Booking SMS has been deployed **off**, with independent 24-hour/1-hour controls,
permission for each exact customer number, provider STOP handling, cancellation
and reschedule rechecks, deduplication, uncertainty handling and deletion-proof
rolling limits. Existing customers have not been enrolled. Provider setup and
real SMS/OTP tests remain activation requirements; email reminders continue
independently. See the dedicated SMS report for the full operational contract.

Additional review fixed stale settings after leaving a slow save, outdated retry
errors, account changes during permission confirmation, large-text/keyboard
permission dialogs, and completed/no-show bookings appearing as a client's next
booking. Tap-to-top now checks each visible scroll position, preserving hidden
Work sections even when they share a controller. Reselecting Work keeps the
current Schedule/Tasks/Notes section and returns it to the top.

#### Changed areas and reasons

| Files/area | Purpose |
| --- | --- |
| `lib/main.dart`, shared `slate_ui.dart`, theme tokens | Account isolation, compact headers/navigation, visible-only scroll-to-top and first-use guide integration. |
| Business, profile, clients, Work, Money and Settings screens | Clearer hierarchy and records/actions closer to the top; truthful next booking and loading/error state. |
| `lib/features/getting_started/`, onboarding screens/provider/repository | Resumable guide, occupation choices, safe committed setup, retry/edit recovery. |
| Auth screens/methods/repository, iOS/Android callback configuration | More account access methods, honest provider gates, verified email and stale-session protection. |
| `lib/shared/sms/`, communication settings and client permission controls | Separate reminder timings with explicit per-number permission, safe slow-save behavior and unavailable-state recovery. |
| Two new auth/SMS migrations and SMS/shared worker functions | Server-side email boundary and durable, disabled-by-default SMS delivery controls. |
| Focused widget/raster/database/provider tests and inspected goldens | Regression coverage for the reported problems and newly discovered edge cases. |

Suggested commit: `Polish app navigation and onboarding; harden account and reminder workflows`.

### Edge-case verification matrix

This records the cases actually inspected or tested. Focused suite counts overlap
and should not be added together. Final global Flutter/build results are recorded
separately; provider configuration, deployed code and delivered messages remain
distinct kinds of evidence.

| Area | Cases covered | Evidence and remaining limits |
| --- | --- | --- |
| Navigation and old-screen content | Pushed forms and keyboards cover the prior page; retained tabs keep their state; smaller screens, enlarged text and bottom safe areas remain usable. | Raster/widget tests and inspected goldens. Earlier physical iPhone checks reproduced Money → Record income without bleed-through. Final-build physical review belongs to the release pass. |
| Dashboard and linked records | Date changes update derived state; sections do not turn failed reads into invented zeroes; joined client/booking/payment/task/note data refreshes together; finished/cancelled future bookings cannot become a client's next booking. | Shared-provider, refresh and client-next-booking regressions; earlier physical next-day booking check. No before/after performance benchmark or every-screen physical run. |
| Saves, retries and interruptions | Duplicate submits and back/discard while saving; refreshing empty lists; leaving communication settings before save finishes; disposed providers; failed saves preserve edits; old-workspace completion cannot invalidate another workspace. | Focused communication/client batch: 31 passing tests. Real network loss and account switches on a physical phone remain separate checks. |
| Auth and account boundaries | Wrong/unverified identity, stale workspace cache, delayed invalid-session cleanup after another account signs in, recovery versus normal auth events, capability lookup failures, missing provider configuration and repeated OTP/link actions. | Auth/onboarding/guide and sign-out/gate widget regressions. Phone sign-in remains gated; complete external OAuth, inbox-link and real OTP journeys require provider/device evidence. |
| Setup and first-use guide | Custom occupation restored accurately; mobile valeting service suggestions; intentionally empty/skipped steps; old draft dates; committed workspace followed by optional metadata/preference failure; retry/review; delayed guide lookup after account change; skip, resume, replay and enlarged text. | 20 original setup/guide tests plus later adversarial auth/onboarding coverage. Guide state is local and separate from real setup/email predicates. No fake client or booking data is inserted. |
| Business and notifications | Failed setup reads versus genuinely missing data; legacy weekday formats and enabled-but-empty hours; request inbox remains reachable; invalid notification destinations; rapid taps; unread records beyond first page; permission refresh on resume. | Screen/workflow and hierarchy tests. Permission granted does not prove remote push delivery; actual APNs/FCM receipts remain a provider/device check. |
| Weather | No location/permission, manual area fallback, errors and stale requests, age/cache bounds and honest unavailable state. | Flutter and proxy tests; earlier installed iPhone showed matching local forecast through the authenticated deployed function. It is a current-hour forecast, not a personal weather-station reading. |
| Customer communication controls | Unconfigured or unknown SMS availability; separate email/text timings; stale phone confirmation; unsupported mobile; provider STOP; changed account/workspace; failed and repeated saves; keyboard and large-text dialogs. | Dedicated SMS/communication widget regressions and existing email tests; server capability controls availability. No carrier delivery inferred from UI state. |
| SMS queue and cost protection | Due windows, new bookings/no backlog, cancelled/moved/deleted bookings, consent/number changes, expiry and retries, old/reclaimed leases, crash-after-dispatch uncertainty, cross-business recipient caps, deletion-proof usage limits and independent retention. | Full local PostgreSQL replay: 89 migrations, 22 suites, 575 assertions, including 72 SMS checks and 19 verified-email checks. Single-connection PGlite cannot prove live simultaneous-session locking or carrier timing. |
| SMS provider callbacks and failures | Real SDK signature validation through proxy URL rewriting; tampered/duplicate parameters; wrong account/service; STOP/START and 21610; callbacks before worker completion; stale dispatch tokens; 429 versus uncertain failures; DST's duplicate hour; short provider validity; invalid limits and failed reservations. | 12 native Deno tests; SMS endpoint and existing worker typecheck. No Twilio account/sender activated and no test SMS sent. Requests already handed to a provider cannot be recalled by a later cancellation/STOP. |
| Deployed SMS and existing email worker | Public/invalid bearer rejected; unconfigured webhook closed; private tables/RPC ACLs; all businesses SMS-off; scheduled worker still succeeds with SMS disabled. | Live SMS v1 and worker v30 ACTIVE; observed HTTP 200 worker results with no failures and zero SMS accepted. Retention cron active; first hosted retention execution was not yet observed. Existing email/lifecycle database suites still pass. |
| Payments and release | Automated collection availability, connected-account state, request/receipt/refund access; preservation of native release gates. | Automated coverage and earlier native builds only. Real business Stripe activation, live charges/refunds, physical Android and final-build review remain explicit limits. No TestFlight upload. |

Source reports: [app improvement pass](2026-09-05-app-improvement-pass.md),
[screen/workflow review](2026-09-05-screen-workflow-review.md),
[account access](2026-09-05-auth-access-methods.md),
[setup/guide](2026-09-05-onboarding-guide.md), and
[SMS backend and controls](2026-09-05-booking-sms-reminders.md).


### Final Edge Function CI-equivalent checks

Using Deno 2.9.4 with a separate cache, all **123 backend tests** passed through
CI's `deno test --allow-env supabase/functions` command. Formatting passed for
all **88 files**, and all **16 workflow-listed endpoint typechecks** passed.
The workflow now explicitly checks the SMS and local-weather endpoints.

The aggregate test run exposed an SMS test import that depended on its nested
function import map. Its import now names the same pinned Twilio 6.1.0 package
explicitly, so both standalone and whole-directory test discovery work. Deno
formatting was applied mechanically to 25 currently changed backend files,
including 17 email/payment/learning files; runtime logic was unchanged by that
formatting. Standard checks recorded dependency checksums for reproducibility.

These are local CI-equivalent checks, separate from a hosted GitHub Actions run.
Formatting-only differences do not change deployed function behaviour and were
not redeployed. Database SQL was unchanged; the prior **89 migrations / 22 suites /
575 assertions** result remains the database evidence. Flutter/native build and
physical-device results remain separate from these backend checks.

## Physical-device booking-request count discrepancy

Final installed-build review exposed Today showing **4 booking requests** while
Business showed **6 requests waiting** in the same workspace. Source tracing
confirmed different status rules: Today counted only `pending`, while Business
and the Active request inbox included `pending` and `contacted`. Contacting a
customer does not resolve their request, so these two requests were incorrectly
missing from Today's attention count.

`BookingRequest.needsDecision` now defines the shared rule used by Today,
Business and the Active inbox. The New inbox filter remains pending-only;
confirmed and declined requests remain Closed. Past requested dates do not
silently remove an unanswered request. Today's supporting text now says
**Awaiting a booking decision**, which also covers a contacted customer.

The integrated regression reproduces four pending and two contacted requests,
checks the Business screen, actual Active/New/Closed inbox badges and Today
provider in one container, confirms one contacted request, then verifies all
active totals become five. It also proves switching screens uses the same
canonical read and a decision requires only one refresh. The six targeted
provider/navigation suites passed **23 tests**; scoped analysis and diff checks
passed. Evidence: `/tmp/workloop-request-count-consistency.log`. This source fix
requires the final native rebuild before its matching count is claimed on the
installed app; no live customer data was modified for the test.


## Final automated checks and native artifacts — including the count fix

The following log results were read directly after the booking-request count
fix. Suite totals overlap and must not be added together as a unique-test count.
These final results supersede earlier incomplete or intermediate Flutter runs.

| Check | Verified result | Evidence log |
| --- | --- | --- |
| Full Flutter suite, including request-count regression | **621 passed, 6 configuration-gated skips; no failures** | `/tmp/workloop-final-including-request-count-suite.log` |
| Payment collection explicitly enabled | **7 passed**, covering payment-email review and iOS/Android receipt/refund UI with connected charges enabled and disabled | `/tmp/workloop-final-payments-enabled.log` |
| Backend source/security contracts | **71 passed**; these inspect contracts and are separate from the PostgreSQL and native Deno results above | `/tmp/workloop-final-backend-source-contracts.log` |
| Release safeguard tests | **11 passed** | `/tmp/workloop-final-release-safeguards.log` |
| Whole-project Flutter analysis | **No issues found** | `/tmp/workloop-final-count-analyze.log` |
| Final iOS profile build | **Succeeded**, automatically development-signed; `build/ios/iphoneos/Runner.app` (74.0 MB reported) | `/tmp/workloop-final-count-ios-build.log` |
| Final Android profile build | **Succeeded**; `build/app/outputs/flutter-apk/app-profile.apk` (162.9 MB reported) | `/tmp/workloop-final-count-android-build.log` |

The iOS build still reports that `device_calendar` and
`flutter_local_notifications` do not yet support Swift Package Manager. This is
a non-blocking warning in the current toolchain and should be checked during a
future Flutter/plugin upgrade. No dependency upgrades were performed merely to
remove version-availability notices.

These are local tests and profile artifacts, not a TestFlight upload, production
store release, completed OAuth sign-in, live-money transaction or physical
Android validation. Final count-fix build validation on the iPhone is being
recorded separately by the release reviewer; this entry does not claim it has
passed. The build result now fulfils the rebuild requirement recorded in the
preceding count-discrepancy section.

## Final count-build device checks and subsequent follow-up

On 5 September at approximately 20:22–20:30 BST, the final count-corrected
1.0.0 (12) profile build was installed and launched on the owner's iPhone.
iPhone Mirroring showed **6** booking requests awaiting a decision on Today
and **6** on Business, resolving the earlier 4/6 disagreement. The actual
location weather displayed 14 degrees and partly cloudy; the Clients list
showed its populated list and next-booking order. The compact navigation and
full-height separators were visible on these screens.

The matching Android profile APK installed successfully on the separate
`WorkloopPolishReview_API36` emulator and its main activity launched. These
are installation/launch observations, not real Android handset or carrier QA.

Further physical checking found that reselecting Clients did not return the
scrolled list to the top. Tapping the mirrored iPhone clock also did not
produce an observable scroll. The reselect path is being fixed and covered
with a real-shell regression before the next local build; native clock input
must be distinguished from a test that injects a Dart method-channel event.

The owner has now paused SMS because of cost and authorized a manual
WhatsApp reminder action. Those subsequent code changes require new focused
verification and native builds. No TestFlight upload has been performed.

## Physical-device navigation reselection follow-up

The final-device review found that tapping the selected Clients tab did not
return its scrolled list to the header. A regression using the real
`MainShell(initialIndex: 1)`, populated Clients screen, phone safe areas and a
scroll gesture reproduced the failure: its offset stayed at 740 instead of
returning to zero. The bottom-navigation callback returned early for the current
destination, so the existing `_navigateTo` scroll-to-top handling was unreachable.
Removing that one return restores the existing shared shortcut without changing
visibility filtering or native gestures.

The navigation-assist, Work/Business and shared-UI suites passed **36 tests**.
New real-shell checks cover Clients tab reselection, a native status-bar message,
and retaining Work's selected Tasks section while returning Tasks to the top and
preserving the hidden Notes position. Existing route, shared-controller,
offscreen PageView, draft-back and create-action preservation checks also passed.
Evidence: `/tmp/workloop-clients-reselect-before.log` (intentional reproduction)
and `/tmp/workloop-navigation-reselect-after.log` (passing final focused run).

The injected native message proves the Dart callback and scroll targeting. It
does not prove UIKit delivered a physical status-bar tap through iPhone
Mirroring; that remains a separate device observation. This source change needs
the next native rebuild and device recheck before claiming the installed-tab
shortcut is fixed. The prior final-artifact entry predates this follow-up.

### Native clock-tap ownership correction

Further source inspection found a concrete native integration conflict, beyond
the tab callback above. The installed Flutter **3.44.8** engine already creates a
status-bar `UIScrollView` detector in `FlutterViewController`. Workloop's
`AppDelegate` added another enabled detector. Apple documents that multiple
onscreen scroll views with `scrollsToTop` enabled prevent the iPhone gesture.
The extra Workloop detector and custom navigation channel have therefore been
removed. The existing shared registry now receives Flutter's public
`WidgetsBindingObserver.handleStatusBarTap` callback, with observer registration
and cleanup bound to the widget lifecycle. Stripe's native bridge is unchanged.

Tests now send the actual `flutter/status_bar` JSON `handleScrollToTop` message,
not Workloop's former private message. Including realistic phone safe areas
exposed a second conflict: Flutter's nested Work `Scaffold` also handled that
message and scrolled its shared primary controller, moving hidden Notes to zero.
That nested scaffold now sets `primary: false`; its own `SafeArea` and Workloop's
visible-section handler remain in place. No framework or private UIKit classes
were modified.

The final navigation/Work/shared-UI batch passed **36 tests**, including Clients
reselection, the real framework callback, retained Work section selection, and
hidden Notes scroll preservation. Evidence:
`/tmp/workloop-native-status-bar-after.log` (captured hidden-position failure)
and `/tmp/workloop-native-status-bar-final.log` (all passing). Physical status-bar
behavior must still be checked after rebuilding these Swift/Dart changes; the
successful Dart callback is not a substitute for UIKit/device delivery evidence.

Sources: [Flutter engine at the installed framework revision](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm#L524),
[Flutter's supported status-bar observer](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/handleStatusBarTap.html),
and [Apple's scroll-to-top ownership rule](https://developer.apple.com/documentation/uikit/uiscrollview/scrollstotop?changes=_6).

### Owner refinement — remove nested content cards

The latest owner instruction is one outer frame per grouped content section.
The empty Client Overview Next booking row is now flat inside its existing
panel. A source composition audit also found and flattened the rows in device
contacts, device calendar, CSV and text-file import previews. The Confirm
booking sheet's empty request summary now uses plain text inside its existing
frame instead of embedding another rounded hint card. The existing row
selection, duplicate warnings, import actions and request confirmation logic
are unchanged.

The audit covered shared content frames plus their compositions in Today,
Business, More, Money, notifications, task details, profile/public booking,
authentication/onboarding, appearance/legal screens and imports. Today attention
and Business/More grouped rows were already flat. Public service choices,
Money graphics, import source launchers and notification status surfaces are
standalone content surfaces; their boundaries remain. Fields, segmented
controls, checkboxes, action buttons, status badges and small icon fields also
retain their useful boundaries. Client Overview and email settings were
reviewed by the coordinating agent; appointment detail and the manual WhatsApp
flow remain under the separate feature review.

These are local presentation changes. No new test harness was introduced for
the four row-style flags. The integrated visual review, existing suite and
native rebuild must include these changes before treating earlier build results
as evidence for the final appearance.
## Final combined local build: WhatsApp, flat content rows and native scrolling

The subsequent combined pass is built and installed. The complete Flutter
suite passed **658 tests** (six configuration skips), and **7** payment-enabled
tests passed separately. Whole-project analysis, formatting and diff checks
passed. Signed iOS profile 1.0.0 (12), 74.0 MB, and Android profile APK,
162.9 MB, both built; the iPhone and isolated Android emulator both accepted
installation and launch. This supersedes earlier source/build counts above.

Physical iPhone Mirroring verification confirmed the reported Aneeka empty
booking section has a single frame, the actual clock/status-bar tap returns
Clients to the top, and reselecting Clients does the same. The new WhatsApp
action is visible in a real saved upcoming booking. Inspection of the external
WhatsApp draft is awaiting reconnection after Mirroring disconnected; no
message has been sent. Full details, limitations and logs are in
`2026-09-05-manual-whatsapp-reminders.md`.

The earlier SMS implementation remains disabled and its unused settings/client
permission entry points are removed from the everyday UI. Automated emails
continue independently. Google public sign-in and verified consent branding
are now published in Google Auth Platform; remaining native provider journey
limits are recorded in `2026-09-05-auth-access-methods.md`.

No TestFlight upload, Play upload, paid sender activation or live customer
message was performed. Suggested combined commit message:
`Polish app navigation and content frames; add safe manual WhatsApp reminders`.
