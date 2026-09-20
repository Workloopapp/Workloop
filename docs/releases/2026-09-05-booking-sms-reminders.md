# Booking reminder texts — deployed, sending disabled

Status: backend deployed with sending disabled on 5 September 2026. Supabase
`imtbyrvsonzvtddswbtb` contains the SMS migration as `20260905184546`; the SMS
endpoint is ACTIVE v1 and the existing email worker is ACTIVE v30. No Twilio
account or number was purchased, and no SMS was sent. Existing customer email
reminders continue independently. This is deployed infrastructure, not activated
carrier delivery.

## User workflow

Business → Customer reminders brings email and text timings together. The same
controls are available in Settings notification preferences. A business can
choose 24 hours, one hour, both, or neither once the server reports that SMS is
configured and enabled. Client Overview provides the separate customer permission
dialog and an edit action when the saved mobile is unsupported. New and
existing businesses start with neither selected. Each customer also needs a
supported mobile in international +44 format and explicit permission recorded by
the owner. A saved phone number, email preference, booking request or past
booking never implies SMS permission. The owner must confirm that the customer
agreed to booking reminder texts before enabling them for that exact number.

The initial supported destinations are UK mobile-format +44 numbers, excluding
070 personal numbers and 076 pager numbers except 07624. This is a bounded format
check, not proof that a number is assigned, reachable or owned by the customer.
Local 07 numbers must be entered as +44; country is never guessed. Foreign
numbers and UK landlines are unavailable initially.

Consent belongs to the customer record and exact normalized number. Formatting
changes preserve permission; a different number revokes it and cancels queued
texts. Restoring an older number requires fresh permission. Another customer
with the same number cannot inherit permission. The owner cannot override a
provider STOP. START removes the provider block but does not restore old business
permissions. With one shared reminder Messaging Service, STOP applies to
Workloop booking reminders from all businesses using that service; explain this
in the provider's confirmation/help text. It does not cancel bookings or emails.

## Trigger and delivery contract

The existing minute worker checks the actual saved appointment, business time
zone, current customer/number, both levels of opt-in, account-deletion state and
provider suppression. It sends only for scheduled future bookings. Each
appointment/start-time/interval can create one outbox record. Completed,
cancelled, rescheduled, disconnected and changed-number records fail the final
check immediately before submission.

There is a 15-minute due window, no backlog catch-up, and no instant reminder for
a booking created less than five minutes before its reminder became due. For
example, a booking created 30 minutes before starting will not generate a late
one-hour text. This avoids confirmation/reminder bursts. Settings changes and
consent changes do not replay old reminders. Expected timing is approximately
24 hours/one hour before the booking, subject to the worker and provider.

Texts identify Workloop and the business, show the actual local booking date/time
and business contact phone when available, and include STOP instructions. They
omit customer names, service titles, addresses, notes and promotional content.
Business discussions should use the business's direct contact details; this is
not an SMS inbox or two-way customer chat. Example:

> Workloop for Valet Studio: booking reminder, 5 Sept, 17:00 BST. Contact +44 7700 900999. Reply STOP to stop reminders.

The body is bounded to 200 UTF-16 code units; accented names can cause multiple
billed SMS segments. No promise of one paid segment is made.

The optional SMS job runs after all existing emails/alerts so a Twilio timeout
cannot delay those jobs. A batch contains at most five texts, each with a
10-second HTTP timeout. Pre-dispatch leases last two minutes. A definite 429
rejection can retry twice, with two-minute backoff and the original expiry.
Ambiguous network/5xx/malformed success results are marked uncertain, never
blindly retried. A crash after dispatch also becomes uncertain. A later signed
delivery callback can resolve uncertainty. Provider acceptance is recorded
separately from confirmed delivery.

Provider queue validity is capped at five minutes and never beyond the booking
start. This limits queueing, not an absolute handset-delivery guarantee. Global,
business and recipient rolling 24-hour caps default to 1,000/100/6 dispatch reservations,
respectively, and may be configured lower. Rejected attempts conservatively use
a reservation too. These are request limits rather than currency or segment budgets; provider spend alerts and limits are still required.

