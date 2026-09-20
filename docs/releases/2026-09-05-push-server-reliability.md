# Push delivery server verification — 5 September 2026

Production project: `imtbyrvsonzvtddswbtb`. Last read-only health check:
**22:40 UTC / 23:40 BST**. This report covers the backend push audit and the two
reviewed database fixes. Flutter device behavior and Firebase configuration are
being verified separately. No synthetic notifications, provider pushes, user
preference changes or TestFlight uploads were performed during this server work.

## Changes applied

| Live migration | Purpose |
| --- | --- |
| `20260905223221_recheck_push_preferences_before_delivery` | Reapply current business-update preferences, read state and quiet hours when queued work is claimed. |
| `20260905223935_require_active_session_for_push_registration` | Bind provider tokens to a validated Auth session and prevent new enqueue/claims for signed-out, expired or unbound sessions. |

The first migration computes policy from the existing notification,
`notification_preferences` and business timezone. It adds no settings table.
Read or disabled-category alerts are terminally suppressed without consuming a
provider attempt. Quiet hours remain 21:00–07:00 in the business timezone;
deferred and retried work is checked again, including daylight-saving changes.
Quiet Sundays applies only to the Sunday morning brief. Device-scheduled booking
and task reminders remain independent of the business-update master switch.
Suppression preserves the existing in-app notification history.

