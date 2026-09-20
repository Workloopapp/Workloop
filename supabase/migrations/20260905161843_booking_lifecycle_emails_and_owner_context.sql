-- New event intents are private and use the existing minute email worker.
-- No historical events are backfilled. No general Auth-table access is granted.
create table app_private.customer_event_emails (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 request_id uuid references public.booking_requests(id) on delete cascade,
 appointment_id uuid references public.appointments(id) on delete cascade,
 transaction_id uuid references public.payment_transactions(id) on delete cascade,
 event text not null check(event in ('request_received','request_declined','booking_changed','booking_cancelled','payment_request')),
 email text not null, payload jsonb not null, dedupe_key text not null unique,
 status text not null default 'pending' check(status in ('pending','processing','sent','failed','cancelled')),
 due_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '24 hours',
 attempts integer not null default 0, lease_token uuid, lease_until timestamptz,
 provider_message_id text, last_error text, created_at timestamptz not null default now(), sent_at timestamptz
);
create index customer_event_emails_due on app_private.customer_event_emails(due_at) where status in ('pending','processing');
create index customer_event_emails_workspace on app_private.customer_event_emails(workspace_id);
create index customer_event_emails_request on app_private.customer_event_emails(request_id);
create index customer_event_emails_appointment on app_private.customer_event_emails(appointment_id);
create index customer_event_emails_transaction on app_private.customer_event_emails(transaction_id);
create table app_private.customer_email_suppression(email text primary key, created_at timestamptz not null default now());
alter table app_private.customer_event_emails enable row level security;
alter table app_private.customer_email_suppression enable row level security;
revoke all on app_private.customer_event_emails,app_private.customer_email_suppression from public,anon,authenticated;
grant select,insert,update,delete on app_private.customer_event_emails,app_private.customer_email_suppression to service_role;

