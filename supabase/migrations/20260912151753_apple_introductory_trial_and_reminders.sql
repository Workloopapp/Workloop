-- Apple owns the introductory trial. Preserve existing beta grants and started
-- legacy trials, but never start another no-card trial. All rollout flags retain
-- their current values; this migration alone cannot start charging or enforcement.
alter table app_private.subscription_config
  add column billing_reminders_enabled boolean not null default false;
alter table app_private.store_subscriptions
  add column purchased_at timestamptz,
  add column is_free_trial boolean not null default false,
  add constraint store_subscription_trial_period check (
    not is_free_trial or (purchased_at is not null and purchased_at < expires_at));
alter table app_private.store_subscription_owners
  add column renewal_signed_at timestamptz,
  add column auto_renews boolean,
  add column renews_at timestamptz,
  add column in_billing_retry boolean not null default false;

create or replace function app_private.workloop_access_for(p_user_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  with config as (select * from app_private.subscription_config where singleton),
  account as (select * from app_private.account_access where user_id=p_user_id),
  paid as (
    select s.*, greatest(s.expires_at,s.grace_expires_at) as valid_until,
      o.auto_renews,o.renews_at,o.in_billing_retry
    from app_private.store_subscriptions s
    join app_private.store_subscription_owners o using(platform,environment,original_transaction_id,user_id)
    where s.user_id=p_user_id and s.environment='Production'
      and s.revoked_at is null and not s.is_upgraded
      and greatest(s.expires_at,s.grace_expires_at)>now()
    order by greatest(s.expires_at,s.grace_expires_at) desc,s.expires_at desc,s.signed_at desc limit 1
  )
  select jsonb_build_object(
    'state',case when coalesce(a.beta_lifetime,false) then 'beta_lifetime'
                 when p.is_free_trial and p.expires_at>now() then 'store_trial'
                 when p.valid_until is not null then 'subscribed'
                 when c.beta_open then 'beta'
                 when a.trial_started_at+interval '720 hours'>now() then 'trial'
                 when a.trial_started_at is not null or exists (
                   select 1 from app_private.store_subscriptions s
                   where s.user_id=p_user_id and s.environment='Production') then 'expired'
                 else 'trial_available' end,
    'has_access',not c.enforcement_enabled or c.beta_open or coalesce(a.beta_lifetime,false)
                 or p.valid_until is not null or coalesce(a.trial_started_at+interval '720 hours'>now(),false),
    'trial_ends_at',case when p.is_free_trial and p.expires_at>now() then p.expires_at
      when p.valid_until is null then a.trial_started_at+interval '720 hours' end,
    'paid_until',p.valid_until,'product_id',p.product_id,'platform',p.platform,
    'auto_renews',p.auto_renews,
    'renews_at',case when p.auto_renews then coalesce(p.renews_at,p.expires_at) end,
    'in_billing_retry',coalesce(p.in_billing_retry,false),
    'grace_ends_at',case when p.grace_expires_at>now() then p.grace_expires_at end,
    'billing_reminders_enabled',c.billing_reminders_enabled,
    'apple_sales_enabled',c.apple_sales_enabled,'google_sales_enabled',c.google_sales_enabled,
    'beta_open',c.beta_open,'enforcement_enabled',c.enforcement_enabled,'server_now',now()
  ) from config c left join account a on true left join paid p on true;
$$;
revoke all on function app_private.workloop_access_for(uuid) from public,anon,authenticated;
grant execute on function app_private.workloop_access_for(uuid) to service_role;

create or replace function app_private.get_workloop_access() returns jsonb
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
  insert into app_private.account_access(user_id,beta_lifetime,beta_granted_at,grant_reason)
    values(uid,eligible,case when eligible then now() end,case when eligible then 'beta_program_entry' end)
    on conflict(user_id) do nothing;
  -- The upsert can wait on another transaction. A session which expires while
  -- waiting must not return an account-access snapshot.
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

create or replace function public.record_verified_store_subscription(p jsonb) returns void
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
  insert into app_private.store_subscriptions(platform,environment,original_transaction_id,user_id,product_id,transaction_id,expires_at,grace_expires_at,revoked_at,signed_at,is_upgraded,status_signed_at,purchased_at,is_free_trial)
  values(p->>'platform',p->>'environment',p->>'original_transaction_id',(p->>'user_id')::uuid,
    p->>'product_id',p->>'transaction_id',(p->>'expires_at')::timestamptz,
    (p->>'grace_expires_at')::timestamptz,(p->>'revoked_at')::timestamptz,(p->>'signed_at')::timestamptz,
    coalesce((p->>'is_upgraded')::boolean,false),(p->>'status_signed_at')::timestamptz,(p->>'purchased_at')::timestamptz,coalesce((p->>'is_free_trial')::boolean,false))
  on conflict(platform,environment,transaction_id) do update set
    product_id=case when store_subscriptions.signed_at<excluded.signed_at then excluded.product_id else store_subscriptions.product_id end,
    expires_at=case when store_subscriptions.signed_at<excluded.signed_at then excluded.expires_at else store_subscriptions.expires_at end,
    revoked_at=case when store_subscriptions.signed_at<excluded.signed_at then excluded.revoked_at else store_subscriptions.revoked_at end,
    is_upgraded=case when store_subscriptions.signed_at<excluded.signed_at then excluded.is_upgraded else store_subscriptions.is_upgraded end,
    purchased_at=case when store_subscriptions.signed_at<excluded.signed_at then excluded.purchased_at else store_subscriptions.purchased_at end,
    is_free_trial=case when store_subscriptions.signed_at<excluded.signed_at then excluded.is_free_trial else store_subscriptions.is_free_trial end,
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
  -- Signed renewal info can accompany an older transaction. Keep its ordering
  -- on the chain so historical refunds and restores cannot undo cancellation.
  update app_private.store_subscription_owners set
    renewal_signed_at=(p->>'renewal_signed_at')::timestamptz,
    auto_renews=(p->>'auto_renews')::boolean,
    renews_at=(p->>'renews_at')::timestamptz,
    in_billing_retry=coalesce((p->>'in_billing_retry')::boolean,false)
  where platform=p->>'platform' and environment=p->>'environment'
    and original_transaction_id=p->>'original_transaction_id'
    and (p->>'renewal_signed_at')::timestamptz is not null
    and (renewal_signed_at is null or renewal_signed_at<(p->>'renewal_signed_at')::timestamptz);
end; $$;
revoke all on function public.record_verified_store_subscription(jsonb) from public,anon,authenticated;
grant execute on function public.record_verified_store_subscription(jsonb) to service_role;

-- Delivery receipts are account-scoped, not workspace notifications. They are
-- necessary for retry/deduplication and never carry recipient addresses or
-- receipt payloads. Due dates are computed from the signed Apple trial period.
create table app_private.subscription_trial_email_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null,
  environment text not null check (environment='Production'),
  transaction_id text not null,
  trial_ends_at timestamptz not null,
  days_before integer not null check (days_before in (7,3)),
  due_at timestamptz not null,
  delivery_expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','skipped','failed')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(platform,environment,transaction_id,trial_ends_at,days_before),
  foreign key(platform,environment,transaction_id)
    references app_private.store_subscriptions(platform,environment,transaction_id) on delete cascade
);
create index subscription_trial_email_due_idx
  on app_private.subscription_trial_email_outbox(next_attempt_at,due_at)
  where status in ('pending','processing');
