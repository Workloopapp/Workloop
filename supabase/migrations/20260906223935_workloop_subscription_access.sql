-- Server-owned access: existing beta accounts keep lifetime access; a public
-- account gets exactly 30 days from first use. Store purchases are verified
-- by the Edge worker before writing this ledger. No client may grant access.
create table app_private.subscription_config (
  singleton boolean primary key default true check (singleton),
  beta_open boolean not null default true,
  enforcement_enabled boolean not null default false,
  apple_sales_enabled boolean not null default false,
  google_sales_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  check (not enforcement_enabled or apple_sales_enabled)
);
insert into app_private.subscription_config(singleton) values(true);
create table app_private.account_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  beta_lifetime boolean not null default false,
  beta_granted_at timestamptz,
  grant_reason text,
  trial_started_at timestamptz,
  created_at timestamptz not null default now(),
  check (not beta_lifetime or (beta_granted_at is not null and grant_reason is not null))
);
-- A subscription chain has one owner, but each renewal/refund is a distinct
-- transaction. A later refund of an old period cannot revoke a newer renewal.
create table app_private.store_subscription_owners (
  platform text not null check (platform in ('apple','google')),
  environment text not null check (environment in ('Production','Sandbox')),
  original_transaction_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(platform,environment,original_transaction_id),
  unique(platform,environment,original_transaction_id,user_id)
);
create table app_private.store_subscriptions (
  platform text not null check (platform in ('apple','google')),
  environment text not null check (environment in ('Production','Sandbox')),
  original_transaction_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null check (product_id in ('workloop_monthly','workloop_yearly')),
  transaction_id text not null,
  expires_at timestamptz not null,
  grace_expires_at timestamptz,
  revoked_at timestamptz,
  signed_at timestamptz not null,
  is_upgraded boolean not null default false,
  status_signed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(platform,environment,transaction_id),
  foreign key(platform,environment,original_transaction_id,user_id)
    references app_private.store_subscription_owners(platform,environment,original_transaction_id,user_id)
    on delete cascade
);
create index store_subscription_owners_user_idx on app_private.store_subscription_owners(user_id);
create index store_subscriptions_user_idx on app_private.store_subscriptions(user_id);
alter table app_private.subscription_config enable row level security;
alter table app_private.account_access enable row level security;
alter table app_private.store_subscriptions enable row level security;
alter table app_private.store_subscription_owners enable row level security;
create policy subscription_config_service on app_private.subscription_config to service_role using(true) with check(true);
create policy account_access_service on app_private.account_access to service_role using(true) with check(true);
create policy store_subscription_owners_service on app_private.store_subscription_owners to service_role using(true) with check(true);
create policy store_subscriptions_service on app_private.store_subscriptions to service_role using(true) with check(true);
revoke all on app_private.subscription_config,app_private.account_access,app_private.store_subscriptions,app_private.store_subscription_owners from public,anon,authenticated;
grant select,insert,update,delete on app_private.subscription_config,app_private.account_access,app_private.store_subscriptions,app_private.store_subscription_owners to service_role;

-- Freeze the real, verified existing cohort without hard-coded generated IDs.
-- Demo/sample identities remain available for trial/billing QA.
insert into app_private.account_access(user_id,beta_lifetime,beta_granted_at,grant_reason)
select id,true,now(),'existing_beta_2026_09_06' from auth.users
where deleted_at is null and email_confirmed_at is not null
  and email not ilike '%@example.com' and email not ilike '%@resend.dev'
  and email not ilike '%+workloop-%';

-- Verification can happen in an older beta build which has no access screen.
-- Grant at the verified-account boundary so those testers are not missed.
create function app_private.grant_verified_beta_access() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.deleted_at is null and new.email_confirmed_at is not null
    and new.email not ilike '%@example.com' and new.email not ilike '%@resend.dev'
    and new.email not ilike '%+workloop-%'
    and exists(select 1 from app_private.subscription_config where singleton and beta_open) then
    insert into app_private.account_access(user_id,beta_lifetime,beta_granted_at,grant_reason)
      values(new.id,true,now(),'beta_program_entry')
      on conflict(user_id) do nothing;
  end if;
  return new;
