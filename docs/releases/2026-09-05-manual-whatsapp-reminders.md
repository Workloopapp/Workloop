# Manual WhatsApp booking reminders — 5 September 2026

## Scope and current status

The owner authorized a manual WhatsApp reminder after pausing SMS for cost.
Implementation is complete in local source. This supersedes the earlier
feasibility-only decision for the manual booking action only. SMS stays off;
no Twilio account, sender, phone-auth activation or customer enrollment is
part of this change. Automated customer email reminders remain independent.

On an upcoming scheduled booking, **Send WhatsApp reminder** appears below the
booking's completion/cancellation actions. It opens a recipient-specific
WhatsApp draft using the saved client, business, service and booking time.
The owner checks the message and sending account, then presses Send in
WhatsApp. Workloop never marks the reminder as sent from an app-launch result.

The HTTPS link can open WhatsApp or its website. It cannot select or guarantee
a WhatsApp Business account when the device has multiple WhatsApp apps. If
opening fails, a flat inline preview offers **Copy reminder**. Copying requires
another explicit tap and fresh validation. Missing/invalid phone numbers offer
the existing **Open client** action so the owner can correct the record.

No paid messaging API is called. There is no automatic WhatsApp send,
scheduler, message outbox, server deployment, migration or database write.

## Implementation files and purpose

| File | Reason |
| --- | --- |
| `lib/shared/utils/whatsapp_reminder.dart` | Shared phone normalization, safely encoded recipient URL, scheduled/future eligibility, business-zone customer text and enriched detail snapshot conversion. |
| `lib/shared/providers/booking_whatsapp_reminder_provider.dart` | Injected URL launcher and clock; fresh scoped booking/client/business/settings reads with identity checks and a second booking/recipient check before handoff. |
| `lib/shared/repositories/appointments_repository.dart` | Adds a single-booking `getById(workspaceId, id)` read, retaining the existing rich/legacy schema fallback and explicit workspace boundary. |
| `lib/features/appointments/widgets/booking_whatsapp_reminder_action.dart` | Secondary booking action, preparation state, duplicate-tap protection, safe error recovery and flat inline copy fallback. |
| `lib/features/appointments/appointment_detail_screen.dart` | Places the action in the existing booking workflow; applies the complete fresh display snapshot without losing client names, multiple services or add-ons. |
| `lib/features/clients/client_detail_screen.dart` | Repairs the existing WhatsApp contact action: current client lookup, UK/global number normalization, current-account/route checks and honest launch errors. |
| `test/booking_whatsapp_reminder_test.dart` | New focused pure, repository, service and rendered-widget regressions, including an actual booking-detail integration case. |

## Guardrails and limits

- Only scheduled bookings strictly after the current instant qualify. Started,
  elapsed, cancelled, completed, no-show, deleted and unknown-status bookings
  do not open reminders.
- Data comes from current repository reads, not the contact name-only join or
  a previously visited screen. Both booking and client must belong to the
  selected workspace. Changed recipient, phone, name, start time or service
  during preparation blocks the stale draft.
- Account/workspace changes, disposal and another route covering the booking
  prevent a delayed handoff. The fallback belongs to the booking widget;
  it does not leave a separate root dialog containing customer data.
- UK mobile numbers beginning `07` are normalized to `+44`; explicit `+`/`00`
  international numbers are accepted. Ambiguous national numbers,
  extensions and combined numbers require correction. Syntactic validity
  does not prove that the number has a WhatsApp account.
- Customer times use the saved business timezone and include the calendar
  date/year. UK times show GMT/BST; other zones include a UTC offset to avoid
  ambiguous abbreviations. Missing/unrecognized timezone data blocks the
  draft instead of inventing a timezone or using the owner's travel timezone.
- The customer message contains booking context, not internal client/booking
  notes. Unknown service names are omitted rather than fabricated.
- Preparation and app launch have bounded waits. Failure does not fall back
  to stale cached data or an unaddressed sharing URL. Copy validates again.