create function app_private.customer_event_payload(wid uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('business_name',w.name,'timezone',coalesce(s.timezone,'Europe/London'),'reply_email',
  (select u.email::text from public.workspace_members m join auth.users u on u.id=m.user_id
   where m.workspace_id=wid and u.email_confirmed_at is not null and u.deleted_at is null order by m.user_id limit 1))
 from public.workspaces w left join public.workspace_settings s on s.workspace_id=w.id where w.id=wid;
$$;
revoke all on function app_private.customer_event_payload(uuid) from public,anon,authenticated,service_role;

create function app_private.capture_request_email() returns trigger
language plpgsql security definer set search_path='' as $$
declare kind text; p jsonb;
begin
 if tg_op='INSERT' then
  if new.status<>'pending' then return new; end if;
  kind:='request_received';
 else
  if old.status is not distinct from new.status then return new; end if;
  if new.status in ('confirmed','declined') then
   update app_private.customer_event_emails set status='cancelled',lease_token=null,lease_until=null
    where request_id=new.id and event='request_received' and status in ('pending','processing');
  end if;
  if new.status<>'declined' then return new; end if;
  kind:='request_declined';
 end if;
 if coalesce(new.email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return new; end if;
 if not exists(select 1 from public.workspace_members where workspace_id=new.workspace_id) then return new; end if;
 -- Public submissions must not generate an unbounded stream to one address.
 if kind='request_received' and exists(select 1 from app_private.customer_event_emails
  where workspace_id=new.workspace_id and email=lower(btrim(new.email)) and event=kind and created_at>now()-interval '5 minutes') then return new; end if;
 p:=app_private.customer_event_payload(new.workspace_id)||jsonb_build_object('customer_name',new.name,
  'booking_title',coalesce((select name from public.services where id=new.service_id and workspace_id=new.workspace_id),'Booking request'),
  'start_time',new.requested_for,'requested_time',new.preferred_time_text);
 insert into app_private.customer_event_emails(workspace_id,request_id,event,email,payload,dedupe_key)
 values(new.workspace_id,new.id,kind,lower(btrim(new.email)),p,kind||'/'||new.id) on conflict(dedupe_key) do nothing;
 return new;
end; $$;
revoke all on function app_private.capture_request_email() from public,anon,authenticated,service_role;
create trigger request_customer_email after insert or update of status on public.booking_requests for each row execute function app_private.capture_request_email();

create function app_private.capture_booking_change_email() returns trigger
language plpgsql security definer set search_path='' as $$
declare recipient text; customer text; kind text; p jsonb;
begin
 if old.start_time<now() and new.start_time<now() then return new; end if;
 if new.status='cancelled' and old.status is distinct from new.status then kind:='booking_cancelled';
 elsif new.status='scheduled' and (old.start_time,old.end_time,old.title,old.location,old.service_id,old.price) is distinct from
  (new.start_time,new.end_time,new.title,new.location,new.service_id,new.price) then kind:='booking_changed';
 else return new; end if;
 if not exists(select 1 from public.workspace_members where workspace_id=new.workspace_id) then return new; end if;
 select coalesce(r.email,c.email),coalesce(r.customer_name,c.name) into recipient,customer
 from public.contacts c left join app_private.booking_email_recipient r on r.appointment_id=new.id and r.workspace_id=new.workspace_id
 where c.id=new.contact_id and c.workspace_id=new.workspace_id;
 if coalesce(recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return new; end if;
 update app_private.customer_event_emails set status='cancelled',lease_token=null,lease_until=null
 where appointment_id=new.id and event in ('booking_changed','booking_cancelled') and status in ('pending','processing');
 p:=app_private.customer_event_payload(new.workspace_id)||jsonb_build_object('customer_name',customer,'booking_title',new.title,
  'start_time',new.start_time,'end_time',new.end_time,'location',new.location,'price',new.price,'service_id',new.service_id);
 insert into app_private.customer_event_emails(workspace_id,appointment_id,event,email,payload,dedupe_key)
 values(new.workspace_id,new.id,kind,lower(btrim(recipient)),p,kind||'/'||new.id||'/'||gen_random_uuid());
 return new;
end; $$;
revoke all on function app_private.capture_booking_change_email() from public,anon,authenticated,service_role;
create trigger booking_customer_change_email after update on public.appointments for each row execute function app_private.capture_booking_change_email();

create function app_private.queue_payment_request_email(p_transaction_id uuid,p_send boolean default true,p_expected_email text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.payment_transactions; i public.invoices; recipient text; customer text; result app_private.customer_event_emails;
begin
 select * into t from public.payment_transactions where id=p_transaction_id for update;
 if t.id is null or auth.uid() is null or not app_private.is_workspace_member(t.workspace_id) or not app_private.current_user_meets_mfa_policy() then raise exception 'Payment access denied'; end if;
 select * into i from public.invoices where id=t.invoice_id and workspace_id=t.workspace_id;
 if i.id is null or t.amount_minor<=0 or t.currency<>'gbp' or t.collection_method<>'payment_link' or t.status<>'pending' or i.status in ('paid','cancelled','void')
  or t.amount_minor>round(greatest(i.total-coalesce(i.amount_paid,0),0)*100)::integer
  or t.created_at<now()-interval '23 hours' or coalesce(t.metadata->>'checkout_url','') !~ '^https://checkout\.stripe\.com/' then raise exception 'Create a current payment link before emailing it'; end if;
 select coalesce(r.email,c.email),coalesce(r.customer_name,c.name) into recipient,customer from public.contacts c
 left join app_private.booking_email_recipient r on r.appointment_id=i.appointment_id and r.workspace_id=i.workspace_id
 where c.id=i.contact_id and c.workspace_id=i.workspace_id;
 recipient:=lower(btrim(recipient));
 if coalesce(recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Add a valid customer email first'; end if;
 if exists(select 1 from app_private.customer_email_suppression where email=recipient) then raise exception 'Email delivery to this address is paused'; end if;
 if not p_send then return jsonb_build_object('status','preview','email',recipient,'amount_minor',t.amount_minor); end if;
 if p_expected_email is distinct from recipient then raise exception 'Customer email changed. Review the recipient again'; end if;
 -- One request per checkout session. Double taps and retries do not re-send.
 insert into app_private.customer_event_emails(workspace_id,transaction_id,event,email,payload,dedupe_key,expires_at)
 values(t.workspace_id,t.id,'payment_request',recipient,app_private.customer_event_payload(t.workspace_id)||
  jsonb_build_object('customer_name',customer,'invoice_number',i.invoice_number,'amount_minor',t.amount_minor,'checkout_url',t.metadata->>'checkout_url',
   'booking_title',(select title from public.appointments where id=i.appointment_id and workspace_id=i.workspace_id)),
  'payment_request/'||t.id,least(now()+interval '2 hours',t.created_at+interval '23 hours')) on conflict(dedupe_key) do nothing;
 select * into result from app_private.customer_event_emails where dedupe_key='payment_request/'||t.id;
 if result.email is distinct from recipient then raise exception 'Customer email changed. Create a fresh payment link'; end if;
 return jsonb_build_object('id',result.id,'status',result.status,'email',result.email);
end; $$;
revoke all on function app_private.queue_payment_request_email(uuid,boolean,text) from public,anon,authenticated,service_role;
grant execute on function app_private.queue_payment_request_email(uuid,boolean,text) to authenticated;
create function public.queue_payment_request_email(p_transaction_id uuid,p_send boolean default true,p_expected_email text default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.queue_payment_request_email(p_transaction_id,p_send,p_expected_email)$$;
revoke all on function public.queue_payment_request_email(uuid,boolean,text) from public,anon,service_role;
grant execute on function public.queue_payment_request_email(uuid,boolean,text) to authenticated;

create function app_private.customer_event_allowed(p_id uuid) returns boolean
language sql security definer set search_path='' as $$
 select exists(select 1 from app_private.customer_event_emails q where q.id=p_id and q.expires_at>now()
 and exists(select 1 from public.workspace_members where workspace_id=q.workspace_id)
 and not exists(select 1 from app_private.customer_email_suppression where email=q.email)
 and case
 when q.event in ('request_received','request_declined') then exists(select 1 from public.booking_requests r where r.id=q.request_id and r.workspace_id=q.workspace_id and lower(btrim(r.email))=q.email
  and case when q.event='request_declined' then r.status='declined' else r.status in ('pending','contacted') end)
 when q.event in ('booking_changed','booking_cancelled') then exists(select 1 from public.appointments a join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
  left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
  where a.id=q.appointment_id and a.workspace_id=q.workspace_id and lower(btrim(coalesce(r.email,c.email)))=q.email
  and case when q.event='booking_cancelled' then a.status='cancelled' else a.status='scheduled' and a.start_time=(q.payload->>'start_time')::timestamptz
   and a.end_time=(q.payload->>'end_time')::timestamptz and a.title is not distinct from q.payload->>'booking_title' and a.location is not distinct from q.payload->>'location'
   and a.price is not distinct from (q.payload->>'price')::numeric and a.service_id is not distinct from (q.payload->>'service_id')::uuid end)
 when q.event='payment_request' then exists(select 1 from public.payment_transactions t join public.invoices i on i.id=t.invoice_id and i.workspace_id=t.workspace_id
  join public.contacts c on c.id=i.contact_id and c.workspace_id=i.workspace_id
  left join app_private.booking_email_recipient r on r.appointment_id=i.appointment_id and r.workspace_id=i.workspace_id
  where t.id=q.transaction_id and t.workspace_id=q.workspace_id and t.status='pending' and i.status not in ('paid','cancelled','void')
   and lower(btrim(coalesce(r.email,c.email)))=q.email and t.amount_minor=(q.payload->>'amount_minor')::integer and t.amount_minor>0 and t.currency='gbp' and t.amount_minor<=round(greatest(i.total-coalesce(i.amount_paid,0),0)*100)::integer
   and t.created_at>now()-interval '23 hours' and t.metadata->>'checkout_url'=q.payload->>'checkout_url') else false end);
$$;
revoke all on function app_private.customer_event_allowed(uuid) from public,anon,authenticated;
grant execute on function app_private.customer_event_allowed(uuid) to service_role;
create function public.claim_customer_event_emails(p_limit integer default 5) returns setof app_private.customer_event_emails
language plpgsql security invoker set search_path='' as $$
begin
 update app_private.customer_event_emails q set status='cancelled',lease_token=null,lease_until=null where status in ('pending','processing') and not app_private.customer_event_allowed(q.id);
 return query with candidates as(select id from app_private.customer_event_emails where due_at<=now() and attempts<5
  and (status='pending' or status='processing' and lease_until<now()) order by due_at for update skip locked limit greatest(1,least(p_limit,5)))
 update app_private.customer_event_emails q set status='processing',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+interval '2 minutes'
 where q.id in(select id from candidates) returning q.*;
end; $$;
create function public.customer_event_still_allowed(p_id uuid,p_lease_token uuid) returns boolean language sql security invoker set search_path='' as $$
 select exists(select 1 from app_private.customer_event_emails where id=p_id and lease_token=p_lease_token and lease_until>now() and status='processing' and app_private.customer_event_allowed(id));
$$;
create function public.finish_customer_event_email(p_id uuid,p_lease_token uuid,p_provider_id text,p_error text) returns void language sql security invoker set search_path='' as $$
 update app_private.customer_event_emails set status=case when p_provider_id is not null then 'sent' when attempts>=5 then 'failed' else 'pending' end,
 provider_message_id=p_provider_id,last_error=left(p_error,160),sent_at=case when p_provider_id is not null then now() else null end,
 due_at=now()+interval '2 minutes',lease_token=null,lease_until=null where id=p_id and lease_token=p_lease_token and status='processing';
$$;
create function public.suppress_customer_event_email(p_provider_id text) returns void language sql security invoker set search_path='' as $$
 insert into app_private.customer_email_suppression(email) select email from app_private.customer_event_emails where provider_message_id=p_provider_id on conflict do nothing;
$$;
revoke all on function public.claim_customer_event_emails(integer),public.customer_event_still_allowed(uuid,uuid),public.finish_customer_event_email(uuid,uuid,text,text),public.suppress_customer_event_email(text) from public,anon,authenticated;
grant execute on function public.claim_customer_event_emails(integer),public.customer_event_still_allowed(uuid,uuid),public.finish_customer_event_email(uuid,uuid,text,text),public.suppress_customer_event_email(text) to service_role;

-- Add useful, current context to the existing account journey without another
-- mailing list or another weekly send. Unsubscribe and caps remain unchanged.
create function app_private.account_email_context(p_contact_id uuid,p_step integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid; wid uuid; business text; tz text; monday timestamptz; next_step text;
begin
 select c.user_id into uid from app_private.learning_contacts c join auth.users u on u.id=c.user_id
 where c.id=p_contact_id and c.program='account' and c.status='active' and lower(u.email)=c.email and u.email_confirmed_at is not null and u.deleted_at is null;
 if uid is null then return '{}'::jsonb; end if;
 select w.id,w.name,coalesce(s.timezone,'Europe/London') into wid,business,tz from public.workspaces w
 join public.workspace_members m on m.workspace_id=w.id left join public.workspace_settings s on s.workspace_id=w.id where m.user_id=uid order by w.created_at desc limit 1;
 if p_step in (10,12) then
  if wid is null then next_step:='finish_workspace';
  elsif not exists(select 1 from public.services where workspace_id=wid and active) then next_step:='add_service';
  elsif not exists(select 1 from public.contacts where workspace_id=wid) then next_step:='add_client';
  elsif not exists(select 1 from public.appointments where workspace_id=wid) then next_step:='add_booking'; end if;
  return jsonb_build_object('setup_step',next_step,'business_name',business);
 end if;
 if p_step<1000 or wid is null then return '{}'::jsonb; end if;
 -- Rolling seven-day window in the business timezone; amounts are not treated as revenue.
 monday:=((now() at time zone tz)-interval '7 days') at time zone tz;
 return jsonb_build_object('business_name',business,'summary',jsonb_build_object(
  'period_start',monday,'period_end',now(),'timezone',tz,
  'completed_bookings',(select count(*) from public.appointments where workspace_id=wid and status='completed' and start_time>=monday and start_time<=now()),
  'upcoming_bookings',(select count(*) from public.appointments where workspace_id=wid and status='scheduled' and start_time>now() and start_time<=now()+interval '7 days'),
  'waiting_requests',(select count(*) from public.booking_requests where workspace_id=wid and status in ('pending','contacted')),
  'overdue_tasks',(select count(*) from public.tasks where workspace_id=wid and status<>'completed' and due_date<(now() at time zone tz)::date)
 ));
end; $$;
revoke all on function app_private.account_email_context(uuid,integer) from public,anon,authenticated;
grant execute on function app_private.account_email_context(uuid,integer) to service_role;
create function public.account_email_context(p_contact_id uuid,p_step integer) returns jsonb language sql security invoker set search_path='' as $$ select app_private.account_email_context(p_contact_id,p_step) $$;
revoke all on function public.account_email_context(uuid,integer) from public,anon,authenticated;
grant execute on function public.account_email_context(uuid,integer) to service_role;

-- Used only by the authenticated, workspace-checked Stripe Edge Function.
create function public.payment_booking_recipient_email(p_invoice_id uuid) returns text
language sql security invoker set search_path='' as $$
 select r.email from public.invoices i join app_private.booking_email_recipient r on r.appointment_id=i.appointment_id and r.workspace_id=i.workspace_id where i.id=p_invoice_id;
$$;
revoke all on function public.payment_booking_recipient_email(uuid) from public,anon,authenticated;
grant execute on function public.payment_booking_recipient_email(uuid) to service_role;
