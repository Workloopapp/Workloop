# Booking reminder settings — 12 September 2026

The owner found that **Customer messages** implied customer chat in Workloop.
The destination is now **Booking reminders**, with a calendar/clock icon and
**Automatic email · Manual WhatsApp** beneath it in Settings and Business.

The screen explains that customer conversations stay in email or WhatsApp.
Automatic email timing, separate booking updates/contact details, and manual
WhatsApp guidance each have a clear purpose within the existing paper panels.
Email contact editing also explains where replies go.

## Behavior

- The email section reports the number of selected reminders, including an
  explicit off state. This reports saved choices, not proof of delivery.
- **Turn off email reminders** clears all reminder times through the existing
  workspace-settings action. Individual switches enable only the chosen times.
  An existing empty selection stays empty when opening the screen.
- Failed writes keep the saved selection and show retry guidance. Pending
  writes disable conflicting timing changes and repeated bulk actions.
- Booking-update emails, business contact details and owner email preferences
  are independent of the reminder timing selection. No schema, enrollment,
  unsubscribe policy, provider configuration or delivery-worker changes.
- WhatsApp reminders remain prepared from an upcoming booking and sent by the
  owner in WhatsApp. Replies stay in WhatsApp.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/settings/settings_screen.dart`, `lib/features/business/business_screen.dart`, `lib/features/settings/customer_reminders_screen.dart` | Consistent destination name and reminder icon while retaining existing navigation. |
| `lib/features/settings/widgets/email_settings_section.dart` | Clear channel/scope copy, saved-selection summary, bulk off action, and separate updates/contact section using existing providers and controls. |
| `lib/features/settings/widgets/business_email_contact_settings.dart` | Explain customer contact details and replies outside Workloop. |
| `test/email_settings_section_test.dart` | Check bulk off, explicit re-enabling, saved off state, failure/retry, pending-write guards, preference isolation and compact large-text operation. |
| `test/settings_navigation_preferences_test.dart`, `test/booking_sms_controls_test.dart` | Exercise existing navigation with the new label. |
| `test/golden/notification_settings_golden_test.dart`, affected settings/customer/Business PNG baselines | Review light/dark presentation with current wording and controls. Existing snapshot filenames remain stable. |
| `docs/CurrentState.md`, `docs/DecisionsLog.md`, this receipt | Record the product wording decision and its verification without rewriting earlier history. |

## Verification

- `source scripts/dev_env.sh` before all Flutter commands.
- Focused settings/reminder checks: **73 passed**.
- Full `flutter test --dart-define-from-file=.env`: **1,330 passed, one skipped**.
  This includes the final bulk-off check at 320px with 2x text and the reviewed
  light/dark snapshots.
- Final `flutter analyze`: **no issues**. An intermediate run picked up six
  Reports style diagnostics during concurrent work; that task resolved them.
- `flutter build ios --profile --dart-define-from-file=.env`: **passed**, signed
  `build/ios/iphoneos/Runner.app`, reported **80.5 MB**.
- `git diff --check`: **passed**.

Ten affected light/dark baseline images were inspected before accepting the
wording/layout changes. A pre-edit source/test/baseline copy is stored locally
at `/tmp/workloop-booking-reminders-before`. The shared checkout contains earlier
and concurrent work; the separate Reports implementation is not attributed to
this task. Its later Business-row subtitle edit was preserved, visually reviewed
and included in the two shared Business baselines after the full test run.
Both Business golden checks then passed against the current shared screen.

## Limits and follow-up

This is local source work. There is no store upload or physical-device
installation in this task. Test the settings route and WhatsApp handoff on the
next combined device build. Provider delivery was not exercised and no real
customer messages were sent. Turning off reminders cannot recall an email
already accepted by its provider.

Suggested commit: `Clarify booking reminders and email controls`

## Follow-up — installed and launched on 12 September 2026

The owner subsequently requested installation on their phone. The signed
1.0.0 (19) profile app was copied to a stable temporary bundle and its signature
checked. The compiled app includes **Booking reminders**, **Turn off email
reminders**, and the explicit explanation that Workloop has no customer chat
inbox.

CoreDevice confirmed installation on Ismaeel's iPhone 15 Pro Max, followed by
successful launch of `com.ismaeel.workloop`. An initial wireless connection reset
cleared after device rediscovery. This supersedes the earlier no-install status;
there was no store upload. Installation and launch do not establish manual
settings-flow or customer-delivery QA.
