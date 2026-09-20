# Notification settings clarity — 6 September 2026

## Request and scope

The owner asked for notification settings to make it obvious who receives each message and whether it appears in the app, on a phone, by email or through WhatsApp. This pass clarifies the existing controls and groups them by recipient. It does not introduce a new messaging system or change backend schema, provider configuration, saved defaults, notification generation rules or customer enrollment.

The revised Flutter source is not a store release. **TestFlight and Google Play uploads remain on hold.** Final integrated verification is pending the receipt below.

## Settings destinations

| Group | Exact destination label | Purpose |
| --- | --- | --- |
| For you | Your alerts | Business activity in the in-app inbox and through push, phone permission/status, local reminders and quiet hours. |
| For you | Emails to you | Emails sent by Workloop to the account holder, including the existing tips/updates choice and a separate explanation of essential account emails. |
| For your customers | Customer messages | Automatic booking reminder emails, business contact details shown in emails, and manual WhatsApp reminder guidance. |

The screens use the existing Quiet + Warm paper panels with flat content rows. Form controls retain their boundaries. Loading, retry and save-failure feedback remain explicit; errors inside a framed section do not add another content card.

## Recipient and channel matrix

| Control or section | Recipient and channel | Actual behavior and dependencies |
| --- | --- | --- |
| In-app inbox | The business owner, inside Workloop | Opens existing activity history. Phone permission is not required to read it. Existing rows remain when new business updates are paused. |
| Receive business updates (`all_notifications`) | The business owner: in-app inbox + business push | Keeps the existing coupled generation/delivery preference. Category choices below it are disabled while paused without erasing their saved values. Local reminders and emails remain separate. |
| Booking requests (`booking_request`) | The business owner: inbox + push | Covers new customer requests and requests waiting for a response. Requires business updates. |
| Confirmed bookings (`new_booking`) | The business owner: inbox + push | Covers the existing created/confirmed booking workflow, including bookings the owner enters. Requires business updates. |
| Payments received (`payment_received`) | The business owner: inbox + push | Existing booking or linked-payment workflows marking a payment paid. Copy does not promise notification coverage for every Stripe webhook payment. |
| Unpaid and overdue payments (`invoice_overdue`) | The business owner: inbox + push | Covers immediate outstanding-payment activity after completing a booking as unpaid, as well as overdue-invoice automation. |
| Morning overview (`morning_digest`) | The business owner: inbox + push | Existing daily overview around 07:00 in the business timezone. Requires business updates. |
| Skip Sunday overview (`quiet_sundays`) | The business owner: morning overview only | Depends on Morning overview and suppresses that Sunday overview. Other business updates remain eligible. |
| Phone reminders / 15 minutes before a booking (`appointment_reminder_15`) | The business owner: local phone notification | Existing scheduled-booking reminder; phone permission required. Task reminder choices remain inside each task. Choices sync with the workspace; each phone schedules its own alerts. This local delivery is separate from business push and does not send the customer a message. |
| Pause overnight alerts (`quiet_hours_enabled`) | The business owner: business push only | Holds business push from 21:00 to 07:00 in the business timezone. The inbox still updates immediately. Local phone reminders and emails retain their own timings. |
| Booking reminders / Email · Automatic | The business's customer: email | Existing 1-day, 2-hour and 1-hour choices in `customer_reminder_minutes`. Requires a valid customer email and an eligible booking; unsubscribe, suppression and the existing worker checks still apply. |
| Booking updates | The business's customer: service email | Confirmations and booking changes are explained separately from reminder timing choices. Stopping reminders does not cancel a booking. |
| WhatsApp reminders / Manual · You tap Send | The business's customer: WhatsApp | The owner opens a booking, checks the prepared message and sending account, and taps Send in WhatsApp. No automatic WhatsApp delivery is implied. |
| Workloop tips and updates | The account holder: email | Reflects the existing account email journey and suppression state. Essential account/security emails remain separate. A limited website welcome series is identified as such, rather than displayed as consent to ongoing account marketing. |

Business phone delivery still depends on supported app/provider configuration, phone permission, an eligible registered token, an active account/workspace session and the current delivery policy. Quiet hours and preference choices are rechecked before a queued business push is dispatched. Reading a notification can suppress a pending push; changing a preference does not delete historical inbox entries or recall a message already handed to its provider.

