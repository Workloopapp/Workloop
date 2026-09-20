# Customer lifecycle and contextual owner emails — 5 September 2026

## Completed behaviour

The email additions are implemented and the backend is deployed to imtbyrvsonzvtddswbtb. No historical booking events were backfilled. No TestFlight upload was made; the owner's release hold remains in force.

| Email | Actual trigger / decision | Evidence |
| --- | --- | --- |
| Request received | New pending booking_requests row with a valid email; five-minute per-business/address acknowledgement throttle | Database assertions and real QA delivery |
| Request declined | Request status changes to declined; one event per request | Database assertions and real QA delivery |
| Booking changed | Future scheduled appointment changes time, title, location, service or price; private-note edits do not qualify | Database assertions and real QA delivery |
| Booking cancelled | Future booking status changes to cancelled; pending change messages are invalidated | Database assertions and real QA delivery |
| Payment request | Signed-in workspace member creates/reuses a Stripe link, previews the saved customer address and amount, then explicitly sends | Database, template and enabled-feature widget checks; no real-money QA |
| Setup help (four variants) | Before day-2/day-6 delivery, read the latest eligible owner's records: no workspace, else no active service, else no client, else no booking | All four states tested; missing-service branch delivered live |
| Weekly business summary | Existing active-account weekly slot after 37 days; count completed bookings over the last seven days, next-seven-day bookings, pending/contacted requests and overdue tasks | Database assertions and real QA delivery |

Setup help replaces that onboarding lesson. The summary shares the existing weekly advice email. Neither creates an extra mailing cadence. These are record-based decisions, not tracking individual taps or individual onboarding-screen fields. No workspace means setup has not committed a business yet. If all four setup records exist, the regular lesson is sent. Unsubscribe, eligibility, inactivity rules and delivery caps remain enforced.

The app writes records to Supabase. Database triggers capture booking events. The minute worker drains booking/customer mail; the 15-minute worker claims eligible account messages and reads setup/summary context immediately before composing. Resend delivers the selected HTML/text and returns a provider ID; webhooks report delivery failures. Phones need not remain open after their changes have synced. Unsaved/offline edits cannot trigger server emails.

## Reply routing

New request/booking-change/cancellation/payment-request messages set Reply-To to the business owner's verified account email. Replies arrive in the owner's normal inbox, not an in-app conversation. The delivered decline QA message 1a0725f5da39274d was inspected: From bookings@workloop.uk, Reply-To the controlled owner Gmail alias, SPF/DKIM/DMARC pass.

Without a valid business reply address, delivery uses support@workloop.uk. The template now explicitly explains this fallback instead of promising a direct business reply. Existing reminder worker also sets the verified owner/fallback Reply-To. The older booking-confirmation template instructs customers to contact the business directly and does not have this new Reply-To mechanism; do not imply every historical email is retroactively changed.

## Files and safeguards

- Migration 20260905161843_booking_lifecycle_emails_and_owner_context.sql: private customer-event queue/suppression, capture triggers, leased service-only workers, member/MFA-checked payment enqueue and service-only owner context. Filename matches the hosted migration timestamp; the initially generated local filename was renamed after applying through MCP. Public wrappers are invokers. No new general Auth table access.
- _shared/customer_event_email.ts and owner_context_email.ts: escaped branded HTML and text, honest request/cancellation wording, five transaction variants, four setup variants and one combined weekly summary.
- learning-series, drain-booking-confirmation-emails, resend-webhook: connect new content to existing schedulers and suppression reporting. Deployed versions 4, 28 and 12 respectively at final verification.
- stripe-payments/index.ts (deployed version 26): new Checkout sessions set customer_email and receipt_email from the authoritative booking recipient or saved invoice contact. Existing sessions are not retrofitted.
- stripe_payments_repository.dart and payment_collection_sheet.dart: deliberate email action, recipient/amount review, recipient-change protection, idempotency and useful database validation messages. Requires payment collection capability and a ready Stripe business.
- scripts/email render/review helpers: 74 user/customer variants plus two operations variants, with triggers and recipients. Ten new previews and the updated complete guide sent to ismaeel1993@outlook.com; prior previews were not resent.
- Website email-preferences guidance: published version 32, source 7c82993e90e0fdec92dd6642b73913bc518c6e5a. Actual workloop.uk response confirmed updated setup, summary and booking/payment explanations.