## Backend and app interface

Migration `20260905184546_booking_sms_reminders_and_consent.sql` adds:

- `workspace_settings.customer_sms_reminder_minutes`, initially empty and limited
  to 1440/60.
- Private contact permission, global provider-suppression and leased outbox tables.
  The outbox is necessary for deduplication, delivery evidence and retry safety;
  eligibility is computed from current booking data.
- A private 25-hour dispatch-usage ledger, without booking/customer foreign keys,
  prevents deleting bookings or businesses from resetting rolling usage caps. It
  contains only workspace UUID, SHA-256 recipient digest and reservation time.
  This is pseudonymous data, not anonymous data; raw numbers are not stored there.
  RLS and service-role-only grants protect it. The `workloop-sms-retention` SQL
  cron sweeps usage after 25 hours and outbox details after 90 days every 15 minutes,
  even when outbound provider sending is paused.
- Authenticated, workspace-scoped `get_booking_sms_consent(p_contact_id)` and
  `set_booking_sms_consent(p_contact_id,p_enabled,p_expected_phone)` RPCs. Both
  return `{phone, consented, provider_stopped}`. Existing membership, account
  deletion and MFA boundaries are respected.
- Service-role-only queue, dispatch, completion and provider-update RPCs. Tables
  have RLS, no app read access, and explicit function/table grants.

`POST /functions/v1/sms-booking-reminders` with a valid non-anonymous user bearer
and `{"action":"capabilities"}` returns availability, reason, supported region,
allowed intervals and permission requirement. The app must treat missing or
failed capability responses as unavailable, and preserve email settings.

The same function handles Twilio callbacks, so gateway JWT verification is off.
Provider routes instead require the official pinned Twilio SDK signature check
against the exact configured public URL plus unchanged query and all decoded
POST fields. This remains valid behind the Supabase proxy. Account/service IDs,
delivery UUIDs and message IDs are validated; duplicate fields and bad signatures
never write. Provider error 21610 also records STOP and revokes consent if the
inbound callback was missed. Status callbacks cannot downgrade delivered texts.

## Activation checklist for the owner/operator

1. Create and fund the actual Twilio account with approved business details.
   Set provider billing/spend alerts and restrict outbound geographic permissions
   to approved destinations. No activation/spend is authorized by this file.
2. Configure a dedicated, reply-capable reminder Messaging Service and sender.
   Enable **Advanced Opt-Out**, review STOP/START/HELP responses, and configure its
   inbound webhook as POST to the exact public function URL with
   `?action=inbound`. Phone-number redaction must not be enabled: it conflicts
   with Advanced Opt-Out.
3. Keep login codes separate, using the same Twilio account if desired but a
   distinct Supabase Auth Verify/service configuration. Reminder STOP must never
   suppress login verification. Provider capabilities and verified-email rules
   still gate phone sign-in separately.
4. The migration, webhook and updated worker are deployed with sends off.
   Review that deployment before activation, then set secrets only in the server
   environment:
   `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`,
   `TWILIO_REMINDER_MESSAGING_SERVICE_SID`, `TWILIO_SMS_WEBHOOK_BASE_URL`.
   The base URL has no query/fragment and ends in
   `/functions/v1/sms-booking-reminders`.
5. Keep `BOOKING_SMS_ENABLED=false` and `TWILIO_REMINDER_SERVICE_READY=false`
   until the sender/Advanced Opt-Out/region/billing configuration is verified.
   Both must be explicitly true to expose readiness and submit messages. Optional
   `BOOKING_SMS_GLOBAL_DAILY_LIMIT`, `BOOKING_SMS_WORKSPACE_DAILY_LIMIT` and
   `BOOKING_SMS_PHONE_DAILY_LIMIT` only lower their hard maxima. Invalid explicit limits (including zero) disable
   outgoing sends instead of silently using a larger default; signed STOP and
   delivery webhooks remain available.