- Opening WhatsApp is not sending or delivery evidence. Actual app/browser
  availability, the owner's sending account and the recipient's WhatsApp
  availability remain external conditions.

## Related reminder/navigation UI changes

The same owner decision removes inactive SMS controls from the everyday email
settings and client overview. `email_settings_section.dart` explains the manual
WhatsApp workflow, while `business_screen.dart` labels the customer-reminder
entry as email reminders and WhatsApp. Dormant SMS implementation and tests
remain available without enrolling customers or promising activation.

The accompanying client overview refinement removes a nested empty-state
card from Next booking and includes light/dark golden checks.
These related files are `lib/features/settings/widgets/email_settings_section.dart`,
`lib/features/business/business_screen.dart`,
`lib/features/clients/widgets/client_overview_tab.dart` and
`test/golden/client_detail_quiet_warm_golden_test.dart`.

## Verification

Focused final command, after `source scripts/dev_env.sh`:

```sh
flutter test --dart-define-from-file=.env \
  test/booking_whatsapp_reminder_test.dart \
  test/booking_status_commit_safety_test.dart \
  test/appointment_client_handoff_test.dart
```

**38 tests passed.** The log is
`/tmp/workloop-whatsapp-reminder-final.log`. Scoped Dart analysis reported
**no issues**, and `git diff --check` was clean.

Coverage includes special characters/emoji/newlines, international and UK
numbers, missing/invalid phones, midnight and daylight-saving folds, status
boundaries, current account/workspace/recipient, rescheduling during reads,
GET-only workspace/id query scoping, duplicate taps, failed launches, explicit
copy, route coverage/disposal, retry, 320-point/2× text layout and retention of
the real client, service bundle, add-ons and newest notes/price on booking
detail. Existing booking-save and linked-client navigation tests also pass.

Full-suite verification, final golden inspection, native builds and physical
WhatsApp handoff evidence are pending integration. TestFlight remains
explicitly on hold. No customer message was sent during these checks.

Suggested commit message: `Add safe manual WhatsApp booking reminders`.

## Integrated verification and installation

The complete Flutter suite passed **658 tests** with six configuration-dependent
skips. The separately enabled payment collection/email suite passed **7 tests**.
Whole-project `flutter analyze` reported no issues; formatting checked 291 files
without changes, and `git diff --check` passed. During integration, the two
Business screenshot expectations and one old SMS-label assertion were updated
to the approved WhatsApp wording after visual inspection; the complete suite
then passed again.

The final development-signed iOS profile build is 1.0.0 (12), 74.0 MB. It was
installed and launched on the owner's iPhone. The matching Android profile
APK is 162.9 MB and installed/launched on the isolated API 36 emulator. Phone
sign-in and browser Apple OAuth remain disabled by their release flags;
payment collection retains its existing enabled build configuration. No
TestFlight or Play upload occurred.

On the final iPhone build, the actual status-bar clock tap and active Clients
tab reselection both returned a scrolled list to the top. The exact Aneeka
client view from the owner's screenshot now displays the Next booking empty
row with one outer frame, without an inner rounded card. The manual WhatsApp
action is visible on Lewis Morgan's future booking, while the saved client,
service, price, date/time, location, notes and money sections remain intact.

Mirroring disconnected as the WhatsApp action was opened, before its external
draft could be inspected. The owner was asked to lock the phone again for
that final external handoff check. No message was sent. This is a pending
external-app observation, not a failed Flutter suite or proof of delivery.

Logs: `/tmp/workloop-whatsapp-final-full-suite-verified.log`,
`/tmp/workloop-whatsapp-final-payments-enabled.log`,
`/tmp/workloop-whatsapp-final-analyze.log`,
`/tmp/workloop-whatsapp-final-format.log`,
`/tmp/workloop-whatsapp-final-ios-build.log`,
`/tmp/workloop-whatsapp-final-android-build.log`, and the matching
`/tmp/workloop-whatsapp-final-iphone-*` / `android-*` install/launch logs.
