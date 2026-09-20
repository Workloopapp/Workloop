# Settings and notification audit — 5 September 2026

## Outcome and release status

Settings now separates the owner's phone alerts, customer reminders and emails
from Workloop. Account, privacy, appearance and maps controls use clear grouped
rows, with visible loading/failure states and safer asynchronous actions. The
approved Quiet + Warm identity is preserved; this is a refinement of the
existing app and workflows.

The audit also repaired client notification initialization, account changes,
deferred navigation and retry handling, plus two reviewed server delivery
boundaries. The two database migrations are deployed. The revised mobile
screens are local source, **not a new TestFlight or Google Play release**.
The owner's TestFlight hold remains in force.

At this report's handoff, the final whole-app test rerun, new iOS/Android builds,
physical visual checks and current Firebase/FCM setup verification are pending
the integrator's final evidence. Earlier build/device receipts must not be
represented as verification of this settings revision.

## Findings resolved

| Finding | Resulting behavior |
| --- | --- |
| Owner alerts, customer reminders and marketing emails shared one long settings flow. | Three clearly named destinations; each email screen loads only its own data. A failing customer-settings fetch does not break Workloop email preferences, or vice versa. |
| Privacy opened the top of Account, away from the requested controls. | Privacy & data opens directly to export and deletion. Account contains personal details, sign-in security and sign-out. |
| “Master notifications” implied it disabled every channel. | Business updates controls incoming business activity and related push alerts. Personal device reminders and both email audiences remain separate. Child business controls are visibly disabled when paused, while saved choices are retained. |
| Quiet Sundays looked independent of the morning overview. | Skip Sunday overview depends on Morning overview. It does not silently disable every Sunday alert or personal reminder. |
| Stored options had no current producer or misleading scheduling semantics. | Unused `no_show`, `lead_followup`, `weekly_summary` and ambiguous `task_due_morning` controls are not exposed. Saved data is preserved. Task reminders are chosen inside each task. |
| Enabling a local booking reminder depended on remote push setup succeeding. | The local 15-minute reminder checks local notification permission and saves independently of Firebase/remote registration. |
| Device permission was confused with delivery readiness. | Checking, denied, unavailable and failed states are explicit. Allowed permission is separate from server registration. Registration can be connecting, retrying or failed without claiming delivery. Phone settings has a direct native action and an honest failed-handoff fallback. |
| Name saving allowed repeated submission; failures and account changes could leave stale UI. | Saves are guarded, inputs/cancel/back are disabled during submission, failed drafts remain available, and owned account sheets are removed on account change. Long personal details wrap; the email address is selectable. |
| Password UI assumed every account already had a password. | Set or change password works with the existing email-security-code flow without inferring a password from an email identity. Fields are labelled, requirements are visible, and code retry, duplicate-save prevention and cancellation cleanup are explicit. |
| Sign-out closed its sheet before errors and could act after account cleanup raced another sign-in. | Sign-out is explicitly for this device, uses the existing expected-user guard, and keeps failed attempts retryable. |
| Export could reach the native picker after leaving the page or changing account/workspace. | The original account/workspace and current route are rechecked before the save handoff. Incomplete exports save nothing. Latest feedback replaces queued stale success messages. |
| Deletion explanation described backend implementation rather than consequences. | It explains immediate loss of access after acceptance, subsequent permanent deletion, export-before-deletion and possible retention. Optional local draft cleanup cannot turn an accepted request into a reported request failure. |
| Map preferences could look saved when reading/writing failed. | Loading, load retry, failed-save feedback and the actual persisted choice are explicit. |
| Maps chooser overflowed by 542 pixels at 320 × 568 with 2× text. | The shared chooser is scroll-controlled and scrollable. The regression now reaches Google Maps and verifies that the choice is actually saved. |
| Appearance could be changed before initial hydration or repeatedly while saving. | Choices wait for the initial read and disable during saves; failed persistence restores the preceding appearance. |
| Support and calendar labels implied technical or unsupported behavior. | Support offers app information without client data. Calendar export clearly creates a snapshot; it does not claim ongoing two-way sync. |

