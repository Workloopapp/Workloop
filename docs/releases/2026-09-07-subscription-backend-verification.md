# Subscription backend verification — 7 September 2026

Status: implemented and tested locally. The new migration and Edge function have **not** been applied to the hosted project by this pass. No Apple purchase, refund, notification or production access change was generated. Flutter subscription UI, store configuration, final integration and deployment are owned by the parent release pass.

## Scope and schema decision

The initial proposed ledger had one mutable row per original subscription. That is insufficient: Apple renewals are individual transactions, and a later refund can refer to an older paid period while a newer renewal remains active. The revised, still-unapplied migration keeps each transaction separately and introduces a private immutable owner binding for each original subscription chain. This is necessary payment state, not a duplicate business-data cache.

- `store_subscription_owners` binds `(platform, environment, original_transaction_id)` to one account. Renewals cannot claim a different owner. A composite foreign key keeps transaction ownership consistent with its chain.
- `store_subscriptions` uses `(platform, environment, transaction_id)` as its key. Access considers current, non-revoked, non-upgraded **Production** periods only. Sandbox receipts remain separate and do not grant production access.
- The inner transaction's `signedDate` orders expiry, refund and upgrade facts. The independently verified outer notification date orders grace status. A later outer notification carrying an older inner transaction cannot erase a more recent refund.
- A transaction-only restore has no authoritative renewal/grace status. It cannot erase a valid grace period. A newer notification can end grace even if a transaction-only restore arrived first.
- The verified cohort retains lifetime beta access. After beta closes, a verified public account receives exactly 720 elapsed hours from its first accepted access check. Repeated checks do not restart the trial.
- The initial configuration keeps beta open and enforcement and both store-sales flags off. Applying the migration does not itself turn on charging or block the current beta cohort.

