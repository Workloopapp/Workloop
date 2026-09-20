# Apple introductory trial and billing reminders — 12 September 2026

Implemented for the approved one-month Apple free trial followed by the monthly subscription. Public release remains paused. The initial local verification below was followed by the authorised hosted preparation receipt at the end of this document. Billing, email reminders and public release remain disabled.

## Access contract

The backend verifies Apple's transaction and renewal JWS with the existing pinned App Store Server Library. It retains the immutable account binding for an original subscription and separate rows for individual renewal/refund periods.

| State | Meaning |
| --- | --- |
| `trial_available` | The account has no previous Production subscription or started legacy trial. Apple purchase authorisation is required before access when enforcement is enabled. This is not a guarantee of introductory-offer eligibility; StoreKit determines that. |
| `store_trial` | A verified Production transaction explicitly identifies an introductory `FREE_TRIAL`, and its Apple expiry is still in the future. Turning off renewal does not remove this period's access. |
| `subscribed` | A verified active paid period or verified billing grace. An expired free period in grace is not described as a continuing free trial. |
| `trial` | An already-started legacy no-card trial retains its original 720-hour end. New access checks never create another no-card trial. |
| `expired` | A previous trial or Production period ended or was revoked without another valid entitlement. |
| `beta` / `beta_lifetime` | Existing beta policy and lifetime grants remain intact. |

`get_workloop_access` continues returning `has_access`, `server_now`, `paid_until`, product/platform and store flags. Additions are `renews_at`, nullable `auto_renews`, `in_billing_retry`, `grace_ends_at` and `billing_reminders_enabled`. During a store trial, `trial_ends_at` is Apple's exact signed expiry; an Apple calendar month is not replaced by 30 days. `paid_until` remains the effective access end, including verified grace.

Transaction-only verification cannot establish cancellation or renewal status. It leaves `auto_renews` unknown until signed renewal information arrives. Independently signed renewal metadata belongs to the original chain and has its own ordering timestamp: a transaction restore or notification concerning an older refunded period cannot overwrite a newer cancellation. A known cancelled subscription returns no future charge date.

Only Production transactions grant access. Sandbox transactions stay isolated and never unlock production accounts. Existing yearly purchases remain recognised even though the new offer is monthly.

## Schema and delivery decision

The additive migration stores the signed trial/purchase facts on the existing transaction ledger and signed renewal facts on its existing owner row. These cannot be safely inferred from client fields. It also adds one private, account-scoped delivery outbox because existing push notifications belong to a workspace and could expose subscription information to other members.

The outbox is used by the existing protected `drain-booking-confirmation-emails` scheduled worker, through the established account email sender configuration. No new schedule, secret, email provider or user notification permission is required. These are subscription service emails, independent of marketing opt-in.

- Due times are computed from the signed free-period expiry, seven and three days before the first charge. Each reminder has a distinct durable identity and one-day delivery window; an offline worker does not backfill both reminders together or send after the cancellation deadline.
- Only current Production monthly free trials with verified auto-renewal enabled qualify. Expired, refunded, replaced, upgraded, cancelled, lifetime-beta and billing-retry periods are excluded. The verified account email is loaded immediately before sending.
- Claim and pre-send checks both recheck the live database state. Cancelling, refunding or deleting an account between claim and preparation suppresses the send. A request already in flight at the provider remains an unavoidable delivery boundary; the email directs users to Apple's latest status.
- Claims use bounded batches, row leases, eight attempts and exponential backoff. The final allowed attempt keeps its valid lease during overlapping worker runs. A stable Resend idempotency key prevents a lost completion response from producing a new logical email.
- Provider message IDs are required to record success. Error records contain stable codes, not recipient addresses, payloads or secrets. Account deletion cascades the outbox. The email gives the exact UTC trial end, an Apple management/cancellation link, the 24-hour cancellation deadline and the fact that deleting the app or Workloop account does not cancel Apple billing. Pricing is directed to the customer's App Store subscription, avoiding an incorrect hardcoded price or currency.

`billing_reminders_enabled` defaults to **false**. The app may promise email reminders only after that capability is enabled. All existing beta, enforcement and sales flag values are preserved. There are no email sends from the migration itself.

## Authoritative write boundary

The existing subscription guard now also covers newer business records: quotes/invoices and their receipts, mileage, tax estimates, receipt metadata, attachments, invoice records, checklist items and service/booking item records. This closes direct Data API and document-RPC paths that would otherwise bypass an expired app screen.

Read/export and DELETE policies are retained. A narrowly constrained nested update allows PostgreSQL to clear `contact_id` / `appointment_id` references when the referenced parent has actually been deleted, without changing the record body. Ordinary direct updates and unrelated nested edits still fail. Provider reconciliation with no customer `auth.uid()` retains the existing behaviour.

## Local verification

- **55 focused Deno tests passed** for signed identity/offer/renewal policy, forged-JWS rejection, request boundaries and email delivery/suppression.
- **16 additional existing email/operator tests passed**; the related email command reports 22 because it also includes the six new reminder tests above.
- Both affected Edge entry-point import graphs passed `deno check`.
- **116 pgTAP assertions passed**: the existing 62 subscription assertions adapted to the new start boundary, plus 54 introductory-period, cancellation, grace, reminder, retry and ownership assertions.
- An additional real PostgreSQL foreign-key probe passed: deleting linked clients/bookings clears document references while preserving the body; an expired account cannot insert mileage or update a document.
- **22 business-schema integration assertions passed**, added and independently reviewed by the journey/QA agent. They execute the current document schema and action/save RPC, mileage/receipt/tax schema and RLS, and both subscription migrations. They cover expired direct/RPC writes, rollback of partial drafts, readable exports, client deletion with document reference clearing, lifetime access, tenant isolation and provider reconciliation.