## Copy and state corrections

- **Recipient comes first.** The settings hub now separates For you from For your customers; each destination reiterates its audience and channel.
- **In-app and push are explicit.** Business activity is labelled “In-app inbox + push alerts.” Phone permission can be off while inbox history remains usable. Business updates is not described as an all-channel master switch.
- **Payment labels match the actual producers.** Confirmed bookings includes creation; Payments received describes marked-paid booking/linked-payment events; Unpaid and overdue payments includes the immediate pending-payment event.
- **Morning and quiet controls describe their real scope.** Skip Sunday overview is dependent on Morning overview. Quiet hours is labelled “Business push only”; Focus/Do Not Disturb is distinguished from Workloop's own schedule.
- **Local scheduling is not called a device-only preference.** The copy explains workspace-synced choices and schedules stored on each phone. Existing legacy preference values are preserved; no unused/ambiguous legacy control is reintroduced.
- **Registration is not proof of delivery.** Phone status retains checking, failed, allowed, denied and unsupported states, plus registration progress/retry/failure. The allowed/registered description says delivery also depends on the connection and Workloop's notification service; it does not claim a successful provider delivery.
- **The limited welcome series is distinguished from ongoing emails.** An active `program=welcome` displays “Welcome series only,” leaves the ongoing tips switch off and offers “Unsubscribe from welcome series.” Ongoing account emails require a deliberate switch action through the existing preference API; no silent program upgrade occurs while rendering settings.
- **Saved customer timings remain authoritative.** This pass does not replace existing empty timing selections with the new-workspace 24h/1h defaults. Reminder unsubscribe, delivery suppression and essential service emails remain distinct.

## Files and reasons

| File | Reason |
| --- | --- |
| `lib/features/settings/settings_screen.dart` | Recipient-based settings groups and the exact Your alerts, Emails to you and Customer messages destinations. |
| `lib/features/business/business_screen.dart` | Uses the same Customer messages label for the existing shortcut. |
| `lib/shared/widgets/workloop_quiet_warm.dart` | Supplies a transparent Material beneath interactive paper-panel content so switches and list tiles paint feedback correctly. |
| `lib/features/notifications/notifications_screen.dart` | Explicit inbox/push/local sections, accurate payment and quiet-hours descriptions, preserved dependent controls and cautious permission/registration wording. |
| `lib/features/settings/customer_reminders_screen.dart` | Renames the existing route presentation to Customer messages. |
| `lib/features/settings/widgets/email_settings_section.dart` | Separates automatic email and manual WhatsApp explanations, account/customer audiences and limited-welcome versus ongoing-account preferences; keeps existing save APIs and retry states. |
| `lib/features/settings/widgets/business_email_contact_settings.dart` | Consistent flat contact-details row and clearer description of the email/phone shown to customers. |
| `test/settings_navigation_preferences_test.dart`, `test/email_settings_section_test.dart` | Covers recipient separation, exact preference writes, dependent controls, permission states, retained values, failed/duplicate saves, limited welcome-series handling and small-screen accessibility. |
| `test/beta_ui_remediation_test.dart`, `test/core/theme/dark_only_theme_test.dart`, `test/booking_sms_controls_test.dart`, `test/feature_workflow_refinement_test.dart` | Keeps existing booking-language, first-frame appearance, customer-only fetch and permission-lifecycle checks aligned with the new labels and flat icon treatment. |
| `test/golden/notification_settings_golden_test.dart` and relevant settings golden fixtures | Twelve reviewed light/dark settings captures, including the lower phone-reminder/quiet-hours and manual-WhatsApp sections; the two existing hub goldens are updated after review. |

This file inventories the scoped clarity change. Other modifications in the shared dirty working tree came from earlier authorized work and are not attributed to this pass.

## Provider and release boundaries

The latest recorded provider decision remains unchanged: Android remote push is pending because Google's `iam.disableServiceAccountKeyCreation` policy blocks the required sender credential and the owner chose to keep that policy. This pass creates no key, installs no provider secret and changes no policy. Local Android reminders are a separate capability. The prior [settings/provider receipt](2026-09-05-settings-and-notifications.md) records that boundary; this report does not claim a fresh provider inspection.

