-- A dedicated QA/review account exercises the real subscription journey while
-- normal customers keep the existing Production-only access policy. This is
-- private operator-owned permission; a client, email address, device or receipt
-- cannot opt an account into Sandbox access. No account is granted by migration.
alter table app_private.account_access
  add column sandbox_access_until timestamptz,
  add constraint account_access_sandbox_dedicated check (
    sandbox_access_until is null or (
      isfinite(sandbox_access_until) and not beta_lifetime and trial_started_at is null
    )
  );
comment on column app_private.account_access.sandbox_access_until is
  'Operator-only finite permission for a dedicated Sandbox tester. Expired non-null permission remains a test account and cannot fall back to free beta. Revoke by setting this to now(), not NULL.';

create or replace function app_private.workloop_access_for(p_user_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  with config as (select * from app_private.subscription_config where singleton),
  account as (select * from app_private.account_access where user_id=p_user_id),
  policy as (
    select c.*,
      a.beta_lifetime,a.trial_started_at,a.sandbox_access_until,
      a.sandbox_access_until is not null as is_tester,
      coalesce(a.sandbox_access_until>now(),false) as sandbox_allowed
    from config c left join account a on true
  ),
  paid as (
    select s.*,
      case when s.environment='Sandbox'
        then least(greatest(s.expires_at,s.grace_expires_at),c.sandbox_access_until)
        else greatest(s.expires_at,s.grace_expires_at) end as valid_until,
      o.auto_renews,o.renews_at,o.in_billing_retry
    from app_private.store_subscriptions s
    join app_private.store_subscription_owners o using(platform,environment,original_transaction_id,user_id)
    cross join policy c
    where s.user_id=p_user_id
      and (s.environment='Production' or (s.environment='Sandbox' and c.sandbox_allowed))
      and s.revoked_at is null and not s.is_upgraded
      and greatest(s.expires_at,s.grace_expires_at)>now()
    -- A real paid period remains authoritative even when a test receipt has a
    -- later expiry. Sandbox never replaces or relabels a Production transaction.
    order by (s.environment='Production') desc,
      greatest(s.expires_at,s.grace_expires_at) desc,s.expires_at desc,s.signed_at desc
    limit 1
  )
  select jsonb_build_object(
    'state',case when coalesce(c.beta_lifetime,false) then 'beta_lifetime'
                 when p.is_free_trial and p.expires_at>now() then 'store_trial'
                 when p.valid_until is not null then 'subscribed'
                 when c.is_tester and not c.sandbox_allowed then 'expired'
                 when c.beta_open and not c.is_tester then 'beta'
                 when not c.is_tester and c.trial_started_at+interval '720 hours'>now() then 'trial'
                 when c.trial_started_at is not null or exists (
                   select 1 from app_private.store_subscriptions s where s.user_id=p_user_id
                     and (s.environment='Production' or c.is_tester)) then 'expired'
                 else 'trial_available' end,
    'has_access',((not c.enforcement_enabled or c.beta_open) and not c.is_tester)
                 or coalesce(c.beta_lifetime,false) or p.valid_until is not null
                 or (not c.is_tester and coalesce(c.trial_started_at+interval '720 hours'>now(),false)),
    'trial_ends_at',case when p.is_free_trial and p.expires_at>now() then p.expires_at
      when p.valid_until is null and not c.is_tester then c.trial_started_at+interval '720 hours' end,
    'paid_until',p.valid_until,'product_id',p.product_id,'platform',p.platform,
    'auto_renews',p.auto_renews,
    'renews_at',case when p.auto_renews then coalesce(p.renews_at,p.expires_at) end,
    'in_billing_retry',coalesce(p.in_billing_retry,false),
    'grace_ends_at',case when p.grace_expires_at>now() then p.grace_expires_at end,
    'store_environment',p.environment,
    'is_sandbox_tester',c.is_tester,
    'sandbox_test_expires_at',c.sandbox_access_until,
    'billing_reminders_enabled',c.billing_reminders_enabled and
      (not c.is_tester or coalesce(p.environment='Production',false)),
    'apple_sales_enabled',case when c.is_tester then c.sandbox_allowed else c.apple_sales_enabled end,
    'google_sales_enabled',c.google_sales_enabled and not c.is_tester,
    'beta_open',c.beta_open and not c.is_tester,
    'enforcement_enabled',c.enforcement_enabled or c.is_tester,
    'server_now',now()
  ) from policy c left join paid p on true;
$$;
revoke all on function app_private.workloop_access_for(uuid) from public,anon,authenticated;
grant execute on function app_private.workloop_access_for(uuid) to service_role;