Payment intents cannot be queued by anonymous/other-workspace users, after payment, for stale links, invalid recipients, non-GBP/invalid amounts or amounts exceeding outstanding balance. Authoritative recipients are reviewed and checked again. Duplicate enqueue uses one event per transaction; changed transaction amounts invalidate stale payloads. Resend retries use stable idempotency keys. Rapid changes/cancellations revoke obsolete pending messages. Private notes are excluded.

## Verification

- Flutter analysis: no issues. Full suite: 489 passed, 6 feature-gated skips. Separate PAYMENT_COLLECTION_ENABLED=true suite: 7 passed, including approve/cancel and recipient-bound payment requests plus existing iOS/Android receipt/refund controls.
- Signed iOS profile build: passed, Runner.app 73.6 MB. This is a local build, not physical-device validation or TestFlight release.
- Database full replay: 19 pgTAP suites, 468 assertions passed in PGlite with hosted Auth permission/type modelling; external cron/Auth bootstrap remains simulated. Hosted queue and scheduler delivery were checked separately.
- Email/template/worker tests: 14 passed in the Node TypeScript harness, including escaping, unsafe checkout rejection, all setup branches, current summary counts, revoked claims, stable retries and correct Reply-To/fallback wording.
- Website typecheck, lint, build and 21 rendered tests pass. Payment and weekly HTML layouts visually inspected.
- Live synthetic QA: request received 85b5e659-1019-4604-8ba5-c39e532f40df; booking changed c447f422-d09a-46d7-83c4-515a40bdc4bc; declined 5324d53c-c108-4741-9f0c-71a204414cfa; cancelled 89a36042-7296-49ee-a56f-cc7e281befd7; setup cae4298b-3569-4276-badd-45300e961244; weekly summary b73aae46-007f-483a-9216-85c2338b36a2. All reached the controlled Gmail inbox. Temporary QA account/workspace/contact were deleted afterwards.
- Scheduled drain returned HTTP 200 with no failed jobs. Security advisor reports expected private-table deny-all/RLS informational notices and pre-existing public definer warnings; no new public definer was added. See https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable for the existing warning class.

## Remaining limits / follow-up

New signup preferences, activity reporting and payment-email controls are local pending the expressly held app release. New booking triggers operate on saved records independently of app distribution. Existing unconsented accounts are not backfilled into the account journey. Template availability is not proof that every optional Auth flow is offered in the app.

Stripe platform Successful payments and Refunds switches were changed from off to on and verified on in Safari. However Workloop uses direct charges: connected businesses use their own receipt settings. Automatic payment receipts are requested through receipt_email for new Checkout sessions; automatic refund receipts still require connected-business settings and real payment/refund verification. Do not send duplicate Workloop refund receipts merely to compensate. Clearview is fictional and must not be activated with invented identity or bank details.

An update of Workloop's Stripe support email/website/privacy/terms was attempted; native Safari stopped exposing the window before saved-state verification. Reconnection and unlock did not restore inspection. The alternate Google session led to new-account registration and was closed without creating an account. Therefore the platform support-detail change and connected-business refund configuration remain unverified. Stripe's current receipt rules: https://docs.stripe.com/receipts#stripe-connect-customizations.

Suggested commit: feat(email): connect customer lifecycle messages and contextual owner guidance

## Follow-up — direct contact wording and exception coverage

The subsequent user instruction supersedes the reply invitation described above. Booking/payment emails now include direct business contact details, and contact settings allow an explicit business email/phone. See [contact and exception implementation](2026-09-05-email-contacts-and-exceptions.md) for deployment, delivery evidence, 26 prepared exception templates and current release limits.