## Screen intent and navigation

All destinations use the existing Navigator/GoRouter structure and shared opaque
page/back presentation. These are settings entry points, not new product modules.

| Settings entry | Opens | Purpose and boundary |
| --- | --- | --- |
| Owner name/account identity | Account | First name, email, password, two-step verification and sign out on this device. |
| Your notifications | Owner notification preferences | Permission/registration status, Phone settings, Activity inbox, business updates, quiet hours and personal 15-minute booking reminders. |
| Activity inbox inside Your notifications | Existing Notifications screen | Review incoming activity; historical unread status is not a new task or proof that an action remains outstanding. |
| Customer reminders | Customer reminder settings | Existing automatic booking emails, business contact details and manual WhatsApp guidance. No Workloop marketing preference fetch. |
| Emails from Workloop | Workloop email preferences | Getting-started help, business tips and updates. No customer reminder-settings fetch. |
| App appearance | Appearance | System, Light or Dark, saved on the current device. |
| Maps & calendar | App preferences | Preferred maps app and the existing calendar-file export. |
| Getting started | Existing resumable guide | Continue/replay workflow guidance without generating demonstration records. |
| Help & support | Support | Contact support, copy safe app information, privacy policy, terms and version. |
| Import data | Existing import flow | Existing contacts/calendar/file imports; no new import behavior in this pass. |
| Privacy & data | Data-only account view | Export the workspace or request account deletion directly. |

Customer emails continue to provide the business's direct contact details.
Manual WhatsApp remains an owner-reviewed draft: the owner checks the message
and sending account, then taps Send in WhatsApp. No automatic WhatsApp sender,
SMS activation, paid messaging API or new customer enrollment was added.

## Files changed and why

The working tree contains earlier authorized work. This inventory describes this
settings/notification pass; it is not a claim that every current Git diff began
with this audit.

| Files | Reason |
| --- | --- |
| `lib/features/settings/settings_screen.dart` | Grouped settings hub and distinct destinations; returning from a destination rebuilds the screen without recreating shared auth dependencies. |
| `lib/features/settings/widgets/settings_account_tab.dart` | Account/data-only presentations, accessible forms, guarded saves, scoped sign-out, export ownership/navigation checks and plain deletion consequences. |
| `lib/features/settings/widgets/settings_app_tab.dart`; `lib/shared/providers/maps_preference_provider.dart`; `lib/shared/utils/maps_launcher.dart` | Persisted map-state loading/retry, save feedback, honest calendar-export copy and responsive maps chooser. |
| `lib/features/settings/widgets/settings_appearance_view.dart` | Flat appearance choices, initial-load/write guard and failed-save feedback using the existing notifier rollback. |
| `lib/features/settings/customer_reminders_screen.dart`; `lib/features/settings/widgets/email_settings_section.dart` | Separate customer and Workloop email settings; avoid fetching unrelated settings. |
| `lib/features/settings/support_screen.dart` | Clearer app-information/support wording and feedback. |
| `lib/features/notifications/notifications_screen.dart` | Owner-specific preference groups, dependencies, permission/registration presentation, native settings recovery and independent local reminder activation. |
| `lib/shared/notifications/remote_push_service.dart`; `remote_push_bootstrap.dart`; `remote_push_registration.dart` in the same directory | Idempotent initialization/listeners, retryable registration state, identity-aware bootstrap, deferred tap completion and native settings bridge. |
| `lib/shared/notifications/local_reminder_service.dart`; `local_reminder_bootstrap.dart`; `local_reminder_plan.dart` in the same directory | Retry failed initialization/reconciliation, separate account/workspace plans, clear obsolete reminders and preserve task wording/calendar-day timing across DST. |
| `ios/Runner/AppDelegate.swift`; `android/app/src/main/kotlin/com/ismaeel/workloop/MainActivity.kt` | Native `workloop/notifications` → `openSettings` handlers. Source presence is not physical-device handoff proof. |
| `supabase/migrations/20260905223221_recheck_push_preferences_before_delivery.sql`; `20260905223935_require_active_session_for_push_registration.sql` in the same directory; `supabase/schema_contract.sql` | Current delivery-policy checks and an actual Auth-session binding for device tokens, preserving existing membership/MFA boundaries. |
| `test/settings_account_safety_test.dart`; `test/settings_onboarding_recovery_test.dart` | Account failure/retry, duplicate/back guards, stale-account/export protection, deletion cleanup and compact keyboard layouts. |
| `test/settings_navigation_preferences_test.dart`; `test/ui_audit_states_test.dart`; `test/beta_ui_remediation_test.dart` | Real route/persistence/permission behavior, independent email fetches, notification dependencies, exact retry target and accessible large-text selection. |
| `test/notification_service_reliability_test.dart`; `test/notification_bootstrap_reliability_test.dart`; existing reminder-plan/route tests | Plugin-channel/service/bootstrap regressions, including sign-in without resume and deferred notification navigation. |
| `supabase/tests/database/022_push_dispatch_preferences.test.sql`; `023_push_registration_sessions.test.sql` and updated 009/016 fixtures | Current preferences, active-session ownership, revoked/expired sessions and legacy-token compatibility. |
| `test/golden/files/settings-dark-only.png`; `settings-light.png` in the same directory | Visually reviewed appearance-hub baselines updated for the intended grouped-row design. |