6. Use an explicitly consented test recipient to verify actual delivery, timezone,
   STOP/START/HELP, callback routing, disabled settings, number changes,
   cancellation/rescheduling, and provider rejection before customer rollout.
   The same provider setup has not yet been proven on a real phone.

No credentials are included in Flutter or documentation. Webhook processing
continues while outbound sending is paused, provided credentials remain set.

## Privacy and retention

Twilio receives the mobile number, business name, booking date/time, optional
business contact phone and message text to deliver the reminder, plus technical
delivery metadata. The Workloop outbox stores recipient/booking/provider IDs,
timing, statuses and error codes for 90 days, then removes them during the next
15-minute retention sweep. The independent usage ledger keeps only workspace
UUID, recipient digest and reservation time for a 25-hour window before that
sweep removes it; this limited record survives deletion to prevent allowance
resets. Retention depends on the database scheduler continuing to run. It does not store the rendered body. Consent is retained with the
customer record; deletion cascades. Minimal phone suppression is retained to
honour STOP, even across business/customer deletion, until a valid provider START.
There is no analytics use or business-conversation storage from inbound messages.

Provider-standard message retention applies. The implementation does not request
paid message redaction or promise EU residency. The configured US1 API endpoint
is `api.twilio.com`; a regional move needs separate compatibility review for both
Messaging and Auth. Website/privacy and store disclosures must include Twilio as
an SMS delivery provider before enabling the feature for users. A secret-free
sample configuration is in `supabase/functions/.env.example`.

## Verification evidence

The migration is replayed with all current repository migrations in local
PostgreSQL 18.3 (PGlite 0.5.8 + pgTAP), using stubbed Auth readers and scheduler
metadata. All 89 current migrations replay and all 22 database suites pass (575 assertions,
including 72 SMS assertions and 19 verified-email onboarding assertions). The
isolated SMS suite covers access, intervals, current-state
eligibility, consent, STOP/21610, phone changes, leases, quotas, retries,
uncertainty and delivery transitions. This does not prove hosted GoTrue,
cron execution or carrier delivery.

Deno 2.9.4 typechecks pass for the SMS endpoint and existing scheduled worker.
Twelve TypeScript tests pass in Deno against original source and real Twilio 6.1.0
SDK with stubbed HTTP/RPC calls. The SDK reads environment variables on import,
so tests use the repository-standard `--allow-env` permission and make no network
requests. They cover disabled-by-default configuration, timezone and
privacy-safe content, queue validity, outcome classification, canonical proxy
signature validation, tamper rejection and opt-out processing. No tests send SMS.

The app's `test/booking_sms_controls_test.dart` adds 16 passing regressions for
unconfigured/undeployed/unknown availability, retry, independent 24-hour/one-hour
choices, missing settings, failed saves, explicit permission confirmation,
duplicate-save guards, changed/stale/unsupported numbers, provider STOP and the
exact contact/phone RPC payload. Unknown availability preserves saved choices
with an explicit unconfirmed status; it does not claim that sending stopped.
Confirmed unconfigured service displays disabled/off controls while keeping the
saved times. Client consent RPCs are not called when texting is unavailable.

The final focused app batch passed 30 tests: those 16 SMS tests plus the four
existing email-setting tests and ten screen-hierarchy regressions. Targeted Dart
analysis and `git diff --check` passed. These tests use fake repositories and HTTP
responses; actual hosted function availability, carrier delivery and physical
phone interactions still require the activation checks above.

## Read-only hosted verification — 5 September 2026, 18:48–18:49 UTC

- Project status is `ACTIVE_HEALTHY`, PostgreSQL 17.6.1.155. Hosted migration
  `20260905184546` is `booking_sms_reminders_and_consent`; the accompanying
  verified-email onboarding guard is `20260905184601`. The two new local source filenames
  were reconciled to these deployed timestamps without changing their SQL;
  unrelated migration history was preserved.
- `sms-booking-reminders` v1 and `drain-booking-confirmation-emails` v30 are ACTIVE.
  Both retain their intentional `verify_jwt=false` gateway setting; the endpoint
  checks user Auth/provider signatures itself, and the existing worker checks its
  private drain token.
