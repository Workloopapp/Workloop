# Scoped Sandbox review access — 12 September 2026

Status: implemented, independently reviewed and deployed after the local verification below. No tester grant, account creation, global flag change, email send or real Apple purchase occurred in this pass. The hosted receipt at the end supersedes the initial deployment-pending statements.

## Problem and resulting behaviour

Apple reviews In-App Purchases using Sandbox transactions. Workloop already verifies and stores those receipts, but its original access policy intentionally selected Production periods only. A reviewer could therefore complete a valid test purchase and remain outside the paid app. Global beta access also hid that failure by bypassing the purchase journey during testing.

The additive migration introduces one private, finite permission: `app_private.account_access.sandbox_access_until`. A normal account has NULL and keeps the existing Production-only rules. An explicitly permitted, dedicated reviewer/QA account exercises the actual purchase journey and can use its own cryptographically verified Sandbox period. A permission alone grants no subscription access.

- Active test permission closes beta access and enables subscription enforcement for that account. Its effective Apple checkout flag is on even while global Apple sales are off. Google checkout remains off.
- A valid Production entitlement always takes precedence. Sandbox records remain `Sandbox` in the ledger and do not become real revenue or production billing reminders.
- Sandbox access ends at the earlier of the signed subscription/grace expiry and the test permission expiry. Cancellation preserves the remaining period; refunds, upgrades and expiry remove access according to the same verified ledger rules used by Production.
- An expired non-NULL permission remains a dedicated test account and fails closed. It cannot fall back to open beta, disabled global enforcement or a legacy no-card trial.
- A database constraint forbids test permission alongside lifetime beta or a started legacy trial, and rejects infinite permission dates. Existing lifetime grants are untouched.
- Permission is stored in an existing private table with its existing service-only grants/RLS. No client field, user metadata, Apple receipt, email naming convention or device property can grant it. Immutable subscription ownership continues preventing cross-account restore or renewal claims.

The implementation changes only `workloop_access_for` and adds the private column/constraint. Apple's verifier, recording RPC, callback and production email worker remain unchanged.

## Flutter contract

The existing `state`, `has_access`, expiry and store flags are the authoritative effective values. Clients must continue refreshing `get_workloop_access` after verification and on resume, without locally unlocking based on receipt environment.

| Added field | Meaning |
| --- | --- |
| `is_sandbox_tester` | This account has a dedicated testing permission record, including when that permission has expired. It does not itself mean access or a successful purchase. |
| `sandbox_test_expires_at` | Finite server-owned end of the testing permission, nullable for normal accounts. |
| `store_environment` | `Production` or `Sandbox` for the selected active entitlement; NULL without one. Use this field to label an actual test subscription. |

For a selected Sandbox period, `paid_until` is capped at the testing permission end so the existing client expiry clock can close the gate. `trial_ends_at`, `renews_at` and `grace_ends_at` continue describing Apple's actual signed period, including accelerated Sandbox timing. `billing_reminders_enabled` is false for test accounts without an active Production entitlement. The email worker independently continues selecting Production rows only.

## Safe operator grant procedure

These steps are documentation only; none has been executed. Deploy and review the additive migration before granting permission. Use an authorised database/service operator session, never the app client's credentials.

1. Create or select a dedicated, verified reviewer account with a known working password and only synthetic workspace data. Use a controlled email alias containing `+workloop-` when creating it, because the existing beta-enrolment policy already excludes that pattern; the alias itself does not grant testing permission. Keep that account out of lifetime beta. Do not reuse one of the 17 real lifetime-beta accounts, reset their grants, or reuse a customer account.
2. Verify the account's exact `auth.users.id`, verified status and dedicated workspace. Confirm it has no real Stripe connection or real customer recipients. Replace the intentionally invalid UUID placeholder below with that observed ID.
3. Execute this bounded grant transaction. It refuses lifetime/legacy-trial shortcuts and any account with Production subscription history. The actual column constraint also protects later writes.

```sql
begin;
do $$
declare
  review_user uuid := 'REPLACE_WITH_VERIFIED_REVIEW_USER_UUID'::uuid;
begin
  if not exists (
    select 1 from auth.users
    where id=review_user and deleted_at is null and email_confirmed_at is not null
  ) then
    raise exception 'A dedicated verified review account is required';
  end if;
  if exists (
    select 1 from app_private.account_access
    where user_id=review_user and (beta_lifetime or trial_started_at is not null)
  ) or exists (
    select 1 from app_private.store_subscriptions
    where user_id=review_user and environment='Production'
  ) then
    raise exception 'Use a fresh dedicated tester; do not change real customer access';
  end if;
  insert into app_private.account_access(user_id,sandbox_access_until)
    values(review_user,clock_timestamp()+interval '30 days')
    on conflict(user_id) do update
      set sandbox_access_until=excluded.sandbox_access_until
      where not account_access.beta_lifetime and account_access.trial_started_at is null;
  if not found then raise exception 'Tester grant was not applied'; end if;
end $$;
commit;
```