Detailed client and server implementation/evidence remain in
[notification client reliability](2026-09-05-notification-client-reliability.md)
and [push server verification](2026-09-05-push-server-reliability.md).

## Verification completed

| Check | Evidence |
| --- | --- |
| Account focused batch | **17 passed**: 14 new safety tests plus three existing settings/onboarding recovery tests. `/tmp/workloop-account-settings-tests.log`. |
| Settings/preferences batch | **30 passed**: 20 new behavioral tests plus ten existing UI/beta cases. `/tmp/workloop-settings-preferences-tests.log`. |
| Notification client batch | **23 passed**, documented in the client report; `/tmp/workloop-push-reliability-tests.log`. This is client/service testing, not 23 physical delivery checks. |
| Analysis | Full `flutter analyze` reported no issues; `/tmp/workloop-settings-full-analyze.log`. Scoped analysis and changed-file whitespace checks also passed. |
| First whole-app run | **703 passed, six configuration skips, two expected golden failures**. Both failures were the Settings light/dark appearance surfaces; `/tmp/workloop-settings-full-tests.log`. |
| Golden review/update | Integrator visually reviewed the two intended Settings changes and updated only those baselines. Their focused run passed **2 tests**; `/tmp/workloop-settings-goldens-update.log`. |
| Final whole-app rerun | **Pending at this report's handoff**. The expected 705-test passing total must not be stated as achieved until the run finishes. Evidence target: `/tmp/workloop-settings-final-tests.log`. |
| Focused database verification | **129 assertions** across push suites 009/016/022/023. |
| Full database replay | **91 migrations, 24 suites, 647 assertions passed**; real PostgreSQL semantics through PGlite/pgTAP, with Auth/cron/vault fixtures as documented in the server report. |
| Deployed server changes | Both named migrations applied and function bodies read back against source. Advisor count remained 29 with no new findings. No synthetic provider pushes or real preference mutations were performed during that verification. |

The UI tests exercise real widgets and notifiers, delayed/failing storage and
repository fakes, and mocked installed plugin/native channels. They verify
intended state and handoff calls, not real inbox or lock-screen delivery.

## Pending integration and operational checks

The integrator should append final results here rather than replacing earlier
receipts or inferring outcomes from source.

- Final full-suite result, relevant enabled-payment checks, final analysis and
  any additional reviewed golden evidence.
- Fresh iOS and Android builds for this exact source; install/launch receipts
  and settings/navigation visual checks on actual target devices.
- Native Phone settings round-trip and notification permission refresh;
  foreground/background/terminated receipt and valid tap destinations.