The SQL verification used disposable PGlite 0.3.16 with explicit Auth/session/MFA fixtures and representative surrounding business tables; the business integration runner also models Storage and base-table dependencies. Together the suites passed **138 pgTAP assertions**. They ran the actual subscription migrations, business migrations noted above, functions, ACLs, constraints and tests. This does not claim a complete hosted-schema replay, concurrent database-connection test, real Apple receipt acceptance, actual scheduler execution or provider delivery. Evidence and hashes are under `build/subscription-backend-20260912/`.

A read-only hosted security advisor baseline still reported 26 private-table RLS informational notices and six pre-existing authenticated security-definer warnings. This was not a hosted check of the new migration, which remains unapplied.

## Integration and activation sequence

1. Complete Flutter integration of the additive contract and monthly StoreKit offer eligibility. With enforcement on, Apple confirmation must precede guarded business-setup writes.
2. Review/apply the additive SQL, then deploy both `workloop-subscription` and the extended scheduled email worker. Keep all rollout flags off and beta access preserved during validation.
3. Configure the Apple monthly product, one-month introductory offer and signed server notifications. Verify real Sandbox purchase, restore, renewal toggle, refund and grace. Sandbox must not create production entitlement or production reminder emails.
4. Verify the account email sender and the deployed worker using synthetic/test-controlled delivery evidence. Then enable `billing_reminders_enabled` only when the service is actually available. Do not infer delivery from an HTTP success or an outbox claim alone.
5. Resume public-release activation separately. Existing beta builds do not understand the new `trial_available` / `store_trial` states; keep beta open/store sales off until the compatible app and rollout are ready. Public distribution requires a newly built candidate containing this implementation; the previously uploaded build 20 predates these changes.

Apple references: [signed transaction fields](https://apple.github.io/app-store-server-library-node/interfaces/JWSTransactionDecodedPayload.html), [signed renewal fields](https://apple.github.io/app-store-server-library-node/interfaces/JWSRenewalInfoDecodedPayload.html), [introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions). Supabase changelog and current [database function guidance](https://supabase.com/docs/guides/database/functions) were checked before implementation.

Suggested commit: `feat: support Apple introductory trials and account billing reminders`

## Hosted preparation receipt — 12 September 2026

The parent authorised scoped backend deployment after local tests and independent review. This supersedes the earlier unapplied-migration / deployment-pending statements above. It does not authorise public release or billing activation.

- Preflight retrieved both deployed Edge source bundles and all four SQL bodies being replaced. Every existing source/dependency matched the pre-task checkout snapshot; no remote drift was overwritten. All eleven newer business tables required by the expanded guard were present.
- Only `apple_introductory_trial_and_reminders` was applied to project `imtbyrvsonzvtddswbtb`. Supabase recorded version **20260912151753**. The CLI-created local migration was renamed to that observed version without changing its SQL bytes, keeping future migration replay aligned.
- `workloop-subscription` deployed as **version 3**, status **ACTIVE**, custom-auth configuration `verify_jwt=false` preserved. All five retrieved deployed source files exactly match the intended local files.
- `drain-booking-confirmation-emails` deployed as **version 34**, status **ACTIVE**, `verify_jwt=false` preserved. All sixteen retrieved deployed source/dependency files exactly match local, including the account reminder helper. Both upload bundles included their pinned dependency lockfiles.
- Before and after: **17 account-access records, all 17 lifetime beta; zero legacy trials; zero store transactions; zero original chains**. After deployment, the reminder outbox contained **zero rows** and every existing account still resolved to `beta_lifetime`.
- Existing rollout flags and their `updated_at` value were unchanged: `beta_open=true`, `enforcement_enabled=false`, `apple_sales_enabled=false`, `google_sales_enabled=false`. The new `billing_reminders_enabled` flag is **false**.
- Hosted catalogue checks confirm subscription guards on **20 business tables**, plus no authenticated read access to the reminder outbox and no authenticated execution access to its claim RPC. Security-advisor counts remained the same 26 existing informational notices and six existing warnings.
- Non-delivery endpoint checks: unauthenticated purchase POST **401**, malformed purchase body **400**, forged Apple notification **400**, and GET on the shared worker **405**. No authenticated worker run, customer email send or real purchase was generated by this pass.

Source snapshots, pre/post configuration and counts, endpoint responses, source hashes and deployed file comparisons are recorded under `build/subscription-backend-20260912/`. The deployed SQL file is `supabase/migrations/20260912151753_apple_introductory_trial_and_reminders.sql`; the other changed backend files are the verification module/tests, reminder email helper/tests, scheduled worker entry point and SQL suites 026, 039 and 040.

Still required before public enforcement: a real Apple lifecycle test, confirmed server notification configuration and an explicit isolated Sandbox/App Review access policy or dedicated test backend. App Review purchases run in Sandbox; this implementation deliberately does not turn those receipts into production entitlement. Do not enable the public paywall or claim review readiness until that reviewer/test path is resolved. Apple agreements, product approval and app submission remain separate release work.

Subsequent provider configuration: both Production and Sandbox notification URLs were saved and read back in App Store Connect. See the [customer journey and Apple configuration receipt](2026-09-12-apple-trial-customer-journey.md). This completes URL configuration only; real signed notification delivery and the remaining activation checks above are still outstanding.