- Unauthenticated and invalid-bearer capability requests returned 401. The
  unconfigured inbound/status webhook routes returned 503 with the provider-not-
  configured error. A worker request without its drain token returned 401. No
  authenticated worker invocation or provider send was manually triggered.
- The actual scheduled worker returned HTTP 200 at 18:47 and 18:48 UTC, `ok=true`,
  `failures=[]`, and SMS `{disabled:true,accepted:0,failed:0,uncertain:0,skipped:0}`.
  Its cron record shows 20 succeeded invocations in the preceding 20 minutes.
- Live counts were zero for SMS permissions, outbox records, usage reservations,
  and businesses with SMS timing enabled. The new retention job is active at
  `*/15 * * * *`; its first hosted execution had not occurred at this observation.
- All four private SMS tables have RLS enabled. Anonymous/authenticated roles have
  no SELECT or INSERT grant. Only authenticated users can invoke the scoped
  customer-permission wrappers; queue/dispatch/provider updates are service-only.
  The private phone-change trigger function cannot be executed directly by app,
  anonymous or service roles.
- The SMS-related security advisor notices are four informational
  [RLS enabled with no policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
  entries. That is intentional deny-by-default behaviour for service-only private
  tables, not a reason to add public/app read policies. SMS-related performance
  notices are informational [unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)
  on new empty tables. No missing-index advisor finding names an SMS table.
  Broader existing advisor notices were reported separately rather than hidden
  or changed as part of this verification.

The public checks prove the disabled/access-denied paths and the continuing
scheduled worker. They do not prove a signed-in capability response, configured
live Twilio signatures, actual STOP delivery or any carrier receipt. Those need
the legitimate provider setup and explicitly consented recipient described above.

## Additional adversarial review

The second review found and repaired two real gaps: deleting sent bookings could
reset usage caps because the queue cascades on deletion, and an invalid explicit
operator limit could fall back to a larger default. The independent usage ledger
and closed-on-invalid-limit configuration address those cases. Reservation and
current eligibility checks execute after the shared usage lock; a failed database
reservation never reaches Twilio.

Additional tests cover workspace/booking deletion with cap preservation, limits
shared across businesses for the same recipient, pre-dispatch lease expiry and
replacement, stale dispatch callbacks, a delivered callback arriving before the
worker's HTTP completion, customer permission removed after claim, retention
with outbound sending disabled, the duplicated clock hour at the autumn DST
change, shortened provider validity near booking start, and reservation failure.
The existing email and lifecycle database suites continue to pass.

The local database is single-connection PGlite: real simultaneous Postgres
sessions, live cron timing and real carrier delivery have not been exercised.
The locking and token checks were reviewed and their state transitions tested,
not proven under hosted concurrent load. A booking or opt-out change after a
request has already been handed to Twilio cannot retract an in-flight SMS; the
implementation checks current eligibility immediately before dispatch and limits
provider queue time. These operational limits should remain explicit in release
validation rather than promising every possible external race is eliminated.

### Follow-up: interruption and accessibility checks

The subsequent edge-case pass raised `booking_sms_controls_test.dart` to 24
passing tests and added a keyboard/large-text email-contact test. Its combined
communication/client batch passed 31 tests. These specifically exercise leaving
a screen during a settings write, disposal of the whole provider scope, changing
workspaces while an old write finishes, changing accounts while SMS permission
is being confirmed, retry after a failed save, and using the permission dialog
on a 320pt-wide phone with 1.6x text. The business contact form is also exercised
with a visible keyboard at 1.4x text.

Settings updates now own their successful cache invalidation at the provider
level, so leaving a route cannot leave old switches cached. Old workspace saves
do not invalidate a different workspace. A different signed-in user cannot
complete an earlier SMS consent confirmation. Permission and contact dialogs
scroll their titles and content together when space is constrained. No sending,
payment or carrier behaviour is inferred from these local UI checks.

## Sources checked 5 September 2026

- [Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy):
  permission, sender identification and opt-out requirements.
- [Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out):
  setup, STOP/START/HELP callbacks and provider responses.
- [Message resource](https://www.twilio.com/docs/messaging/api/message-resource):
  submission, queue validity and status callbacks.
- [Webhook security](https://www.twilio.com/docs/usage/security): canonical URL,
  all POST fields and official SDK validation.
- [Error 23004](https://www.twilio.com/docs/api/errors/23004): incompatibility
  between phone-number redaction and Advanced Opt-Out.
- [Regional feature availability](https://www.twilio.com/docs/global-infrastructure/messaging-eu-feature-availability):
  redaction is a paid feature; do not assume optional service support.
- [ICO electronic marketing guidance](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/electronic-and-telephone-marketing/):
  distinguish routine service messages from marketing content.


## CI-equivalent backend validation

The final local run used the exact CI Deno version (2.9.4), a separate cache and
CI's commands: `deno fmt --check supabase/functions` passed for 88 files;
`deno test --allow-env supabase/functions` passed all 123 tests; and all 16
workflow-listed endpoint typechecks passed. The workflow now includes explicit
checks for `local-weather` and `sms-booking-reminders`.

The full directory test command does not inherit a nested function import map.
The SMS test therefore imports the same pinned `npm:twilio@6.1.0` dependency
explicitly; production imports and versions are unchanged. The initial CI-style
run exposed that import issue and 25 formatting failures. Deno's formatter was
applied mechanically to the eight SMS/weather/worker files and 17 existing dirty
email/payment/learning files, with no runtime logic changes in those files.
Standard Deno checks recorded dependency checksums, including local weather's
lockfile and remote assertion-module checksums for the existing worker tests.

These formatting-only local byte changes do not change the already deployed
SMS/email behaviour and did not trigger a redeploy. SQL was unchanged, so the
verified 575-assertion database replay was not repeated for this formatting pass.
This is local CI-equivalent evidence, not a claim that GitHub Actions itself ran.


### Planning costs checked on 5 September 2026

Twilio's UK mobile-number messaging list price was $0.056 per outbound segment,
$0.0075 per inbound segment and $2.50/month for a mobile sender number. With the
indicative USD/GBP rate of 0.7401, one outbound segment is about 4.14p. Two
single-segment reminders for 100 bookings cost about £8.29 before tax, optional
features, carrier/FX fees and sender rental. 100 users at that volume would cost
about £829/month for outbound reminder segments alone. This is a planning
estimate, not a bill or promise of carrier delivery; names/characters/length can
make one visible text occupy several billed segments. One selected timing sends
one reminder, two selected timings send two, only for eligible bookings and
consented supported numbers. Login-code SMS is separate.

If Twilio Verify is selected for login codes, its published fee is $0.05 per
successful verification plus the applicable channel delivery fees. No SMS
provider account, sender rental or Verify service has been activated. Paid
allowances/top-ups were recommended for sustainability; no customer billing
or SMS allowance product has been implemented or authorised yet. The current
technical rate caps are abuse protections, not a customer pricing plan.

Sources: [UK SMS pricing](https://www.twilio.com/en-us/sms/pricing/gb),
[Verify pricing](https://www.twilio.com/en-us/verify/pricing), and
[indicative exchange rate](https://wise.com/gb/currency-converter/usd-to-gbp-rate).

## Owner decision — 5 September 2026: SMS paused for cost

The owner decided to leave SMS reminders inactive because of their ongoing
cost. SMS remains off. Do not create or fund a Twilio account, rent a sender,
activate SMS phone authentication, enable any business's text reminders or
enrol customers while this decision stands. Existing local and disabled hosted
groundwork is retained; it is not an active customer service or a commitment to
a future SMS launch. Customer email reminders continue independently.

WhatsApp reminders are under feasibility review only. No WhatsApp implementation,
provider activation, customer enrollment, outbound reminders or spending is
authorized by this decision. Record the costs and practical requirements for
the owner before considering a separate decision to proceed.
