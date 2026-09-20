# Stripe collection owner notifications — 6 September 2026

## Change and deployment boundary

Successful Stripe collections previously reconciled the payment and invoice without creating the owner's `payment_received` notification. The new database trigger creates one notification for each newly reconciled collection and lets the existing push outbox handle device delivery. Tapping it opens `/payments/<invoice_id>`.

This change is implemented and verified locally. **It has not been deployed and no real notification, push, customer email or payment was sent during verification.** The existing Stripe webhook source is unchanged. Root must review and apply the new migration to activate the behavior; no Edge Function redeployment is required for this change.

| File | Reason |
| --- | --- |
| `supabase/migrations/20260906165210_stripe_payment_received_notifications.sql` | Adds the private receipt-decision ledger, provider notification trigger, historical baseline and narrow duplicate/forgery guard. |
| `supabase/tests/database/025_stripe_payment_notifications.test.sql` | Adds 56 isolated database assertions for collection, preferences, routing, push enqueue, partial/mixed payments, retries, rollback and tenant boundaries. |

The migration was created using Supabase CLI `2.114.0 migration new stripe_payment_received_notifications` after reading the CLI help. Apply the migration as one transaction. Its brief `SHARE ROW EXCLUSIVE` lock allows reads but makes concurrent payment writes wait until the historical baseline and trigger installation are complete.

## Behavior

- Existing settled payments are marked historical without creating alerts. Refreshes and out-of-order webhook events cannot replay them. Existing pending payments remain eligible when first successfully collected after deployment.
- The trigger runs after `sync_invoice_after_stripe_transaction`. The destination invoice is already reconciled when the notification and push outbox are inserted.
- Only a current successful, unrefunded collection with provider payment/charge references, `paid_at`, matching merchant account and a same-workspace invoice can create the alert. The existing signed webhook/reconciler continues to verify Stripe's current object, amount, currency, metadata and live/test mode.
- Each actual collection has a durable decision keyed by transaction ID. Duplicate updates, clearing the notification inbox and turning preferences back on cannot create another received alert. Separate legitimate installments each have their own receipt.
- Amounts describe the money collected in that transaction: a £40 installment against a £100 invoice says £40 received. It does not claim that the whole invoice is paid.
- A refund/dispute first observed before a success alert consumes the decision silently. Subsequent refund, dispute-won or historical success events do not announce old income again. This change does not introduce refund/dispute alert types.
- Master and payment-received preferences are checked before inserting the alert. Existing push settings, quiet hours, current device/session eligibility and dispatch-time preference checks remain in the shared pipeline.
- Completing an already wholly Stripe-funded booking does not add a redundant manual payment alert. Genuine manual balances and mixed manual/card income keep their existing alerts.
- The notification's reserved `stripe_payment_received:` key can only be inserted through its matching private receipt reservation. Authenticated clients cannot forge the key using another type or an update, take another workspace's key, mutate provider transaction state, or inspect/reset the private ledger.
- Invoice reconciliation, receipt decision and notification insertion commit together. A notification insert failure rolls back the transaction update so the existing webhook retry can complete it once.

## Schema and security

`app_private.stripe_payment_notification_receipts` stores only the transaction ID, optional notification ID, processing time and the decision (`historical`, `queued`, `preferences_disabled`, `settlement_changed`). It is not an additional financial ledger. RLS is enabled; anonymous and authenticated clients have no table access. Server access is explicitly limited to select/insert/update. Both foreign keys are indexed. Clearing an inbox alert clears its notification pointer but retains the durable transaction decision; existing transaction retention/deletion rules remain authoritative.

The provider trigger is `SECURITY INVOKER`, using existing service-role permissions. The narrow notification guard is `SECURITY DEFINER` with an empty search path so it can read the private receipt during existing authenticated workflows. It checks workspace membership before private reads and is not exposed as a callable client RPC. Existing public-table RLS remains in force.

The lock prevents an update from settling between the historical baseline scan and trigger creation. Normal simultaneous reconciliation updates serialize on the transaction row; the receipt primary key and atomic insert also reject duplicate decisions. The isolated test runtime cannot reproduce multiple production database connections.

## Verification

Final migration SHA-256: `315a135e06d4393571a92a3547970d15f9892696bff595279ee50d32b8d0af40`.

| Check | Result |
| --- | --- |
| Full sorted migration replay | 93 migrations passed. |
| All database suites | 743 assertions passed across 26 files, including 56 new assertions. |
| Upgrade simulation with data seeded before this migration | 8 assertions passed: historical suppression, no historical pushes, no replay after refresh, and one new alert/push for a previously pending payment. |
| Stripe reconciliation/API and push-delivery/route Deno tests | 30 tests passed. |
| Existing Stripe webhook Deno typecheck | Passed. |
| Local Supabase security/performance advisors | Unavailable: local Postgres connection refused at `127.0.0.1:54322`. No production query was substituted. ACL/RLS and provider-key guards are covered by the isolated database tests. |

Database evidence uses `/tmp/workloop-db-validation/full-replay.mjs` with PGlite, real PostgreSQL SQL execution and pgTAP. Artifacts: `/tmp/workloop-stripe-notifications-full.json`, `/tmp/workloop-stripe-notification-upgrade.json`, and `/tmp/workloop-stripe-notification-deno.log`. The upgrade runner and its synthetic fixtures are under `/tmp/workloop-db-validation/stripe-notification-upgrade*`; they inject records before applying the actual migration, rather than testing a reimplementation of its backfill.

PGlite stubs Supabase Auth/JWT readers, cron metadata, Vault metadata and baseline roles. These checks do not establish live JWT verification, scheduler timing, Resend delivery, Stripe live-account readiness, APNs receipt on a real device, or production concurrent-worker behavior. Exactly one database notification/queue decision is verified; external push transport delivery is not claimed to be exactly once.

## Release follow-up

1. Review/apply only the intended pending migration using the normal Supabase release process; avoid replaying unrelated dirty migrations without checking remote history.
2. Run security/performance advisors against the deployed database, verifying private-ledger access and foreign-key indexes.
3. Use the existing approved payment validation process to check a genuine merchant's successful collection, exact invoice navigation and permitted iPhone push delivery. This local work did not activate a fictional business or make a live charge.
4. Keep this backend deployment separate from any TestFlight/App Store upload and from live card-collection/merchant activation claims.

Supabase guidance reviewed: [Database triggers](https://supabase.com/docs/guides/database/postgres/triggers), [Database functions](https://supabase.com/docs/guides/database/functions) and the [current changelog](https://supabase.com/changelog.md), retrieved 6 September 2026. No relevant breaking change required modifying the existing notification/push architecture; the new table remains private and all privileges are explicit.

Suggested commit: `fix: notify owners once for reconciled Stripe payments`.
