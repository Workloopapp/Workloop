-- Customer service reminders are separate from Workloop marketing preferences.
-- Private queues reuse the existing minute worker and provider delivery reports.
alter table public.workspace_settings add column customer_reminder_minutes integer[] not null default array[]::integer[]
  check (customer_reminder_minutes <@ array[1440,120,60] and cardinality(customer_reminder_minutes)<=3);
-- Existing businesses choose timings before first activation; new businesses
-- start with 24h/1h. Do not send surprise emails for imported or beta fixtures.
alter table public.workspace_settings alter column customer_reminder_minutes set default array[1440,60];

create table app_private.booking_email_recipient (
  appointment_id uuid primary key references public.appointments(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  customer_name text not null
);
alter table app_private.booking_email_recipient enable row level security;
create index booking_email_recipient_workspace_idx on app_private.booking_email_recipient(workspace_id);
-- Capture the request's authoritative email after the existing atomic workflow.
-- Never replace a public request email with a different phone-matched contact.
alter function app_private.create_booking_workflow(jsonb) rename to create_booking_workflow_before_reminders;
create function app_private.create_booking_workflow(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb; request_row public.booking_requests%rowtype; wid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  wid:=(p_payload->>'workspace_id')::uuid;
  if not app_private.is_workspace_member(wid) then raise exception 'Workspace access denied' using errcode='42501'; end if;
  r:=app_private.create_booking_workflow_before_reminders(p_payload);
  if nullif(p_payload->>'booking_request_id','') is not null then
    select * into request_row from public.booking_requests where id=(p_payload->>'booking_request_id')::uuid and workspace_id=wid and status='confirmed';
    if found and nullif(btrim(request_row.email),'') is not null then
      insert into app_private.booking_email_recipient(appointment_id,workspace_id,email,customer_name)
      select a.id,wid,lower(btrim(request_row.email)),request_row.name
      from jsonb_array_elements_text(r->'appointment_ids') x(id)
      join public.appointments a on a.id=x.id::uuid and a.workspace_id=wid
      on conflict(appointment_id) do nothing;
    end if;
  end if;
  return r;
end; $$;
revoke all on function app_private.create_booking_workflow_before_reminders(jsonb),app_private.create_booking_workflow(jsonb) from public,anon,authenticated;
grant execute on function app_private.create_booking_workflow(jsonb) to service_role;

create table app_private.booking_reminder_preferences (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  unsubscribe_token uuid not null unique default gen_random_uuid(),
  stopped_at timestamptz,
  suppressed_at timestamptz,
  unique(workspace_id,email)
);
alter table app_private.booking_reminder_preferences enable row level security;
create table app_private.booking_reminder_outbox (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  preference_id uuid not null references app_private.booking_reminder_preferences(id) on delete cascade,
  start_time timestamptz not null,
  minutes_before integer not null check(minutes_before in (1440,120,60)),
  due_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'pending' check(status in ('pending','processing','sent','failed','cancelled')),
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(appointment_id,start_time,minutes_before)
);
create index booking_reminder_due_idx on app_private.booking_reminder_outbox(due_at) where status in ('pending','processing');
create index booking_reminder_preference_idx on app_private.booking_reminder_outbox(preference_id);
create index booking_reminder_provider_idx on app_private.booking_reminder_outbox(provider_message_id) where provider_message_id is not null;
alter table app_private.booking_reminder_outbox enable row level security;
revoke all on app_private.booking_email_recipient,app_private.booking_reminder_preferences,app_private.booking_reminder_outbox from public,anon,authenticated;
grant select,insert,update,delete on app_private.booking_email_recipient,app_private.booking_reminder_preferences,app_private.booking_reminder_outbox to service_role;

create function public.enqueue_booking_reminder_emails() returns integer
language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
  -- Enqueue only at the due window, never send a catch-up reminder hours late.
  insert into app_private.booking_reminder_preferences(workspace_id,email)
  select distinct a.workspace_id,lower(btrim(coalesce(r.email,c.email)))
  from public.appointments a join public.workspace_settings s on s.workspace_id=a.workspace_id
  join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
  left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
  where a.status='scheduled' and a.start_time>now() and a.start_time<now()+interval '25 hours'
    and coalesce(r.email,c.email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and exists(select 1 from public.workspace_members m where m.workspace_id=a.workspace_id)
  on conflict(workspace_id,email) do nothing;
  insert into app_private.booking_reminder_outbox(appointment_id,preference_id,start_time,minutes_before,due_at,expires_at)
  select a.id,p.id,a.start_time,v.m,a.start_time-make_interval(mins=>v.m),
    least(a.start_time,a.start_time-make_interval(mins=>v.m)+interval '15 minutes')
  from public.appointments a join public.workspace_settings s on s.workspace_id=a.workspace_id
  join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
  left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
  join app_private.booking_reminder_preferences p on p.workspace_id=a.workspace_id and p.email=lower(btrim(coalesce(r.email,c.email)))
  cross join lateral (select distinct unnest(s.customer_reminder_minutes) as m) v
  where a.status='scheduled' and p.stopped_at is null and p.suppressed_at is null
    and a.start_time>now() and a.start_time-make_interval(mins=>v.m)<=now()
    and a.start_time-make_interval(mins=>v.m)>now()-interval '15 minutes'
    -- A new last-minute booking should not immediately get a redundant reminder.
    and a.created_at<a.start_time-make_interval(mins=>v.m)-interval '5 minutes'
    and exists(select 1 from public.workspace_members m where m.workspace_id=a.workspace_id)
  on conflict(appointment_id,start_time,minutes_before) do nothing;
  get diagnostics n=row_count;
  return n;
end; $$;

create function public.booking_reminder_still_allowed(p_outbox_id uuid,p_lease_token uuid) returns boolean
language sql security invoker set search_path='' as $$
  select exists(select 1 from app_private.booking_reminder_outbox q
    join public.appointments a on a.id=q.appointment_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
    left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
    join app_private.booking_reminder_preferences p on p.id=q.preference_id and p.workspace_id=a.workspace_id
    where q.id=p_outbox_id and q.lease_token=p_lease_token and q.status='processing'
      and q.lease_expires_at>now() and q.expires_at>now() and a.start_time>now()
      and a.start_time=q.start_time and a.status='scheduled' and q.minutes_before=any(s.customer_reminder_minutes)
      and p.email=lower(btrim(coalesce(r.email,c.email))) and p.stopped_at is null and p.suppressed_at is null
      and exists(select 1 from public.workspace_members m where m.workspace_id=a.workspace_id));
$$;

create function public.claim_booking_reminder_emails(p_limit integer default 5)
returns table(outbox_id uuid,lease_token uuid,recipient_email text,unsubscribe_token uuid,reply_email text,payload jsonb)
language plpgsql security invoker set search_path='' as $$
begin
  perform public.enqueue_booking_reminder_emails();
  update app_private.booking_reminder_outbox set status='cancelled',last_error='reminder_window_expired',lease_token=null,lease_expires_at=null
    where status in ('pending','processing') and expires_at<=now();
  return query with candidates as (
    select q.id from app_private.booking_reminder_outbox q
    join public.appointments a on a.id=q.appointment_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join app_private.booking_reminder_preferences p on p.id=q.preference_id
    where q.due_at<=now() and q.expires_at>now() and q.attempt_count<4
      and (q.status='pending' or (q.status='processing' and q.lease_expires_at<now()))
      and a.status='scheduled' and a.start_time=q.start_time and q.minutes_before=any(s.customer_reminder_minutes)
      and p.stopped_at is null and p.suppressed_at is null
    order by q.due_at,q.id for update of q skip locked limit greatest(1,least(p_limit,20))
  ), claimed as (
    update app_private.booking_reminder_outbox q set status='processing',attempt_count=q.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '2 minutes'
    where q.id in(select id from candidates) returning q.*
  ) select q.id,q.lease_token,p.email,p.unsubscribe_token,
      (select u.email from public.workspace_members m join auth.users u on u.id=m.user_id
        where m.workspace_id=a.workspace_id and u.email_confirmed_at is not null order by m.user_id limit 1),
      jsonb_build_object('business_name',w.name,'customer_name',coalesce(r.customer_name,c.name),'booking_title',a.title,
        'start_time',a.start_time,'end_time',a.end_time,'timezone',s.timezone,'location',a.location,'minutes_before',q.minutes_before)
    from claimed q join public.appointments a on a.id=q.appointment_id
    join public.workspaces w on w.id=a.workspace_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
    left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
    join app_private.booking_reminder_preferences p on p.id=q.preference_id;
end; $$;
create function public.finish_booking_reminder_email(p_outbox_id uuid,p_lease_token uuid,p_provider_message_id text,p_error text)
returns void language sql security invoker set search_path='' as $$
  update app_private.booking_reminder_outbox set status=case when p_provider_message_id is not null then 'sent'
    when attempt_count>=4 or expires_at<=now() then 'failed' else 'pending' end,
    provider_message_id=p_provider_message_id,last_error=left(p_error,160),
    sent_at=case when p_provider_message_id is not null then now() else null end,
    due_at=case when p_provider_message_id is null then now()+interval '2 minutes' else due_at end,
    lease_token=null,lease_expires_at=null
    where id=p_outbox_id and lease_token=p_lease_token and status='processing';
$$;
create function public.stop_booking_reminders(p_token uuid) returns void
language plpgsql security invoker set search_path='' as $$
declare pid uuid;
begin
  update app_private.booking_reminder_preferences set stopped_at=now() where unsubscribe_token=p_token returning id into pid;
  update app_private.booking_reminder_outbox set status='cancelled',lease_token=null,lease_expires_at=null
    where preference_id=pid and status in ('pending','processing','failed');
end; $$;
create function public.suppress_booking_reminders(p_provider_message_id text) returns void
language plpgsql security invoker set search_path='' as $$
declare pid uuid;
begin
  select preference_id into pid from app_private.booking_reminder_outbox where provider_message_id=p_provider_message_id limit 1;
  update app_private.booking_reminder_preferences set suppressed_at=now() where id=pid;
  update app_private.booking_reminder_outbox set status='cancelled',lease_token=null,lease_expires_at=null
    where preference_id=pid and status in ('pending','processing','failed');
end; $$;
revoke all on function public.enqueue_booking_reminder_emails(),public.booking_reminder_still_allowed(uuid,uuid),public.claim_booking_reminder_emails(integer),public.finish_booking_reminder_email(uuid,uuid,text,text),public.stop_booking_reminders(uuid),public.suppress_booking_reminders(text) from public,anon,authenticated;
grant execute on function public.enqueue_booking_reminder_emails(),public.booking_reminder_still_allowed(uuid,uuid),public.claim_booking_reminder_emails(integer),public.finish_booking_reminder_email(uuid,uuid,text,text),public.stop_booking_reminders(uuid),public.suppress_booking_reminders(text) to service_role;

-- Existing nine-part subscribers keep exactly the scope they requested.
-- New account journeys start only with a recorded signup notice/opt-out offer.
alter table app_private.learning_contacts
  add column user_id uuid unique references auth.users(id) on delete cascade,
  add column program text not null default 'welcome' check(program in ('welcome','account')),
  add column legal_basis text not null default 'consent' check(legal_basis in ('consent','customer_soft_opt_in')),
  add column notice_recorded_at timestamptz,
  add column last_activity_at timestamptz;
alter table app_private.learning_email_outbox drop constraint learning_email_outbox_step_check;
alter table app_private.learning_email_outbox add constraint learning_email_outbox_step_check check(step between -1 and 100000);

create function app_private.start_account_email_journey(p_user_id uuid,p_enabled boolean,p_basis text,p_offered_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare u auth.users%rowtype; c app_private.learning_contacts%rowtype;
begin
  select * into u from auth.users where id=p_user_id and email_confirmed_at is not null and deleted_at is null;
  if not found or nullif(btrim(u.email),'') is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(lower(u.email),9152026));
  select * into c from app_private.learning_contacts where email=lower(btrim(u.email)) for update;
  -- Automatic enrolment must never override a previous opt-out or broaden a
  -- previously limited series. A fresh affirmative settings choice may restart.
  if found and (c.status='suppressed' or (p_basis='customer_soft_opt_in' and c.id is not null)) then return; end if;
  insert into app_private.learning_contacts(email,user_id,stage,source,consent_version,status,program,legal_basis,notice_recorded_at,confirmed_at,last_activity_at)
  values(lower(btrim(u.email)),u.id,'using','app_account','workloop-account-emails-2026-09-v1',
    case when p_enabled then 'active' else 'unsubscribed' end,'account',p_basis,p_offered_at,now(),now())
  on conflict(email) do update set user_id=u.id,stage='using',source='app_account',
    consent_version='workloop-account-emails-2026-09-v1',program='account',legal_basis=p_basis,
    notice_recorded_at=p_offered_at,status=case when p_enabled then 'active' else 'unsubscribed' end,
    confirmed_at=now(),requested_at=now(),stopped_at=case when p_enabled then null else now() end,
    last_activity_at=now(),last_sent_at=null
  returning * into c;
  delete from app_private.learning_email_outbox where contact_id=c.id and status<>'sent';
  if p_enabled then
    insert into app_private.learning_email_outbox(contact_id,step,due_at)
    select c.id,9+ord,now()+make_interval(days=>d)
      from unnest(array[2,4,6,9,12,16,20,25,30]) with ordinality as days(d,ord)
    on conflict(contact_id,step) do nothing;
  end if;
end; $$;
revoke all on function app_private.start_account_email_journey(uuid,boolean,text,timestamptz) from public,anon,authenticated,service_role;

create function app_private.record_account_email_choice(p_enabled boolean,p_notice_version text,p_offered_at timestamptz,p_source text default 'signup')
returns void language plpgsql security definer set search_path='' as $$
declare u auth.users%rowtype;
begin
  if auth.uid() is null or not app_private.current_user_meets_mfa_policy() then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_enabled is null or p_notice_version is distinct from 'workloop-account-emails-2026-09-v1' or p_source not in ('signup','settings') then
    raise exception 'Invalid email preference' using errcode='22023'; end if;
  select * into u from auth.users where id=auth.uid() and email_confirmed_at is not null;
  if not found then raise exception 'Verify your email first' using errcode='42501'; end if;
  if p_source='signup' then
    -- Social sign-in may also open an old account; never enroll it as new.
    if p_offered_at is null or p_offered_at>now()+interval '1 minute'
      or p_offered_at<now()-interval '1 day' or u.created_at<p_offered_at-interval '1 minute' then return; end if;
  end if;
  perform app_private.start_account_email_journey(u.id,p_enabled,
    case when p_source='signup' then 'customer_soft_opt_in' else 'consent' end,coalesce(p_offered_at,now()));
end; $$;
create function app_private.account_signup_email_choice() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.email_confirmed_at is not null and (tg_op='INSERT' or old.email_confirmed_at is null)
    and new.raw_user_meta_data->>'workloop_email_notice'='workloop-account-emails-2026-09-v1'
    and jsonb_typeof(new.raw_user_meta_data->'workloop_email_updates')='boolean' then
    perform app_private.start_account_email_journey(new.id,(new.raw_user_meta_data->>'workloop_email_updates')::boolean,'customer_soft_opt_in',new.created_at);
  end if;
  return new;
end; $$;
revoke all on function app_private.account_signup_email_choice() from public,anon,authenticated,service_role;
create trigger account_signup_email_choice after insert or update of email_confirmed_at on auth.users
for each row execute function app_private.account_signup_email_choice();

create function app_private.touch_workloop_email_activity() returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not app_private.current_user_meets_mfa_policy() then return; end if;
  update app_private.learning_contacts set last_activity_at=now()
    where user_id=auth.uid() and (last_activity_at is null or last_activity_at<now()-interval '1 hour');
  update app_private.learning_email_outbox q set status='cancelled',lease_token=null,lease_expires_at=null
    from app_private.learning_contacts c where c.id=q.contact_id and c.user_id=auth.uid()
      and q.step in (100,101,102) and q.status in ('pending','processing');
end; $$;
create function app_private.get_account_email_preference() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not app_private.current_user_meets_mfa_policy() then raise exception 'Authentication required' using errcode='42501'; end if;
  select jsonb_build_object('enabled',c.status='active','program',c.program,'suppressed',c.status='suppressed') into result
    from app_private.learning_contacts c join auth.users u on u.id=auth.uid() and lower(u.email)=c.email;
  return coalesce(result,jsonb_build_object('enabled',false,'program',null,'suppressed',false));
end; $$;
create function public.record_account_email_choice(p_enabled boolean,p_notice_version text,p_offered_at timestamptz,p_source text default 'signup') returns void language sql security invoker set search_path='' as $$ select app_private.record_account_email_choice(p_enabled,p_notice_version,p_offered_at,p_source); $$;
revoke all on function app_private.record_account_email_choice(boolean,text,timestamptz,text) from public,anon,authenticated,service_role;
grant execute on function app_private.record_account_email_choice(boolean,text,timestamptz,text) to authenticated;
create function public.touch_workloop_email_activity() returns void language sql security invoker set search_path='' as $$ select app_private.touch_workloop_email_activity(); $$;
revoke all on function app_private.touch_workloop_email_activity() from public,anon,authenticated,service_role;
grant execute on function app_private.touch_workloop_email_activity() to authenticated;
create function public.get_account_email_preference() returns jsonb language sql security invoker set search_path='' as $$ select app_private.get_account_email_preference(); $$;
revoke all on function app_private.get_account_email_preference() from public,anon,authenticated,service_role;
grant execute on function app_private.get_account_email_preference() to authenticated;
revoke all on function public.record_account_email_choice(boolean,text,timestamptz,text),public.touch_workloop_email_activity(),public.get_account_email_preference() from public,anon,authenticated;
grant execute on function public.record_account_email_choice(boolean,text,timestamptz,text),public.touch_workloop_email_activity(),public.get_account_email_preference() to authenticated;

create function public.enqueue_account_email_journeys() returns integer
language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
  update app_private.learning_email_outbox set status='cancelled',lease_token=null,lease_expires_at=null
    where step>=1000 and status in ('pending','processing') and due_at<now()-interval '7 days';
  -- One current weekly tip, not a backlog of tips after time away. Inactivity
  -- nudges are limited to 14/30/60 days, then pause until real app activity.
  insert into app_private.learning_email_outbox(contact_id,step,due_at)
  select c.id,1000+floor(extract(epoch from(now()-c.confirmed_at))/604800)::integer,now()
  from app_private.learning_contacts c join auth.users u on u.id=c.user_id and lower(u.email)=c.email
  where c.program='account' and c.status='active' and c.confirmed_at<now()-interval '37 days'
    and greatest(c.last_activity_at,u.last_sign_in_at)>now()-interval '14 days'
    and (c.last_sent_at is null or c.last_sent_at<now()-interval '7 days')
  on conflict(contact_id,step) do nothing;
  insert into app_private.learning_email_outbox(contact_id,step,due_at)
  select c.id,v.step,now() from app_private.learning_contacts c join auth.users u on u.id=c.user_id and lower(u.email)=c.email
  cross join (values (100,14,30),(101,30,60),(102,60,67)) v(step,days,until_days)
  where c.program='account' and c.status='active'
    and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)<=now()-make_interval(days=>v.days)
    and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)>now()-make_interval(days=>v.until_days)
    and (c.last_sent_at is null or c.last_sent_at<now()-interval '7 days')
  on conflict(contact_id,step) do nothing;
  get diagnostics n=row_count;
  return n;
end; $$;

create or replace function public.claim_learning_emails(p_limit integer default 5)
returns table(outbox_id uuid,contact_id uuid,step integer,email text,stage text,confirm_token uuid,unsubscribe_token uuid,lease_token uuid)
language plpgsql security invoker set search_path='' as $$
begin
  perform public.enqueue_account_email_journeys();
  delete from app_private.learning_contacts c where c.status='pending' and c.requested_at<now()-interval '7 days';
  update app_private.learning_email_outbox q set status='failed',last_error='confirmation_expired'
    from app_private.learning_contacts c where q.contact_id=c.id and q.step=-1
    and q.status in ('pending','processing') and c.requested_at<now()-interval '24 hours';
  return query with candidates as (
    select q.id from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id
    left join auth.users u on u.id=c.user_id
    where q.due_at<=now() and q.attempt_count<5
      and (q.status='pending' or (q.status='processing' and q.lease_expires_at<now()))
      and ((q.step=-1 and c.status='pending' and c.requested_at>now()-interval '24 hours')
        or (q.step>=0 and c.status='active' and (c.last_sent_at is null or c.last_sent_at<now()-interval '20 hours')))
      and (c.program='welcome' or (u.email_confirmed_at is not null and u.deleted_at is null and lower(u.email)=c.email
        and (u.banned_until is null or u.banned_until<now())
        and ((q.step between 10 and 18 and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)>now()-interval '14 days')
          or (q.step>=1000 and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)>now()-interval '14 days' and (c.last_sent_at is null or c.last_sent_at<now()-interval '7 days'))
          or (q.step in (100,101,102) and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)<=now()-make_interval(days=>case q.step when 100 then 14 when 101 then 30 else 60 end)
            and greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)>now()-make_interval(days=>case q.step when 100 then 30 when 101 then 60 else 67 end)
            and (c.last_sent_at is null or c.last_sent_at<now()-interval '7 days')))))
      and not exists(select 1 from app_private.learning_email_outbox earlier where earlier.contact_id=q.contact_id
        and ((q.step between 0 and 8 and earlier.step between 0 and q.step-1)
          or (q.step between 10 and 18 and earlier.step between 10 and q.step-1))
        and earlier.status in ('pending','processing'))
      and not exists(select 1 from app_private.learning_email_outbox leased where leased.contact_id=q.contact_id and leased.status='processing' and leased.lease_expires_at>now())
    order by q.due_at,q.id for update of q skip locked limit greatest(1,least(p_limit,10))
  ), one_per_contact as (
    select distinct on (q.contact_id) q.id from app_private.learning_email_outbox q join candidates x on x.id=q.id order by q.contact_id,q.due_at,q.id
  ), claimed as (
    update app_private.learning_email_outbox q set status='processing',attempt_count=q.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '5 minutes'
    where q.id in(select id from one_per_contact) returning q.*
  ) select q.id,c.id,q.step,c.email,c.stage,c.confirm_token,c.unsubscribe_token,q.lease_token
    from claimed q join app_private.learning_contacts c on c.id=q.contact_id;
end; $$;

create or replace function public.learning_email_still_allowed(p_outbox_id uuid,p_lease_token uuid)
returns boolean language sql security invoker set search_path='' as $$
  select exists(select 1 from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id
    left join auth.users u on u.id=c.user_id
    where q.id=p_outbox_id and q.lease_token=p_lease_token and q.status='processing' and q.lease_expires_at>now()
      and ((q.step=-1 and c.status='pending') or (q.step>=0 and c.status='active'))
      and (c.program='welcome' or (u.email_confirmed_at is not null and lower(u.email)=c.email and u.deleted_at is null
        and (u.banned_until is null or u.banned_until<now())
        and (q.step not in (100,101,102) or greatest(c.last_activity_at,u.last_sign_in_at,c.confirmed_at)<=now()-make_interval(days=>case q.step when 100 then 14 when 101 then 30 else 60 end)))));
$$;
-- finish_learning_email retains its existing nine-part completion behaviour;
-- account steps use 10..18 and therefore keep the ongoing program active.
revoke all on function public.enqueue_account_email_journeys() from public,anon,authenticated;
grant execute on function public.enqueue_account_email_journeys() to service_role;
