-- SMS is an independent, initially disabled service channel. Existing email
-- choices, customer records and public booking requests imply no SMS consent.
alter table public.workspace_settings
  add column customer_sms_reminder_minutes integer[] not null default array[]::integer[]
  check (customer_sms_reminder_minutes <@ array[1440,60]
    and cardinality(customer_sms_reminder_minutes)<=2);

create function app_private.booking_sms_phone(p_phone text) returns text
language sql immutable security invoker set search_path='' as $$
  select case when regexp_replace(coalesce(p_phone,''),'[ ()-]','','g')
    ~ '^\+44(7[1-57-9][0-9]{8}|7624[0-9]{6})$'
    then regexp_replace(p_phone,'[ ()-]','','g') end;
$$;
revoke all on function app_private.booking_sms_phone(text) from public,anon,authenticated;
grant execute on function app_private.booking_sms_phone(text) to service_role;

create table app_private.booking_sms_consent (
  contact_id uuid primary key references public.contacts(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  phone text not null check(app_private.booking_sms_phone(phone) is not null and phone=app_private.booking_sms_phone(phone)),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null,
  source text not null default 'owner_confirmed_customer_permission'
    check(source='owner_confirmed_customer_permission'),
  revoked_at timestamptz
);
create index booking_sms_consent_workspace_phone_idx on app_private.booking_sms_consent(workspace_id,phone);
create index booking_sms_consent_granted_by_idx on app_private.booking_sms_consent(granted_by);
create table app_private.booking_sms_suppression (
  phone text primary key,
  stopped_at timestamptz not null default now()
);
create table app_private.booking_sms_outbox (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  recipient_phone text not null,
  start_time timestamptz not null,
  minutes_before integer not null check(minutes_before in (1440,60)),
  due_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'pending' check(status in
    ('pending','processing','sending','uncertain','accepted','delivered','failed','cancelled')),
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_expires_at timestamptz,
  dispatch_token uuid,
  dispatched_at timestamptz,
  provider_message_id text,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique(appointment_id,start_time,minutes_before)
);
create index booking_sms_due_idx on app_private.booking_sms_outbox(due_at)
  where status in ('pending','processing');
create index booking_sms_workspace_dispatch_idx on app_private.booking_sms_outbox(workspace_id,dispatched_at);
create index booking_sms_phone_dispatch_idx on app_private.booking_sms_outbox(recipient_phone,dispatched_at);
create index booking_sms_dispatch_idx on app_private.booking_sms_outbox(dispatched_at);
create unique index booking_sms_provider_idx on app_private.booking_sms_outbox(provider_message_id)
  where provider_message_id is not null;
-- Budget evidence must survive booking deletion, otherwise deleting a sent
-- booking resets its spend allowance. Keep only short-lived pseudonymous usage:
-- no booking/customer foreign key, body, or raw mobile number.
create table app_private.booking_sms_dispatch_usage (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  recipient_hash bytea not null check(octet_length(recipient_hash)=32),
  reserved_at timestamptz not null default clock_timestamp()
);
create index booking_sms_usage_global_idx on app_private.booking_sms_dispatch_usage(reserved_at);
create index booking_sms_usage_workspace_idx on app_private.booking_sms_dispatch_usage(workspace_id,reserved_at);
create index booking_sms_usage_recipient_idx on app_private.booking_sms_dispatch_usage(recipient_hash,reserved_at);
alter table app_private.booking_sms_dispatch_usage enable row level security;
revoke all on app_private.booking_sms_dispatch_usage from public,anon,authenticated;
grant select,insert,delete on app_private.booking_sms_dispatch_usage to service_role;
-- Retention also runs while the outbound provider is disabled. This local SQL
-- job never sends a message and requires no provider secret.
select cron.schedule('workloop-sms-retention','*/15 * * * *',
  $cron$delete from app_private.booking_sms_dispatch_usage where reserved_at<clock_timestamp()-interval '25 hours'; delete from app_private.booking_sms_outbox where created_at<clock_timestamp()-interval '90 days'$cron$);

alter table app_private.booking_sms_consent enable row level security;
alter table app_private.booking_sms_suppression enable row level security;
alter table app_private.booking_sms_outbox enable row level security;
revoke all on app_private.booking_sms_consent,app_private.booking_sms_suppression,app_private.booking_sms_outbox from public,anon,authenticated;
grant select,insert,update,delete on app_private.booking_sms_consent,app_private.booking_sms_suppression,app_private.booking_sms_outbox to service_role;

-- Consent belongs to this contact and this exact mobile. A real phone change
-- revokes permission, including when the owner later restores an older number.
create function app_private.revoke_booking_sms_on_contact_phone_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if app_private.booking_sms_phone(old.phone) is distinct from app_private.booking_sms_phone(new.phone) then
    update app_private.booking_sms_consent set revoked_at=now()
      where contact_id=new.id and revoked_at is null;
    update app_private.booking_sms_outbox set status='cancelled',last_error='customer_phone_changed',lease_token=null,lease_expires_at=null
      where appointment_id in(select id from public.appointments where contact_id=new.id)
        and status in ('pending','processing');
  end if;
  return new;
end; $$;
revoke all on function app_private.revoke_booking_sms_on_contact_phone_change() from public,anon,authenticated,service_role;
create trigger revoke_booking_sms_on_contact_phone_change
  after update of phone on public.contacts for each row
  execute function app_private.revoke_booking_sms_on_contact_phone_change();

-- The only app-facing consent access is scoped to a currently accessible contact.
-- An owner must attest permission for the exact number displayed to them.
create function app_private.booking_sms_contact(p_contact_id uuid,p_enabled boolean,p_expected_phone text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare wid uuid; mobile text; uid uuid := auth.uid();
begin
  select workspace_id,app_private.booking_sms_phone(phone) into wid,mobile
    from public.contacts where id=p_contact_id for update;
  if uid is null or wid is null or not app_private.is_workspace_member(wid)
    or not exists(select 1 from auth.users where id=uid and deleted_at is null
      and (banned_until is null or banned_until<now()))
    or public.current_account_deletion_pending()
    or not app_private.current_user_meets_mfa_policy() then
    raise exception 'Contact is unavailable' using errcode='42501';
  end if;
  if p_enabled is not null then
    if mobile is null or p_expected_phone is distinct from mobile then
      raise exception 'Check the current UK mobile number before changing SMS permission' using errcode='22023';
    end if;
    if p_enabled and exists(select 1 from app_private.booking_sms_suppression where phone=mobile) then
      raise exception 'The customer stopped reminder texts with the SMS provider' using errcode='42501';
    end if;
    if p_enabled then
      insert into app_private.booking_sms_consent(contact_id,workspace_id,phone,granted_by)
        values(p_contact_id,wid,mobile,uid)
        on conflict(contact_id) do update set workspace_id=wid,phone=mobile,granted_at=now(),granted_by=uid,revoked_at=null;
    else
      update app_private.booking_sms_consent set revoked_at=now() where contact_id=p_contact_id and workspace_id=wid and phone=mobile;
      update app_private.booking_sms_outbox set status='cancelled',lease_token=null,lease_expires_at=null
        where workspace_id=wid and appointment_id in(select id from public.appointments where contact_id=p_contact_id)
          and status in ('pending','processing');
    end if;
  end if;
  return jsonb_build_object('phone',mobile,
    'consented',exists(select 1 from app_private.booking_sms_consent where contact_id=p_contact_id and workspace_id=wid and phone=mobile and revoked_at is null),
    'provider_stopped',exists(select 1 from app_private.booking_sms_suppression where phone=mobile));
end; $$;
revoke all on function app_private.booking_sms_contact(uuid,boolean,text) from public,anon,service_role;
grant execute on function app_private.booking_sms_contact(uuid,boolean,text) to authenticated;
create function public.get_booking_sms_consent(p_contact_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select app_private.booking_sms_contact(p_contact_id,null,null);
$$;
create function public.set_booking_sms_consent(p_contact_id uuid,p_enabled boolean,p_expected_phone text) returns jsonb
language sql security invoker set search_path='' as $$
  select app_private.booking_sms_contact(p_contact_id,p_enabled,p_expected_phone);
$$;
revoke all on function public.get_booking_sms_consent(uuid),public.set_booking_sms_consent(uuid,boolean,text) from public,anon,service_role;
grant execute on function public.get_booking_sms_consent(uuid),public.set_booking_sms_consent(uuid,boolean,text) to authenticated;

create function app_private.booking_sms_eligible(p_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists(select 1 from app_private.booking_sms_outbox q
    join public.appointments a on a.id=q.appointment_id and a.workspace_id=q.workspace_id
    join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join app_private.booking_sms_consent p on p.contact_id=c.id and p.workspace_id=q.workspace_id and p.phone=q.recipient_phone
    where q.id=p_id and a.status='scheduled' and a.start_time=q.start_time
      and a.start_time>now() and q.expires_at>now()
      and q.minutes_before=any(s.customer_sms_reminder_minutes)
      and p.revoked_at is null and q.recipient_phone=app_private.booking_sms_phone(c.phone)
      and not exists(select 1 from app_private.booking_sms_suppression where phone=q.recipient_phone)
      and exists(select 1 from public.workspace_members where workspace_id=q.workspace_id)
      and not exists(select 1 from public.account_deletion_requests where workspace_id=q.workspace_id and status in ('requested','processing')));
$$;
revoke all on function app_private.booking_sms_eligible(uuid) from public,anon,authenticated;
grant execute on function app_private.booking_sms_eligible(uuid) to service_role;

create function public.claim_booking_reminder_sms(p_limit integer default 5)
returns table(outbox_id uuid,lease_token uuid)
language plpgsql security invoker set search_path='' as $$
begin
  -- A crash after dispatch may mean Twilio accepted the text. Never reclaim it.
  update app_private.booking_sms_outbox set status='uncertain',last_error='dispatch_outcome_unknown'
    where status='sending' and dispatched_at<now()-interval '2 minutes';
  update app_private.booking_sms_outbox q set status='cancelled',last_error='booking_no_longer_eligible',lease_token=null,lease_expires_at=null
    where status in ('pending','processing') and not app_private.booking_sms_eligible(q.id);
  delete from app_private.booking_sms_outbox where created_at<now()-interval '90 days';
  insert into app_private.booking_sms_outbox(appointment_id,workspace_id,recipient_phone,start_time,minutes_before,due_at,expires_at)
  select a.id,a.workspace_id,p.phone,a.start_time,v.m,a.start_time-make_interval(mins=>v.m),
    least(a.start_time,a.start_time-make_interval(mins=>v.m)+interval '15 minutes')
    from public.appointments a join public.workspace_settings s on s.workspace_id=a.workspace_id
    join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
    join app_private.booking_sms_consent p on p.contact_id=c.id and p.workspace_id=a.workspace_id and p.phone=app_private.booking_sms_phone(c.phone)
    cross join lateral (select distinct unnest(s.customer_sms_reminder_minutes) as m) v
    where a.status='scheduled' and p.revoked_at is null and a.start_time>now()
      and a.start_time-make_interval(mins=>v.m)<=now()
      and a.start_time-make_interval(mins=>v.m)>now()-interval '15 minutes'
      and a.created_at<a.start_time-make_interval(mins=>v.m)-interval '5 minutes'
      and not exists(select 1 from app_private.booking_sms_suppression where phone=p.phone)
      and exists(select 1 from public.workspace_members where workspace_id=a.workspace_id)
      and not exists(select 1 from public.account_deletion_requests where workspace_id=a.workspace_id and status in ('requested','processing'))
    on conflict(appointment_id,start_time,minutes_before) do nothing;
  return query with candidates as (
    select q.id from app_private.booking_sms_outbox q
    where q.due_at<=now() and q.expires_at>now() and q.attempt_count<3
      and (q.status='pending' or (q.status='processing' and q.lease_expires_at<now()))
      and app_private.booking_sms_eligible(q.id)
    order by q.due_at,q.id for update skip locked limit greatest(1,least(p_limit,10))
  ), claimed as (
    update app_private.booking_sms_outbox q set status='processing',attempt_count=q.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '2 minutes'
      where q.id in(select id from candidates) returning q.id,q.lease_token
  ) select c.id,c.lease_token from claimed c;
end; $$;

-- Re-read the booking immediately before dispatch, then reserve bounded usage.
-- Limits count messages, not currency; one text can be multiple billed segments.
create function public.begin_booking_reminder_sms(p_outbox_id uuid,p_lease_token uuid,
  p_global_daily_limit integer default 1000,p_workspace_daily_limit integer default 100,p_phone_daily_limit integer default 6)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare q app_private.booking_sms_outbox%rowtype; dispatch uuid; payload jsonb; reserved timestamptz; phone_hash bytea;
begin
  select * into q from app_private.booking_sms_outbox where id=p_outbox_id for update;
  if q.id is null or q.status<>'processing' or q.lease_token is distinct from p_lease_token or q.lease_expires_at<=now() then return null; end if;
  perform pg_catalog.pg_advisory_xact_lock(781045,1);
  reserved:=clock_timestamp();
  if q.lease_expires_at<=reserved or q.expires_at<=reserved or q.start_time<=reserved
    or not app_private.booking_sms_eligible(q.id) then
    update app_private.booking_sms_outbox set status='cancelled',last_error='booking_no_longer_eligible',lease_token=null,lease_expires_at=null where id=q.id;
    return null;
  end if;
  -- SHA-256 is pseudonymisation, not anonymity; this private table is service-only.
  phone_hash:=extensions.digest(q.recipient_phone,'sha256');
  delete from app_private.booking_sms_dispatch_usage where reserved_at<reserved-interval '25 hours';
  if (select count(*) from app_private.booking_sms_dispatch_usage where reserved_at>reserved-interval '24 hours')>=greatest(1,least(p_global_daily_limit,1000))
    or (select count(*) from app_private.booking_sms_dispatch_usage where workspace_id=q.workspace_id and reserved_at>reserved-interval '24 hours')>=greatest(1,least(p_workspace_daily_limit,100))
    or (select count(*) from app_private.booking_sms_dispatch_usage where recipient_hash=phone_hash and reserved_at>reserved-interval '24 hours')>=greatest(1,least(p_phone_daily_limit,6)) then
    update app_private.booking_sms_outbox set status='cancelled',last_error='daily_message_limit',lease_token=null,lease_expires_at=null where id=q.id;
    return null;
  end if;
  dispatch:=gen_random_uuid();
  select jsonb_build_object('business_name',w.name,'start_time',a.start_time,'timezone',s.timezone,
    'business_phone',s.customer_contact_phone,'minutes_before',q.minutes_before) into payload
    from public.appointments a join public.workspaces w on w.id=a.workspace_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id where a.id=q.appointment_id;
  insert into app_private.booking_sms_dispatch_usage(workspace_id,recipient_hash,reserved_at)
    values(q.workspace_id,phone_hash,reserved);
  update app_private.booking_sms_outbox set status='sending',dispatch_token=dispatch,dispatched_at=reserved where id=q.id;
  return jsonb_build_object('outbox_id',q.id,'dispatch_token',dispatch,'recipient_phone',q.recipient_phone,'payload',payload);
end; $$;

create function public.finish_booking_reminder_sms(p_outbox_id uuid,p_dispatch_token uuid,p_provider_message_id text,p_outcome text,p_error text)
returns void language plpgsql security invoker set search_path='' as $$
declare q app_private.booking_sms_outbox%rowtype;
begin
  select * into q from app_private.booking_sms_outbox where id=p_outbox_id for update;
  if q.id is null or q.dispatch_token is distinct from p_dispatch_token or q.status not in ('sending','uncertain') then return; end if;
  if p_provider_message_id is not null and p_provider_message_id !~ '^SM[0-9a-fA-F]{32}$' then raise exception 'Invalid provider message identifier'; end if;
  if p_outcome not in ('accepted','retry','rejected','uncertain') then raise exception 'Invalid SMS outcome'; end if;
  update app_private.booking_sms_outbox set status=case
    when p_provider_message_id is not null then 'accepted'
    when p_outcome='retry' and attempt_count<3 and expires_at>now()+interval '2 minutes' then 'pending'
    when p_outcome='uncertain' then 'uncertain' else 'failed' end,
    provider_message_id=p_provider_message_id,last_error=left(p_error,80),lease_token=null,lease_expires_at=null,
    due_at=case when p_outcome='retry' then now()+interval '2 minutes' else due_at end
    where id=q.id;
  if p_error='provider_21610' then
    perform public.record_booking_sms_opt_out(q.recipient_phone,true);
  end if;
end; $$;

create function public.record_booking_sms_status(p_outbox_id uuid,p_dispatch_token uuid,p_provider_message_id text,p_status text,p_error text)
returns void language plpgsql security invoker set search_path='' as $$
declare q app_private.booking_sms_outbox%rowtype;
begin
  if p_provider_message_id !~ '^SM[0-9a-fA-F]{32}$' or p_status not in ('accepted','queued','sending','sent','delivered','undelivered','failed','canceled') then return; end if;
  select * into q from app_private.booking_sms_outbox where id=p_outbox_id for update;
  if q.id is null or q.dispatch_token is distinct from p_dispatch_token or q.dispatched_at is null
    or (q.provider_message_id is not null and q.provider_message_id<>p_provider_message_id) or q.status='delivered' then return; end if;
  update app_private.booking_sms_outbox set
    provider_message_id=p_provider_message_id,
    status=case when p_status='delivered' then 'delivered'
      when p_status in ('failed','undelivered','canceled') then 'failed'
      when status='failed' then 'failed' else 'accepted' end,
    delivered_at=case when p_status='delivered' then now() else delivered_at end,
    last_error=case when p_status in ('failed','undelivered','canceled') then left(p_error,80) else last_error end,
    lease_token=null,lease_expires_at=null where id=q.id;
  if p_error='provider_21610' then
    perform public.record_booking_sms_opt_out(q.recipient_phone,true);
  end if;
end; $$;

create function public.record_booking_sms_opt_out(p_phone text,p_stopped boolean) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if p_phone !~ '^\+[1-9][0-9]{7,14}$' then return; end if;
  if p_stopped then
    insert into app_private.booking_sms_suppression(phone) values(p_phone)
      on conflict(phone) do update set stopped_at=now();
    update app_private.booking_sms_consent set revoked_at=now() where phone=p_phone and revoked_at is null;
    update app_private.booking_sms_outbox set status='cancelled',last_error='customer_stopped_sms',lease_token=null,lease_expires_at=null
      where recipient_phone=p_phone and status in ('pending','processing');
  else
    -- Provider START only lifts the provider block. It cannot grant or restore
    -- permission for a business that never had consent or whose consent lapsed.
    delete from app_private.booking_sms_suppression where phone=p_phone;
  end if;
end; $$;

revoke all on function public.claim_booking_reminder_sms(integer),
  public.begin_booking_reminder_sms(uuid,uuid,integer,integer,integer),
  public.finish_booking_reminder_sms(uuid,uuid,text,text,text),
  public.record_booking_sms_status(uuid,uuid,text,text,text),
  public.record_booking_sms_opt_out(text,boolean) from public,anon,authenticated;
grant execute on function public.claim_booking_reminder_sms(integer),
  public.begin_booking_reminder_sms(uuid,uuid,integer,integer,integer),
  public.finish_booking_reminder_sms(uuid,uuid,text,text,text),
  public.record_booking_sms_status(uuid,uuid,text,text,text),
  public.record_booking_sms_opt_out(text,boolean) to service_role;