end; $$;
revoke all on function app_private.grant_verified_beta_access() from public,anon,authenticated;
create trigger grant_verified_workloop_beta_access after insert or update of email_confirmed_at on auth.users
for each row execute function app_private.grant_verified_beta_access();

create function app_private.workloop_access_for(p_user_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  with config as (select * from app_private.subscription_config where singleton),
  account as (select * from app_private.account_access where user_id=p_user_id),
  paid as (
    select greatest(expires_at,grace_expires_at) as valid_until,product_id,platform
    from app_private.store_subscriptions where user_id=p_user_id
      and environment='Production' and revoked_at is null and not is_upgraded
      and greatest(expires_at,grace_expires_at)>now()
    order by greatest(expires_at,grace_expires_at) desc limit 1
  )
  select jsonb_build_object(
    'state',case when coalesce(a.beta_lifetime,false) then 'beta_lifetime'
                 when p.valid_until is not null then 'subscribed'
                 when c.beta_open then 'beta'
                 when a.trial_started_at+interval '720 hours'>now() then 'trial'
                 else 'expired' end,
    'has_access',not c.enforcement_enabled or c.beta_open or coalesce(a.beta_lifetime,false)
                 or p.valid_until is not null or coalesce(a.trial_started_at+interval '720 hours'>now(),false),
    'trial_ends_at',a.trial_started_at+interval '720 hours',
    'paid_until',p.valid_until,'product_id',p.product_id,'platform',p.platform,
    'apple_sales_enabled',c.apple_sales_enabled,'google_sales_enabled',c.google_sales_enabled,
    'beta_open',c.beta_open,'enforcement_enabled',c.enforcement_enabled,'server_now',now()
  ) from config c left join account a on true left join paid p on true;
$$;
revoke all on function app_private.workloop_access_for(uuid) from public,anon,authenticated;
grant execute on function app_private.workloop_access_for(uuid) to service_role;

create function app_private.get_workloop_access() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid := auth.uid(); u auth.users%rowtype; beta boolean; eligible boolean;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into u from auth.users where id=uid and deleted_at is null;
  if not found or u.email_confirmed_at is null then
    raise exception 'A verified account is required' using errcode='42501';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'MFA verification required' using errcode='42501';
  end if;
  if not exists(select 1 from auth.sessions where user_id=uid and id::text=auth.jwt()->>'session_id'
    and (not_after is null or not_after>clock_timestamp())) then
    raise exception 'Active session required' using errcode='42501';
  end if;
  select beta_open into beta from app_private.subscription_config where singleton;
  eligible := beta and u.email not ilike '%@example.com' and u.email not ilike '%@resend.dev' and u.email not ilike '%+workloop-%';
  insert into app_private.account_access(user_id,beta_lifetime,beta_granted_at,grant_reason,trial_started_at)
    values(uid,eligible,case when eligible then now() end,case when eligible then 'beta_program_entry' end,case when not beta then now() end)
    on conflict(user_id) do update set trial_started_at=case
      when not beta and not account_access.beta_lifetime then coalesce(account_access.trial_started_at,now())
      else account_access.trial_started_at end;
  -- The upsert can wait on another transaction. A session which expires while
  -- waiting must not start a trial or return an account-access snapshot.
  if not exists(select 1 from auth.users where id=uid and deleted_at is null and email_confirmed_at is not null) then
    raise exception 'A verified account is required' using errcode='42501';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'MFA verification required' using errcode='42501';
  end if;
  if not exists(select 1 from auth.sessions where user_id=uid and id::text=auth.jwt()->>'session_id'
    and (not_after is null or not_after>clock_timestamp())) then
    raise exception 'Active session required' using errcode='42501';
  end if;
  return app_private.workloop_access_for(uid);
end; $$;
create function public.get_workloop_access() returns jsonb language sql security invoker set search_path='' as $$
  select app_private.get_workloop_access();
$$;
revoke all on function app_private.get_workloop_access(),public.get_workloop_access() from public,anon;
grant execute on function app_private.get_workloop_access(),public.get_workloop_access() to authenticated;

-- Called only after cryptographic store verification. Ownership is immutable
-- across renewals. signed_at orders snapshots of the SAME transaction only.
create function public.record_verified_store_subscription(p jsonb) returns void
language plpgsql security invoker set search_path='' as $$
begin
  insert into app_private.store_subscription_owners(platform,environment,original_transaction_id,user_id)
    values(p->>'platform',p->>'environment',p->>'original_transaction_id',(p->>'user_id')::uuid)
    on conflict(platform,environment,original_transaction_id) do nothing;
  if not exists(select 1 from app_private.store_subscription_owners s
      where s.platform=p->>'platform' and s.environment=p->>'environment'
        and s.original_transaction_id=p->>'original_transaction_id'
        and s.user_id=(p->>'user_id')::uuid) then
    raise exception 'Purchase belongs to another account' using errcode='42501';
  end if;
  insert into app_private.store_subscriptions(platform,environment,original_transaction_id,user_id,product_id,transaction_id,expires_at,grace_expires_at,revoked_at,signed_at,is_upgraded,status_signed_at)
  values(p->>'platform',p->>'environment',p->>'original_transaction_id',(p->>'user_id')::uuid,
    p->>'product_id',p->>'transaction_id',(p->>'expires_at')::timestamptz,
    (p->>'grace_expires_at')::timestamptz,(p->>'revoked_at')::timestamptz,(p->>'signed_at')::timestamptz,
    coalesce((p->>'is_upgraded')::boolean,false),(p->>'status_signed_at')::timestamptz)
  on conflict(platform,environment,transaction_id) do update set
    product_id=case when store_subscriptions.signed_at<excluded.signed_at then excluded.product_id else store_subscriptions.product_id end,
    expires_at=case when store_subscriptions.signed_at<excluded.signed_at then excluded.expires_at else store_subscriptions.expires_at end,
    revoked_at=case when store_subscriptions.signed_at<excluded.signed_at then excluded.revoked_at else store_subscriptions.revoked_at end,
    is_upgraded=case when store_subscriptions.signed_at<excluded.signed_at then excluded.is_upgraded else store_subscriptions.is_upgraded end,
    signed_at=greatest(store_subscriptions.signed_at,excluded.signed_at),
    grace_expires_at=case when excluded.status_signed_at is not null and
      (store_subscriptions.status_signed_at is null or store_subscriptions.status_signed_at<excluded.status_signed_at)
      then excluded.grace_expires_at else store_subscriptions.grace_expires_at end,
    status_signed_at=greatest(store_subscriptions.status_signed_at,excluded.status_signed_at),updated_at=now()
  where store_subscriptions.user_id=excluded.user_id and
    store_subscriptions.original_transaction_id=excluded.original_transaction_id and
    (store_subscriptions.signed_at<excluded.signed_at or
      (excluded.status_signed_at is not null and (store_subscriptions.status_signed_at is null or store_subscriptions.status_signed_at<excluded.status_signed_at)));
  -- A verified transaction identifier cannot move between subscription chains.
  if exists(select 1 from app_private.store_subscriptions s
      where s.platform=p->>'platform' and s.environment=p->>'environment'
        and s.transaction_id=p->>'transaction_id'
        and (s.original_transaction_id<>p->>'original_transaction_id'
          or s.user_id<>(p->>'user_id')::uuid)) then
    raise exception 'Transaction belongs to another subscription' using errcode='42501';
  end if;
end; $$;
revoke all on function public.record_verified_store_subscription(jsonb) from public,anon,authenticated;
grant execute on function public.record_verified_store_subscription(jsonb) to service_role;

-- Protect writes as well as the app gate. Reading/exporting/deleting existing
-- records remains possible. Trusted provider reconciliation continues normally.
create function app_private.guard_workloop_subscription_write() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is not null and not coalesce((app_private.workloop_access_for(auth.uid())->>'has_access')::boolean,false) then
    raise exception 'Your Workloop trial has ended. Choose a plan to make changes.' using errcode='PT402';
  end if;
  return new;
end; $$;
revoke all on function app_private.guard_workloop_subscription_write() from public,anon,authenticated;
do $$ declare tab text; begin
  foreach tab in array array['contacts','appointments','payments','expenses','tasks','notes','services','workspace_settings','business_profiles','booking_requests'] loop
    if to_regclass('public.'||tab) is not null then
      execute format('create trigger guard_workloop_subscription_write before insert or update on public.%I for each row execute function app_private.guard_workloop_subscription_write()',tab);
    end if;
  end loop;
end $$;