- Current Firebase/FCM setup and a newly registered eligible device session.
  At the server report's **22:40 UTC / 23:40 BST** readback,
  `FCM_SERVICE_ACCOUNT_JSON` was absent, and the only iOS sandbox token required
  fresh registration after the session-binding migration. Subsequent setup may
  change this; that snapshot is not a final provider verdict.
- Distinguish development-signed iOS from production/TestFlight APNs, and
  emulator checks from a physical Android phone. The owner has no Android
  phone available for physical validation.

Enqueue/claim guards cannot recall a notification already handed to Apple or
Google, and a provider timeout cannot prove exactly-once delivery. An active
worker and an HTTP 200 response do not by themselves prove a device received a
message. TestFlight and Play publication remain outside this report.

Suggested commit: `Clarify settings and harden notification preferences and delivery`

## 2026-09-05 follow-up — Money hierarchy and long histories

The owner reported that a long list of received payments pushed Cash movement,
the weekly target and Get paid with Workloop too far down the screen. Money now
places its overview and collection tools before history, so their position is
independent of how many payments exist.

| Section | Resulting order and behavior |
| --- | --- |
| Made | Period selector, total received, cash movement, weekly/monthly target, payment setup, then received-payment history. Initially show the latest five matching payments. View all N payments reveals every matching record; Show recent payments returns to five. |
| Spent | Period selector, total spent, category totals, then the five most recent expenses. The same disclosure reaches the complete matching history. |
| Owed | Preserve the complete overdue-first outstanding-payment queue and existing collection/mark-received actions. Outstanding work is not hidden behind recent-history disclosure. |
| Custom dates | Keep payment setup available independently of the weekly/monthly target. Expand only records in the chosen date range. |

The disclosure sits **above** the transaction rows. Expanding or collapsing
retains its position and the scroll offset; it does not move the owner to a new
screen or unexpectedly scroll them down the history. Changing Week, Month or
Custom dates restores the recent view. Totals and cash movement always include
all matching records, and received payments continue to be filtered/sorted by
their received date. A payment deep link still opens its actual record even if
it is outside the visible five or the selected period.

### Files and verification

| File | Reason |
| --- | --- |
| `lib/features/finance/finance_screen.dart` | Reorder overview/tools, add recent/full history disclosure without new providers/routes, reset disclosure for a new period and separate Custom-date payment setup from target visibility. |
| `test/money_history_hierarchy_test.dart` | Eleven new behavioral regressions for 30-payment histories, complete totals/chart values, stable disclosure position, received-date filters, Custom periods, older payment/expense editing, settings retry, complete Owed queue, deep links and 320-pixel/2×-text accessibility. |
| `test/feature_hierarchy_refinement_test.dart` | Update the earlier expense-first expectation for the owner's new overview-before-history ordering. |
| `test/golden/files/money-empty.png`; `test/golden/files/money-populated-light.png` | Integrator visually reviewed the intended ordering/spacing changes and updated these two Money baselines only. |

- **40 focused tests passed**, including the 11 new cases plus existing Money,
  creation, accessibility, provider isolation, finance failure and hierarchy
  coverage. Evidence: `/tmp/workloop-money-hierarchy-tests.log`.
- Scoped Dart analysis reported no issues; changed-file whitespace checks
  passed.
- **2 Money golden tests passed** after the integrator's visual review/update.
  Evidence: `/tmp/workloop-money-golden-update.log`.
- The **final combined whole-app suite, exact-source iOS/Android builds and
  device verification remain pending** the last notification permission-event
  integration. This section does not claim that the earlier expected 705-test
  rerun, newer combined count or final builds have finished.

This pass changes presentation only. Existing records, finance calculations,
repositories, period rules, edit/delete actions and payment activation gates
remain in place. It does not enable Stripe, send a payment request or activate
SMS/automatic WhatsApp. The expanded history still renders all matching rows
from the existing complete provider collection; this is not server pagination,
and very large expanded histories retain that existing rendering cost. The
initial compact view limits row construction to five without concealing the
available full history. Native visual/accessibility checks supplement the widget
coverage before release; TestFlight remains on hold.

Suggested Money commit: `Improve Money overview and transaction history hierarchy`