alter table app_private.subscription_trial_email_outbox enable row level security;
revoke all on app_private.subscription_trial_email_outbox from public,anon,authenticated;
grant select,insert,update,delete on app_private.subscription_trial_email_outbox to service_role;
create policy subscription_trial_email_service on app_private.subscription_trial_email_outbox
  to service_role using(true) with check(true);

create function app_private.subscription_trial_email_is_current(p_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from app_private.subscription_trial_email_outbox e
    join app_private.store_subscriptions s using(platform,environment,transaction_id)
    join app_private.store_subscription_owners o
      on o.platform=s.platform and o.environment=s.environment and o.original_transaction_id=s.original_transaction_id
    join auth.users u on u.id=e.user_id and u.id=s.user_id
    join app_private.subscription_config c on c.singleton
    left join app_private.account_access a on a.user_id=u.id
    where e.id=p_id and c.billing_reminders_enabled
      and not coalesce(a.beta_lifetime,false)
      and u.deleted_at is null and u.email_confirmed_at is not null
      and u.email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      and s.environment='Production' and s.product_id='workloop_monthly'
      and s.is_free_trial and s.expires_at=e.trial_ends_at
      and s.revoked_at is null and not s.is_upgraded and o.auto_renews is true
      and not o.in_billing_retry and coalesce(o.renews_at,s.expires_at)=s.expires_at
      and now()>=e.due_at and now()<e.delivery_expires_at and now()<s.expires_at-interval '24 hours'
      and not exists(select 1 from app_private.store_subscriptions later
        where later.user_id=s.user_id and later.environment='Production'
          and later.transaction_id<>s.transaction_id and later.revoked_at is null
          and not later.is_upgraded and later.expires_at>s.expires_at)
  );