The second migration adds nullable `push_tokens.auth_session_id`; the schema
contract is updated accordingly. Existing tokens receive no guessed session
backfill. Both existing public registration signatures remain compatible and
bind the real JWT session on the next authenticated registration. Registration
checks the session after waiting for the existing per-token advisory lock,
matches its owner and rejects missing, malformed, deleted or `not_after`-expired
sessions. Existing membership and MFA checks remain in place. This follows
Supabase's documented method for rejecting an otherwise unexpired access JWT
after sign-out: check its `session_id` against `auth.sessions`.
[Supabase session guidance](https://supabase.com/docs/guides/auth/sessions)

No Auth foreign keys or Auth-table triggers were introduced. The private session
helper is an invoker with execution revoked from public, anonymous,
authenticated and service roles; only the existing privileged function boundary
uses it. Neither Auth session records nor token values are exposed by a new API.
New business alerts do not enqueue for unbound/inactive tokens. Claims
terminally suppress already-queued work when the session has ended. Rebinding a
token to a different session cancels its former session's pending/claimed work,
even if the user and workspace are unchanged.

## Live readback

All changed function bodies exactly matched the reviewed migration source after
application. Public legacy/current registration wrappers remain invokers and
authenticated-only. Claim remains service-role-only. Registration, enqueue and
claim implementation owners are `postgres`; the new helper is an invoker.
Security advisors remained **29 before and after each migration**, with no new
or removed findings.

| Check | Observation |
| --- | --- |
| Shared worker | `drain-booking-confirmation-emails`, ACTIVE version 30; push is a job inside this existing worker. |
| Schedule | Active every minute; preceding audit found 1,440 successful scheduler runs in 24 hours. |
| Latest response | 22:40:00 UTC, HTTP 200, no timeout, `push.configured=true`, zero claimed/sent/failed/retried, empty failure list. |
| APNs configuration | All five required secret names present; values were not printed or persisted. |
| Android configuration | `FCM_SERVICE_ACCOUNT_JSON` absent at 22:40 UTC; separate provider setup may change this afterward. |
| Device bindings | One iOS sandbox token, no production iOS or Android token. Immediately after migration it was unbound and not eligible for delivery. |
| Delivery queue | At 22:39:54 UTC: 2 sent, 4 pending, 4 failed; no expired processing leases. Earliest pending time: 6 September 06:00 UTC / 07:00 BST. |
| Historical failures | Earlier aggregate inspection found four `apns_baddevicetoken` failures. No real provider retry was forced for this audit. |

The existing sandbox installation must resume/open and successfully register
again before its token becomes session-eligible. Unbound pending items will be
suppressed when claimed or when the token is rebound; they will not be silently
attached to an inferred session. The pending count increased independently while
this work was reviewed; this audit did not create those notification records.

### Subsequent device and Android configuration verification

The final profile build was installed and launched on the owner's iPhone. Its
real registration completed at **22:50:43 UTC / 23:50:43 BST**. Live readback at
22:51:41 UTC confirmed exactly one fresh owner-matched sandbox token, bound to
an active Auth session and eligible for delivery. The four former pending rows
were automatically suppressed as `device_session_changed` during registration.
There was then **no pending or processing push work**, two historical sent rows,
and eight failed/suppressed rows (four historical provider failures and four
session-change suppressions). This is live registration/queue evidence; a
physical notification has not yet been sent in this verification sequence.

The Google Cloud UI verification completed separately by the lead agent found
the organisation policy `iam.disableServiceAccountKeyCreation` prevents a
downloadable sender key. The owner explicitly declined an exception, so that
policy remains intact. A dedicated `workloop-push-sender` service account with
`roles/firebasecloudmessaging.admin` has been created, but it has **zero keys**;
no `FCM_SERVICE_ACCOUNT_JSON` secret was added or changed. Android remote-push
provider setup therefore remains pending. Account/role creation alone is not
evidence that Android delivery is configured or working.

## Automated verification

- Focused push verification: **129 assertions** across suites 009 (35),
  016 cross-platform (22), 022 preferences (38) and 023 sessions (34).
- Full database replay: **91 migrations, 24 suites, 647 assertions passed**.
- `git diff --check` passed.
- Existing push fixtures now contain real Auth session rows and JWT session
  claims; production code has no sessionless-fixture exemption.
- Regression cases include both API overloads, MFA, malformed/missing/foreign
  session IDs, revocation with a still-unexpired JWT, session lifetime expiry,
  signout between registration and claim, null legacy bindings, fresh sign-in,
  session rebinding and obsolete delivery leases. Preference tests cover every
  current category/legacy alias, master/read changes, London DST, a half-hour
  timezone, quiet-hour boundaries, retries, expired leases and a suppressed
  front-of-queue item followed by valid work in a one-item batch.

Local evidence:

- `/tmp/workloop-db-validation/push-session-full-20260905-results.json`
- `/tmp/workloop-push-session-full-db.log`
- `/tmp/workloop-db-validation/push-sessions-20260905-results.json`

The replay uses real PostgreSQL through PGlite with pgTAP. Auth table shapes and
JWT GUC readers, cron metadata and vault metadata are test fixtures; it does not
run GoTrue, validate JWT signatures, run a real cron daemon or exercise provider
network delivery. The harness added the observed `auth.sessions` shape rather
than changing Supabase's Auth schema. Migration filenames were reconciled to
their live receipts after applying; source bodies were unchanged.

## Remaining evidence limits

Session/preference checks apply at enqueue and claim. They cannot recall a push
already claimed and handed to Apple/Google. Provider timeouts can still produce
at-least-once delivery rather than an exactly-once guarantee. The session guard
checks ownership, presence and explicit `not_after`; Supabase continues to own
JWT validation and its broader refresh/inactivity policies.

Historical sandbox provider acceptance is not proof of current TestFlight,
Android, foreground/background/terminated delivery or correct notification taps.
Those require current registered devices and physical verification. An HTTP 200
worker response can contain per-job retry/failure counts; HTTP health alone is
not proof that a particular device received an alert.

The audit also identified stored preferences without an active notification
producer (`weekly_summary`, `no_show`, `lead_followup`). `task_due_morning`
currently gates immediate task-related inbox events; individual 09:00 device
task reminders are separate. UI wording/control changes for these findings are
owned by the parallel app improvement work, not these migrations.

## Final combined installation receipt — 6 September, 00:09 BST

The lead agent reported successful installation and launch of the final
combined Money hierarchy and notification-permission fix profile build at
**6 September 00:08:45 BST / 5 September 23:08:45 UTC**, with the development
APNs entitlement verified in the signed artifact.

The independent server readback at **23:09:21 UTC / 00:09:21 BST** recorded a
fresh registration at **23:08:46.271763 UTC**, immediately after that launch:

- App build reported by registration: **12**.
- Exactly one known-owner iOS sandbox device, provider-enabled, session-bound
  and eligible for delivery.
- No pending or processing push deliveries and no expired leases.
- Historical rows unchanged: two sent, four `apns_baddevicetoken` failures and
  four `device_session_changed` suppressions.
- Latest minute worker: **23:09:00 UTC**, HTTP 200, no timeout, configured push
  provider, zero claimed/sent/failed/retried and an empty failure list.

This is a second real client-to-server registration receipt for the final
installed build. The build number and timestamp are server observations; signed
artifact/source provenance belongs to the coordinating build report. Physical
banner delivery and tapping the banner remain unverified because the phone was
in use. No diagnostic push, quiet-hours override, schedule or customer-data
change was made for this receipt. The prepared owner-only test remains on hold
until an explicit send instruction after the app is backgrounded.