4. Read `app_private.workloop_access_for` for that exact ID in the operator session. Before a purchase it should show `is_sandbox_tester=true`, `state=trial_available`, `has_access=false`, effective `beta_open=false`, `enforcement_enabled=true`, `apple_sales_enabled=true` and no `store_environment`. Check unchanged global flags and unchanged lifetime counts separately.
5. Sign in with this account on the integrated build and run real Apple Sandbox purchase, restore, cancellation, accelerated renewal/expiry and refund tests. A successful test receipt must produce `store_environment=Sandbox` and the appropriate `store_trial` / `subscribed` state, with no Production transaction or billing email. Test a second unpermitted account to verify separation.
6. Put the working reviewer credentials, the subscription screen location and test-purchase instructions in App Review notes. Keep the permission valid throughout review; extend it deliberately before it expires if review takes longer. These notes disclose the account-scoped testing policy and never tell the app to identify Apple reviewers by device or network.

To revoke testing access while retaining the account, expire the permission rather than setting it to NULL:

```sql
update app_private.account_access
set sandbox_access_until=least(sandbox_access_until,clock_timestamp())
where user_id='REPLACE_WITH_VERIFIED_REVIEW_USER_UUID'::uuid
  and sandbox_access_until is not null;
```

This blocks further Sandbox access and its scoped checkout override. A real active Production subscription, if one subsequently exists, remains valid. Normal account deletion still cascades its private access and ledger rows.

## Verification and remaining gates

- **59 new pgTAP assertions passed** for private permission, finite/dedicated-account constraints, effective flags, public RPC/session behaviour, rejection of self-assigned metadata, unapproved Sandbox isolation, chain ownership, cancellation, stale restore, refunds, renewal, grace, expiry, database write enforcement, Production precedence and unchanged global flags.
- **138 existing SQL assertions passed** against the new migration: the subscription/reminder suites and the current business-schema/RLS/document-RPC integration suite. Total: **197 SQL assertions**, plus the existing nested foreign-key deletion/write probe.
- **55 existing Deno tests passed** for Apple verification policy, forged-JWS rejection, request boundaries and email delivery checks. No Edge code changed.
- Scoped whitespace validation passed. Evidence and source hashes are in `build/scoped-sandbox-review-20260912/`.

SQL tests use disposable PGlite and explicit Auth/Storage/base-table fixtures; they exercise actual relevant migrations and functions but are not a full hosted migration replay or a genuine Apple purchase. The migration has not been deployed, no reviewer account exists from this pass, and App Store review readiness still depends on client integration, owner Apple setup and real-device purchase evidence.

Files: `supabase/migrations/20260912155445_scoped_sandbox_subscription_testing.sql`, `supabase/tests/database/041_scoped_sandbox_subscription.test.sql`, and this release note. Suggested commit: `feat: scope Apple Sandbox access to dedicated review accounts`.

Apple sources: [review preparation guidance](https://developer.apple.com/forums/topics/app-store-distribution-and-marketing/app-store-distribution-and-marketing-app-review), [Sandbox testing overview](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox), and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Hosted preparation receipt — 12 September 2026

The independent journey/QA review found no blocking issue in the effective policy, constraints, Production precedence, grant/revoke instructions or test evidence. The parent then authorised applying this one migration without creating or granting any account.

- Preflight confirmed the live `workloop_access_for` body exactly matched the previous deployed migration, the testing column/migration did not yet exist, private access ACLs were intact, and all 17 access records were lifetime beta. Store, legacy-trial and reminder counts were zero.
- Applied only `scoped_sandbox_subscription_testing` to project `imtbyrvsonzvtddswbtb`, recorded by Supabase as **20260912155445**. The CLI-created local migration was renamed to this observed provider version with unchanged SQL bytes.
- Retrieved deployed SQL exactly matches the tested migration. Its definer/empty-search-path configuration and service-only helper execution grants remain intact; authenticated clients cannot update the permission column. The finite, non-lifetime, non-legacy-trial constraint was read back and verified.
- After deployment: **17 lifetime-beta accounts unchanged, zero tester permissions, zero store transactions, zero legacy trials and zero reminder rows**. Every existing account still reports `beta_lifetime` and `is_sandbox_tester=false`.
- Global configuration, including its existing `updated_at`, was byte-for-value unchanged: beta open; enforcement, Apple sales, Google sales and billing reminders all off.
- No Edge function needed deployment. No account was created/granted, no shared worker was invoked, and no email, Apple purchase or app upload was generated.

Pre/post evidence is saved in `build/scoped-sandbox-review-20260912/hosted-before.json` and `hosted-after.json`. Creating the dedicated account, granting its finite permission, integrating the current Flutter build and completing the real device Sandbox lifecycle remain separate next steps; deployment alone is not an App Review readiness claim.