$$;
revoke all on function app_private.subscription_trial_email_is_current(uuid) from public,anon,authenticated;
grant execute on function app_private.subscription_trial_email_is_current(uuid) to service_role;

create function public.claim_subscription_trial_emails(p_limit integer default 5)
returns table(outbox_id uuid,lease_token uuid)
language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;
  if p_limit not between 1 and 20 then raise exception 'invalid claim limit' using errcode='22023'; end if;
  -- A one-day window prevents a recovered worker from sending both reminders
  -- together or reminding after the cancellation deadline. Retries stay inside it.
  insert into app_private.subscription_trial_email_outbox(
    user_id,platform,environment,transaction_id,trial_ends_at,days_before,due_at,delivery_expires_at)
  select s.user_id,s.platform,s.environment,s.transaction_id,s.expires_at,d.days,
    s.expires_at-make_interval(days=>d.days),s.expires_at-make_interval(days=>d.days)+interval '24 hours'
  from app_private.store_subscriptions s
  join app_private.store_subscription_owners o using(platform,environment,original_transaction_id,user_id)
  join app_private.subscription_config c on c.singleton and c.billing_reminders_enabled
  cross join (values(7),(3)) d(days)
  where s.environment='Production' and s.product_id='workloop_monthly' and s.is_free_trial
    and s.revoked_at is null and not s.is_upgraded and o.auto_renews is true
    and now()>=s.expires_at-make_interval(days=>d.days)
    and now()<s.expires_at-make_interval(days=>d.days)+interval '24 hours'
  on conflict(platform,environment,transaction_id,trial_ends_at,days_before) do nothing;

  update app_private.subscription_trial_email_outbox e
    set status=case when attempt_count>=8 then 'failed' else 'skipped' end,
        lease_token=null,lease_expires_at=null,last_error='No longer due or eligible'
    where e.status in ('pending','processing') and
      ((e.attempt_count>=8 and (e.status='pending' or e.lease_expires_at<=now()))
        or not app_private.subscription_trial_email_is_current(e.id));
  return query with candidates as (
    select e.id from app_private.subscription_trial_email_outbox e
    where e.status in ('pending','processing') and e.next_attempt_at<=now()
      and e.attempt_count<8
      and (e.status='pending' or e.lease_expires_at<=now())
    order by e.due_at,e.id for update skip locked limit p_limit
  ), claimed as (
    update app_private.subscription_trial_email_outbox e set
      status='processing',attempt_count=e.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '5 minutes'
    from candidates where e.id=candidates.id returning e.id,e.lease_token
  ) select claimed.id,claimed.lease_token from claimed;
end; $$;

-- The worker rechecks immediately before each provider request, so a refund,
-- renewal, cancellation, account deletion or kill switch after claim suppresses
-- the send. As with all provider delivery there is a small in-flight boundary.
create function public.prepare_subscription_trial_email(p_outbox_id uuid,p_lease_token uuid)
returns table(recipient_email text,trial_ends_at timestamptz,days_before integer)
language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;
  return query select lower(btrim(u.email)),e.trial_ends_at,e.days_before
  from app_private.subscription_trial_email_outbox e join auth.users u on u.id=e.user_id
  where e.id=p_outbox_id and e.lease_token=p_lease_token and e.status='processing'
    and e.lease_expires_at>now() and app_private.subscription_trial_email_is_current(e.id);
end; $$;

create function public.finish_subscription_trial_email(
  p_outbox_id uuid,p_lease_token uuid,p_sent boolean,p_skipped boolean default false,
  p_provider_message_id text default null,p_error text default null)