## Final integration receipt — 6 September 2026, 00:09 BST

This receipt resolves the pending test/build entries above. It covers the
combined Settings, notification permission-event and Money hierarchy source.

| Check | Final evidence |
| --- | --- |
| Full analysis | No issues found. `/tmp/workloop-settings-money-final-analyze.log`. |
| Whole app | **718 passed, six configuration skips**. `/tmp/workloop-settings-money-verified-tests.log`. |
| Payment-enabled follow-up | **18 passed** with `PAYMENT_COLLECTION_ENABLED=true` and `TAP_TO_PAY_ENABLED=false`, covering the six gated checks plus Money history behavior. `/tmp/workloop-settings-money-payments-enabled-tests.log`. |
| Database | **647 assertions passed** across 91 migrations and 24 suites, including the 129 focused push assertions reported above. |
| Final iOS profile | Built successfully, 74.1 MB. `/tmp/workloop-settings-money-ios-build.log`. The signed `aps-environment` entitlement is `development`, matching the explicit `APNS_ENVIRONMENT=sandbox` build define. |
| Final Android profile | Built successfully, 163.1 MB. `/tmp/workloop-settings-money-android-build.log`. This is compilation/package evidence, not Android push delivery. |
| Physical iPhone install | Final combined app installed at 00:08 BST and launched successfully at **00:08:45 BST**, 6 September. `/tmp/workloop-settings-money-iphone-install.log` and `/tmp/workloop-settings-money-iphone-launch.log`. Local version remains `1.0.0+12`; no store upload was made. |
| Whitespace | `git diff --check` passed. Existing unrelated dirty work remains intact. |

The final permission-event review found that granting permission through a task
or booking could leave Settings stale and defer remote registration until the
next resume. Both consumers now listen to the existing local permission event;
two regressions cover immediate status/registration refresh without another
permission prompt. The 45-test integration batch passed. One older whole-app
test fake lacked the existing `permissionChanges` getter; its fixture was
corrected, its 13-test suite passed, and the complete 718-test rerun above passed.
No production fallback was added to accommodate a broken fake.

The earlier iOS compilation failure for notification-settings availability was
fixed by using the SDK's iOS 16 availability boundary. The final build passed;
the existing `device_calendar` and `flutter_local_notifications` Swift Package
Manager compatibility notices remain future dependency-maintenance work.

Artifact SHA-256 receipts:

- iOS `Runner` executable: `20cbdaa3a599c3de8fd80287babf302b1c5e24a8791af532cde14affbc7c425c`.
- Android profile APK: `2a25dc24e2837c15502683a24689410731470b5cce0a660664699be1cc0d771d`.

### Provider decision and remaining release checks

Google's `iam.disableServiceAccountKeyCreation` organisation policy blocked the
Android sender credential. The owner explicitly chose **Keep the policy; leave
Android setup pending**. No exception was applied and no credential was created
or installed in Supabase. The dedicated `workloop-push-sender` service account
exists with `roles/firebasecloudmessaging.admin`, with zero keys; Android remote
push remains unconfigured. This does not activate an SMS service or ad spend.

The iPhone did successfully register its active owner session after the server
change. The final combined build registered at **23:08:46 UTC / 00:08:46 BST**,
one second after launch: one enabled, bound and eligible owner sandbox token;
no pending deliveries or expired leases; latest worker HTTP 200 with no
failures. The server report contains the readback. Registration is distinct from
actual delivery. iPhone Mirroring reported that the phone was in use, so the
final native Settings round-trip, visible background/terminated notification
and notification-tap navigation have **not** been observed in this pass. No
synthetic notification was sent and no quiet-hour preference was changed.

Before a release, complete the physical iPhone delivery/tap checks, verify
production APNs with the eventual TestFlight build, and finish Android provider
configuration and real-device delivery separately. Existing devices with old
unbound registrations need to reopen/resume Workloop to register their active
session. The latest app changes are installed locally on the owner's iPhone;
**TestFlight and Play uploads remain on hold**.

Suggested combined commit: `Polish settings and Money and harden notification delivery`