Apple explicitly describes the older-transaction refund case in [Meet the App Store Server Library](https://developer.apple.com/videos/play/wwdc2023/10141/). The ordering policy also follows the separate signed dates in Apple's [notification signedDate](https://developer.apple.com/documentation/appstoreservernotifications/signeddate) and [subscription status data](https://apple.github.io/app-store-server-library-node/interfaces/Data.html). These dates are not interchangeable.

## Authentication and request boundaries

The app access RPC requires an existing verified, non-deleted user, the existing optional-MFA policy, and the JWT's session belonging to that exact user. `auth.sessions.not_after` is checked with `clock_timestamp()`. These checks run again after the account upsert, so a session that expires during a wait cannot start a trial; a failure rolls back the write.

Only the service role can write verified transactions. Clients cannot assign purchase ownership, edit ledger rows or call the recording RPC. Private tables have RLS, explicit service policies and revoked client grants. The original-chain binding also survives a competing transaction upsert: cross-chain or cross-account reassignment raises an error and rolls back any new binding.

The Edge endpoint uses Apple's standard server library to verify the certificate chain, signature, app, environment and decoded data. The authenticated app path additionally verifies the signed `appAccountToken` against the current account; a client-supplied environment cannot relabel a Sandbox receipt. Both configured product IDs and the auto-renewable type are checked. The endpoint never logs receipt payloads, tokens, request headers or customer data.

`verify_jwt = false` is explicit for this function because Apple's notification callback has no Supabase JWT. The callback is authenticated by signed Apple data; the app purchase path still performs Auth, session and MFA checks itself. Request bodies are limited to 64,000 **bytes while streaming**, including absent or misleading `Content-Length` headers, and malformed UTF-8/JSON is rejected.

## Files and reasons

| Files | Reason |
| --- | --- |
| `supabase/migrations/20260906223935_workloop_subscription_access.sql` | Private access configuration, beta/trial state, transaction-granular ledger and chain ownership; access/session/MFA checks; expiry write guard. |
| `supabase/functions/workloop-subscription/verification.ts` | Apple SDK verification, signed identity/product policy and separate transaction/status ordering. |
| `supabase/functions/workloop-subscription/index.ts` | Authenticated purchase verification and cryptographically authenticated Apple callback; safe responses without payload logs. |
| `supabase/functions/workloop-subscription/request_body.ts` | Streaming byte limit, strict UTF-8 decoding and object-only JSON boundary. |
| `supabase/functions/workloop-subscription/apple_root.ts`, `deno.json`, `deno.lock` | Existing proposed pinned Apple trust root and reproducible standard SDK dependencies. |
| `supabase/config.toml` | Dedicated callback-compatible function gateway setting. |
| `supabase/functions/workloop-subscription/verification_test.ts`, `request_body_test.ts` | Policy, real-SDK forged-JWS rejection and bounded streaming regressions. |
| `supabase/tests/database/026_workloop_subscription_access.test.sql` | Actual SQL functions, constraints, ACL/RLS presence, transaction ordering, trial/session behavior and write guard. |
| `supabase/tests/fixtures/subscription_bootstrap.sql` | Isolated PostgreSQL-only Auth fixture; never a production migration. |

## Verification receipt

- **36 Deno tests passed**: 24 identity/date/grace/refund policy and real Apple SDK forged-JWS cases, plus 12 body parsing/stream-limit cases. Log: `/tmp/workloop-subscription-deno-tests.log`.
- Full Edge import-graph `deno check` passed. Log: `/tmp/workloop-subscription-deno-check.log`.
- **62 pgTAP assertions passed** in PostgreSQL 17 in the dedicated `workloop-subscription-checks` container on Docker context `colima-workloop-checks`. The database contains synthetic users only. Logs: `/tmp/workloop-subscription-db-bootstrap.log`, `/tmp/workloop-subscription-db-migration.log`, `/tmp/workloop-subscription-db-tests.log`.
- SQL cases include older-period versus current-period refunds, equal/stale replay, newer refund reversal, later outer notification with older inner snapshot, separate renewals, immutable chain ownership, upgrade exclusion, Sandbox isolation, grace restore/end ordering, trial non-reset, missing/malformed/revoked/expired/wrong-user sessions, in-transaction session expiry rollback, MFA, lifetime beta, account-delete cascades, and expired-write/read/delete behavior.
- Scoped formatting and `git diff --check` passed.

This is **not** a claim that the complete Supabase migration chain or a hosted purchase lifecycle has run. The standalone bootstrap models only the relevant Auth fields and copies the existing MFA policy. The write guard is exercised on a temporary business-row probe; the full migration attaches it to the named business tables when present.

## Deployment handoff and remaining gates

The exact runtime bundle and migration are staged at `/tmp/workloop-subscription-backend-20260907/`, with a SHA-256 manifest. Review and apply the SQL before deploying `workloop-subscription` with `verify_jwt: false`. Preserve the initial beta-open, enforcement-off and sales-off configuration until the existing cohort, store products and tested purchase flow are verified.

Still required before charging or enforcing access:

- Full-stack migration review/validation in the existing Supabase schema and RLS environment, including existing workflow triggers and account deletion.
- Real StoreKit Sandbox purchase and restore, same-account and different-account recovery, renewal, billing retry/grace expiry, refund/reversal and notification delivery/retry. The forged-JWS tests prove rejection, not acceptance of a real Apple receipt.
- Confirm the configured app/bundle IDs, product IDs, server notification URL and actual product/store availability. No Google purchase verification is implemented; Google sales remain off.
- Final Flutter tests, signed builds and device checks, especially expired-account read/export/delete and a verified new public account's trial start. No TestFlight/App Store upload is included in this pass.

Suggested commit: `fix: verify subscription periods and preserve account access boundaries`.

## Full-schema integration receipt — 7 September 2026, 00:19 BST

This receipt supersedes the earlier **full migration-chain validation pending** statement. The unchanged existing `/tmp/workloop-db-validation/full-replay.mjs` harness replayed all **94 sorted migrations**, then all **27 SQL suites / 805 assertions**, successfully. This includes **56 Stripe collection notification assertions** and **62 subscription assertions**. No additional bootstrap adaptation or production SQL change was needed.

Evidence: `/tmp/workloop-subscription-full-replay-results.json` and `/tmp/workloop-subscription-full-replay.log`. The JSON records each source SHA-256, complete TAP results and the precise runtime/stubs. The tested migration hashes match the current checkout:

- Subscription `20260906223935`: `71c5ceefaec16ad2f765799ecf7562de294ff559c1ae2d06130196d545c0f9eb`.
- Stripe owner alerts `20260906165210`: `315a135e06d4393571a92a3547970d15f9892696bff595279ee50d32b8d0af40`.

The full replay uses PGlite 0.5.8 / PostgreSQL 18.3, with the existing minimal Auth table/JWT-reader, cron metadata, Vault metadata and Supabase baseline-role fixtures. The only migration-text adaptations were skipping two unavailable `pg_cron` extension declarations because the explicit cron metadata fixture already exists. All application migration logic, functions, triggers, RLS policies and SQL tests ran. These results do not verify GoTrue JWT authentication, actual cron execution, Vault encryption, external push delivery, live money movement or concurrent production connections.

The parent separately reports that the subscription migration and Edge version 1 have now been deployed, with **15 lifetime beta grants**, enforcement/store-sales flags off, unsigned requests returning 401 and forged payloads returning 400. Those are the parent's hosted receipts, not actions performed by this isolated verification pass. The Stripe notification migration was still awaiting the parent's deployment decision at this receipt. No database test failure blocked it. Real Apple purchase/restore/webhook lifecycle and final app/device checks remain separate gates.
