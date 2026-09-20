# Customer contact details and exception email readiness — 5 September 2026

Customer booking and payment emails now ask recipients to contact the business directly and show its available contact details. Workloop support/account copy also uses direct support contact wording. Historical emails already delivered cannot be changed.

## Contact behaviour

- New `workspace_settings.customer_contact_email` and `customer_contact_phone` are customer-facing details, edited through the existing settings repository and RLS/MFA protection.
- Explicit business email takes precedence. Without one, the verified, non-deleted owner's account email is used, excluding private Apple relay addresses. A phone is shown only when explicitly provided; private Auth phones are never inferred.
- Existing business page and valid public social links are included when available. Unsafe links and malformed details are omitted.
- If no usable contact exists, the email honestly asks the customer to use details previously supplied by the business. No invented address or promise of forwarding.
- Contact details are resolved from the relevant queued email's workspace at first composition and frozen for retries. This preserves stable provider payloads. Contact lookup failure retries rather than sending an incomplete message.
- Reply-To remains useful for accidental replies, but no customer-facing copy asks recipients to reply. A configured/fallback business email receives accidental replies; otherwise the header points to Workloop support.
- The new contact editor is local pending the held app release. Existing builds continue using the verified owner email fallback unless business contact settings are set separately.

## Collection and coverage

The rendered collection has 100 user/customer variants and the review guide adds two internal operations alerts. Variants are not 100 emails sent to every user.

Existing automated paths cover account verification/welcome/deletion, supported Auth/security events, request receipt/decline, accepted-request confirmation, booking changes/cancellation, configured booking reminders, deliberate payment requests, the requested welcome series, conditional onboarding help, weekly advice/summary and inactivity journeys. Auth template availability does not imply every optional Auth flow has a button in the app.

The 26 added templates are **prepared for a verified event or reviewed support case, not newly automatic sends**:

| Audience | Situations |
| --- | --- |
| Booking customer | More information needed, reinstated booking, manually arranged booking confirmation, attendance clarification |
| Paying customer | Processing payment, failed payment, expired link, part payment, corrected balance, pending/failed/partial/completed refund |
| Business owner | Payment requiring review, dispute, payout problem, undeliverable customer email, missing business contacts |
| Account holder | Partial/failed import, requested export ready, delayed deletion, support acknowledgement/resolution, service interruption/recovery |

Each prepared template requires a nonempty verified reference and details. These templates deliberately do not guess an amount, declare a refund complete from a button tap, infer a no-show from an unfinished booking, or assume an incident is resolved because time passed. The catalogue records the required source event for every case. No new speculative marketing or service messages were enrolled.

### Correct edge cases can mean no email

- Private note edits and unchanged booking status do not warrant a customer update.
- Obsolete changes, cancelled bookings, expired reminder windows and revoked leases must not deliver stale reminders.
- Unsubscribed/suppressed addresses must not receive the stopped category; booking reminder and owner marketing preferences stay separate.
- Repeated taps and retries use durable queue identities and provider idempotency.
- An incomplete appointment alone is insufficient evidence of a no-show.
- Payment/refund emails require reconciled provider facts; avoid duplicate Stripe receipts and duplicate requests after payment.
- Support acknowledgements must not answer automated senders in a loop.
- Export, deletion and security messages require their protected workflow, not a marketing timer.

## Files and reasons

- `supabase/migrations/20260905164210_business_email_contact_details.sql`: validated business fields, private reminder contact snapshot, service-only queue contact resolver; existing RLS remains unchanged.
- `lib/features/settings/widgets/business_email_contact_settings.dart` and `email_settings_section.dart`: small contact editor; validation and failed-save input retention; existing repository/provider reuse.
- `_shared/business_contact_email.ts`: common safe HTML/plain-text direct contact block and lookup.
- `_shared/customer_event_email.ts`, `booking_reminder_email.ts`, `booking_confirmation_email.ts`: contact lookup, content and accidental-reply routing in all three delivery paths.
- `_shared/exception_email.ts`: 26 reusable, clearly gated exception templates.
- `_shared/account_journey_email.ts`, `owner_context_email.ts`, `account_welcome_email.ts`, `waitlist_welcome_email.ts`: replace reply invitations with direct support contact language.
- `scripts/email/render_email_catalog.mjs`, `prepare_owner_review.mjs`: expanded synthetic catalogue, correct audiences, trigger labels and prepared-vs-automatic distinctions. Generation sends nothing.
- Contact/widget, email/template and database tests protect routing, validation, escaping, permissions, retry and failure behaviour.

## Deployment and evidence

Production Supabase `imtbyrvsonzvtddswbtb` migration applied as `20260905164210`. Functions deployed and active: `drain-booking-confirmation-emails` v29, `confirm-booking-request` v18, `learning-series` v5, `join-waitlist` v15. Confirmation and waitlist retain gateway JWT verification; scheduled worker and learning-series retain their existing authentication contracts.

Controlled QA at 16:45 UTC sent exactly three customer messages to the owner's dedicated Gmail alias: request acknowledgement, confirmation and one-hour reminder. All three arrived in Inbox with direct business email/phone, no reply invitation, and SPF/DKIM/DMARC passing. The acknowledgement came from an actual request insert and the reminder from an eligible appointment; confirmation used a controlled queue fixture (not an end-to-end phone booking acceptance). Synthetic workspace/user removed afterwards.

| Email | Resend message ID | Gmail message ID |
| --- | --- | --- |
| Request acknowledgement | 4118d80a-6bdc-4716-976d-b917b00a264e | 1a072759adebd595 |
| Confirmation | cb98f5e1-06ab-434f-85e6-9d0da04e9caf | 1a072759a80d51c1 |
| Reminder | 7a9013c0-8a60-46d9-bc05-ecf1a6794425 | 1a072759abff8ee1 |

- Flutter analysis: no issues. One initial brace-style lint was fixed before final analysis.
- Flutter tests: 490 passed, six existing feature-gate skips. Includes validation, normalized save and retry retaining contact edits.
- Signed iOS profile build: passed, 73.7 MB. Existing plugin Swift Package Manager migration warnings remain; build succeeds through the current integration.
- Email/template/worker checks: 29 passed in the Node TypeScript harness, including all customer variants, every exception template, unsafe links, missing references, provider failure and revoked events.
- Database replay: 20 pgTAP suites, 484 assertions passed in PGlite. Harness stubs hosted Auth/cron/Vault; the live three-path check separately verifies the real scheduled worker and delivery.
- `git diff --check`: passed. Customer email appearance inspected in the in-app browser.
- Security advisor: no ERROR findings; existing private-table no-policy INFO notices and six pre-existing authenticated-definer WARN notices remain. New contact RPC is invoker/service-only. See [Supabase advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable); no unrelated security rewrite made.

## Remaining limits and next steps

- No TestFlight upload, installation or new physical-device validation. Contact settings reach beta users with the next approved app release.
- Prepared exception templates require the named verified event/review before sending; creating a template is not a claim that import/export/support/dispute automation now exists.
- Stripe-generated receipts remain processor-managed and use the connected business's Stripe contact configuration. This change does not activate fictional Clearview or verify live-money collection or connected-account refund receipts.
- No Workloop subscription charging lifecycle was introduced; trial/renewal billing notices must match the eventual verified store/provider contract rather than hypothetical dates or prices.
- HTML/text preview files and the trigger guide were regenerated locally; the new 26 previews were not bulk emailed without a fresh request.

Suggested commit: `feat(email): add direct business contacts and prepared exception templates`
