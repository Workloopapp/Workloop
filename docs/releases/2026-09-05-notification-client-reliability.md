# Notification client reliability — 5 September 2026

This pass improves the existing Flutter remote-push and on-device reminder services. It does not publish a TestFlight build or establish that a notification has been delivered to a physical device.

## Confirmed defects repaired

- A bootstrap mounted while signed out did not watch the auth stream. Signing in could leave token registration and a deferred notification tap waiting for a later app resume. Both bootstraps now react to identity changes directly.
- Deferred notification navigation could stall on a settled screen: the second post-frame callback did not request a frame. Local and remote navigation now request the frame needed to complete the queued route. The login/cold-start widget regression reproduced the failure before this repair.
- Retrying a failed Firebase cold-start lookup attached duplicate message/tap/token listeners. Listener attachment is now idempotent, and token-stream errors trigger a retry signal instead of escaping as uncaught errors. Cold-start routes are consumed once, including initialization recovered by a later registration attempt.
- Local initialization cached a failed Future permanently. It can now retry. Cancellation failures are counted along with scheduling failures; partial reconciliation is retried instead of being marked complete.
- Local reminder reconciliation now belongs to a specific account and workspace. An account change interrupts subsequent platform operations, clears old scheduled reminders even if the new workspace fails to load, and prevents old results from becoming the successful current fingerprint. Signed-out startup and resume also reconcile an empty plan.
- Task reminder wording previously described the day setup occurred rather than the day the notification will fire. Same-day and day-before reminders now use the correct future wording. Calendar-day arithmetic preserves the selected local 09:00 across daylight-saving changes.

## Delivery and settings semantics

`remotePushRegistrationStatusProvider` exposes `idle`, `registering`, `registered`, `retrying`, and `failed`. **Registered means the server accepted this device token. It is not proof of APNs/FCM delivery.** Transient token/registration failures use bounded retries at 1, 2, 4, and 8 seconds; resume and permission/token events can retry again. Token and registration calls have a 15-second timeout so a stalled lookup does not block all subsequent registration work.

`RemotePushService.openNotificationSettings()` uses the existing native-channel pattern (`workloop/notifications`, `openSettings`) and reports unsupported/failed opening rather than claiming success. The platform handlers and settings-screen presentation are integrated separately by the parent task. Opening system settings does not require Firebase configuration.

Foreground remote messages continue to refresh the canonical workspace data. This service does not add a duplicate foreground alert. Notification routes retain the existing allowlist and opaque identifiers; local lock-screen text remains generic.

Business updates and local task/booking reminders are separate settings. This pass does not silently turn the business-update preference into a master switch for reminders the owner explicitly scheduled.

## Verification

`flutter test --no-pub --dart-define-from-file=.env` passed **23 tests** across:

- `test/notification_service_reliability_test.dart`: real installed plugin method channels, initialization retry, single listener/tap delivery, token-stream errors, cancellation/scheduling failures, interrupted reconcile, late permission responses, and opening system settings.
- `test/notification_bootstrap_reliability_test.dart`: sign-in without resume, deferred cold-start routing, transient registration retry, token refresh, signout while token lookup is pending, partial local failure retry, switching accounts while scheduling, and signed-out cleanup.
- `test/local_reminder_plan_test.dart`: timing, wording, eligibility, stable identifiers, and pending-reminder limit.
- `test/notification_route_test.dart`: exact permitted entity routes and invalid-route handling.

Scoped Dart analysis reports no issues; scoped `git diff --check` passes. Evidence: `/tmp/workloop-push-reliability-tests.log` and `/tmp/workloop-push-reliability-analyze.log`.

## Integration and remaining live checks

A client cannot revoke an RPC already submitted before signout by ignoring its eventual result. The backend audit identified the need to bind registration/delivery to an active auth session and recheck current preferences; that work is owned and validated separately in the backend task. No server migration is claimed as complete by this client note.

Physical foreground, background, cold-start and warm-tap checks remain necessary on development-signed iOS, production/TestFlight iOS, and Android. Provider credentials, APNs signing environment, phone notification permission, OS delivery policy and valid current token registration all remain prerequisites. No customer notifications were sent by these tests.

Primary references consulted: [Firebase Flutter client setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) and [receiving Flutter messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages). In particular, Apple token availability is asynchronous, and cold-start `getInitialMessage` and warm `onMessageOpenedApp` handling are separate paths.

## Integration follow-up

After the physical iPhone installation, the parent task verified that the owner's fresh authenticated session registered the device at **22:50:43 UTC on 5 September 2026**. This is current-session registration evidence, not proof of notification delivery or a notification tap opening the correct screen.

Read-only integration review found the native settings handoff consistent with the Dart contract: iOS 16+ opens notification settings and older iOS opens app settings; Android opens the app's notification settings with its package identifier. Both report failure through the existing UI fallback.

A final permission-event gap was repaired: granting the shared OS notification permission from a task or personal booking reminder now updates the visible device status and wakes remote registration without requiring app resume. This does not change saved business preferences or request permission a second time from those reminder flows. Separate widget regressions cover the visible status and initial push registration.

The session guard is now present in `20260905223935_require_active_session_for_push_registration.sql`. Independent source review confirmed existing membership/MFA enforcement, same-user active-session validation after the token lock, suppression of revoked/unbound sessions at enqueue/claim, and cancellation of obsolete leases on session rebinding, without new public Auth-table access. An alert already handed to an external push provider cannot be retracted by cancelling its database lease.

Follow-up verification passed **45 tests** across the five notification/settings files, including both permission-event regressions. Scoped analysis is clean. Evidence: `/tmp/workloop-push-permission-integration-tests.log` and `/tmp/workloop-push-permission-integration-analyze.log`. Final whole-app tests and native builds are run separately after integrating these last changes.