returns text language plpgsql security definer set search_path='' as $$
declare e app_private.subscription_trial_email_outbox%rowtype; result text;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;
  select * into e from app_private.subscription_trial_email_outbox
    where id=p_outbox_id and lease_token=p_lease_token and status='processing' for update;
  if not found then return 'skipped'; end if;
  if p_sent and nullif(btrim(p_provider_message_id),'') is null then
    raise exception 'Provider message ID required' using errcode='22023';
  end if;
  result:=case when p_sent then 'sent'
    when p_skipped or not app_private.subscription_trial_email_is_current(e.id) then 'skipped'
    when e.attempt_count>=8 then 'failed' else 'pending' end;
  update app_private.subscription_trial_email_outbox set status=result,
    provider_message_id=case when p_sent then left(p_provider_message_id,200) end,
    sent_at=case when p_sent then now() end,
    last_error=case when p_sent then null else left(p_error,200) end,
    next_attempt_at=now()+make_interval(mins=>least(60,power(2,e.attempt_count-1)::integer)),
    lease_token=null,lease_expires_at=null where id=e.id;
  return result;
end; $$;
revoke all on function public.claim_subscription_trial_emails(integer),
  public.prepare_subscription_trial_email(uuid,uuid),
  public.finish_subscription_trial_email(uuid,uuid,boolean,boolean,text,text)
  from public,anon,authenticated;
grant execute on function public.claim_subscription_trial_emails(integer),
  public.prepare_subscription_trial_email(uuid,uuid),
  public.finish_subscription_trial_email(uuid,uuid,boolean,boolean,text,text)
  to service_role;

-- Later modules must use the same authoritative access boundary as bookings,
-- clients and expenses. No read or DELETE policies are changed; provider jobs
-- without a customer auth.uid() retain the existing reconciliation behaviour.
create or replace function app_private.guard_workloop_subscription_write() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_row jsonb; new_row jsonb; relation text; parent_id uuid; cleared boolean:=false;
begin
  if auth.uid() is not null and not coalesce((app_private.workloop_access_for(auth.uid())->>'has_access')::boolean,false) then
    -- Deleting an existing client/booking must still be allowed when PostgreSQL
    -- clears its references. Permit only that referential action: a nested
    -- update, no unrelated field changes, and a parent that has actually gone.
    if tg_op='UPDATE' and pg_trigger_depth()>1 then
      old_row:=to_jsonb(old); new_row:=to_jsonb(new);
      if old_row-array['contact_id','appointment_id','updated_at'] =
         new_row-array['contact_id','appointment_id','updated_at'] then
        foreach relation in array array['contact_id','appointment_id'] loop
          if old_row->relation is distinct from new_row->relation then
            if old_row->>relation is null or new_row->>relation is not null then
              raise exception 'Your Workloop trial has ended. Choose a plan to make changes.' using errcode='PT402';
            end if;
            parent_id:=(old_row->>relation)::uuid;
            if (relation='contact_id' and exists(select 1 from public.contacts where id=parent_id)) or
               (relation='appointment_id' and exists(select 1 from public.appointments where id=parent_id)) then
              raise exception 'Your Workloop trial has ended. Choose a plan to make changes.' using errcode='PT402';
            end if;
            cleared:=true;
          end if;
        end loop;
        if cleared then return new; end if;
      end if;
    end if;
    raise exception 'Your Workloop trial has ended. Choose a plan to make changes.' using errcode='PT402';
  end if;
  return new;
end; $$;
revoke all on function app_private.guard_workloop_subscription_write() from public,anon,authenticated;
do $$ declare tab text; begin
  foreach tab in array array[
    'invoices','task_checklist_items','service_add_ons','booking_request_items',
    'appointment_items','business_documents','business_document_receipts',
    'expense_receipts','mileage_entries','workspace_tax_estimates','record_attachments'
  ] loop
    if to_regclass('public.'||tab) is not null and not exists (
      select 1 from pg_trigger where tgrelid=to_regclass('public.'||tab)
        and tgname='guard_workloop_subscription_write') then
      execute format('create trigger guard_workloop_subscription_write before insert or update on public.%I for each row execute function app_private.guard_workloop_subscription_write()',tab);
    end if;
  end loop;
end $$;