The TestFlight hold remains in force. No TestFlight or Google Play upload, synthetic notification, customer email, WhatsApp message, SMS activation or campaign send is part of this clarity pass.

## Separate functional follow-up

Stripe webhook reconciliation updates payment state but does not currently produce the owner's `payment_received` notification. Existing notification producers are paid booking completion and linked-payment marking. The clarified copy describes that actual coverage. Adding a deduplicated, preference-aware Stripe payment notification is a separate workflow/backend change and has **not** been implemented by this settings pass.

## Verification — pending root final receipt

**Pending.** The parent integration task will append the exact final analysis, focused/full test counts, visual review, native build and device install/launch results. No earlier test count, build artifact or installation should be interpreted as final verification of this revision. Physical provider delivery and notification taps require their own evidence; compilation, phone permission and token registration are not substitutes.

Suggested commit message after the complete working tree is reviewed:

`Clarify notification settings by recipient and delivery channel`

## Final integration receipt — 6 September 2026, 01:24 BST

This receipt resolves the pending verification above and applies to this exact
Settings clarity revision. Existing unrelated dirty work has been preserved.

| Check | Final result |
| --- | --- |
| Full analysis | **No issues found.** `/tmp/workloop-settings-clarity-final-analyze.log`. |
| Whole app | **816 passed, six configuration skips.** Includes all golden suites. `/tmp/workloop-settings-clarity-verified-tests.log`. |
| Focused Settings behavior | **46 passed** across navigation/preferences and email settings, including 320px/2× text, failed and duplicate saves, recipient isolation and welcome-series handling. `/tmp/workloop-notification-settings-behavior.log`. |
| Integration with card collection enabled | **63 passed**, including the payment-enabled suites that cover the six configuration skips, plus the four updated legacy regression suites. `/tmp/workloop-settings-clarity-integration-tests.log`. |
| Visual review | Inspected all twelve new light/dark captures, including lower-page reminders/quiet hours and WhatsApp, before accepting the baselines. Inspected and updated the two existing Settings hub and two Business shortcut goldens; the final whole-app run matches all baselines. |
| iOS profile | **Built successfully, 74.1 MB**, signed and `codesign --verify --deep --strict` passed. Local version **1.0.0 (12)**, with sandbox APNs and card collection enabled. `/tmp/workloop-settings-clarity-ios-build.log`. |
| Android profile | **Built successfully, 163.1 MB**, with card collection enabled. This is compilation/package evidence, not Android push delivery. `/tmp/workloop-settings-clarity-android-build.log`. |
| Physical iPhone | Installed the new app at **01:22 BST**. Launch at **01:23:20 BST** was rejected with `RequestDenied / Locked`; the phone needs unlocking. `/tmp/workloop-settings-clarity-iphone-install.log` and `/tmp/workloop-settings-clarity-iphone-launch.log`. |
| Native visual check | iPhone Mirroring reported that the Mac was locked and could not unlock automatically. Final hands-on screens, phone-settings round-trip and actual push delivery/taps remain unobserved in this revision. No synthetic messages were sent. |
| Whitespace | `git diff --check` passed. |

The initial focused run exposed a real shared-panel interaction issue: native
list tiles and switches could paint beneath the paper decoration. Supplying
the transparent Material inside the panel fixes that issue without suppressing
Flutter's warning. The first full run then found four obsolete test assumptions
and the two intentional Business-label golden differences; those were updated
and the complete suite rerun successfully. The iOS build retains the existing
future Swift Package Manager compatibility notices for `device_calendar` and
`flutter_local_notifications`; it compiled successfully.

Artifact SHA-256:

- iOS `Runner`: `9638338ff6bc5e082b0cc1dd791aafbc2ca352a0f0eb081d4eba7c6e8b094e6a`.
- Android profile APK: `cfa6c78853cc7fa3087712e3b44910dd197df4ee2a7a175c4c28615e5e1752a3`.

No TestFlight/Play upload or backend deployment was made. Before release,
complete the physical screen and notification-delivery checks when the Mac and
phone are available; preserve the owner's Android credential-policy decision.
