-- Optional, confirmed marketing/education series. Existing accounts and launch
-- list subscribers are NOT enrolled. Public HTTP routes call service-only RPCs.
create table app_private.learning_contacts (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(btrim(email)) and length(email) <= 254),
  stage text not null check (stage in ('exploring','using')),
  source text not null,
  consent_version text not null,
  status text not null default 'pending' check (status in ('pending','active','unsubscribed','suppressed','completed')),
  confirm_token uuid not null default gen_random_uuid(),
  unsubscribe_token uuid not null unique default gen_random_uuid(),
  requested_at timestamptz not null default now(),
  confirmed_at timestamptz,
  stopped_at timestamptz,
  last_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index learning_contacts_confirm_token_idx on app_private.learning_contacts(confirm_token);
alter table app_private.learning_contacts enable row level security;

create table app_private.learning_email_outbox (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references app_private.learning_contacts(id) on delete cascade,
  step integer not null check (step between -1 and 8),
  due_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','cancelled','failed')),
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(contact_id,step)
);
create index learning_email_due_idx on app_private.learning_email_outbox(due_at) where status in ('pending','processing');
create index learning_email_provider_idx on app_private.learning_email_outbox(provider_message_id) where provider_message_id is not null;
alter table app_private.learning_email_outbox enable row level security;
revoke all on app_private.learning_contacts,app_private.learning_email_outbox from public,anon,authenticated;
grant usage on schema app_private to service_role;
grant select,insert,update,delete on app_private.learning_contacts,app_private.learning_email_outbox to service_role;

create function public.request_learning_series(p_email text,p_stage text,p_source text,p_consent_version text)
returns void language plpgsql security invoker set search_path='' as $$
declare c app_private.learning_contacts%rowtype;
begin
  if p_consent_version <> 'workloop-learning-2026-09-v1' or p_stage not in ('exploring','using')
     or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'invalid_learning_request' using errcode='22023';
  end if;
  -- Serialize signup limits and repeat requests. Never reveal membership state.
  perform pg_advisory_xact_lock(905260901);
  select * into c from app_private.learning_contacts where email=lower(btrim(p_email)) for update;
  if found and (c.status in ('active','completed','suppressed') or c.requested_at > now()-interval '1 hour') then return; end if;
  if (select count(*) from app_private.learning_contacts where requested_at > now()-interval '1 hour') >= 100 then return; end if;
  insert into app_private.learning_contacts(email,stage,source,consent_version)
  values(lower(btrim(p_email)),p_stage,left(p_source,80),p_consent_version)
  on conflict(email) do update set stage=excluded.stage,source=excluded.source,
    consent_version=excluded.consent_version,status='pending',confirm_token=gen_random_uuid(),
    requested_at=now(),confirmed_at=null,stopped_at=null,last_sent_at=null
  returning * into c;
  -- A fresh explicit request invalidates earlier confirmation and queued mail.
  delete from app_private.learning_email_outbox where contact_id=c.id;
  insert into app_private.learning_email_outbox(contact_id,step,due_at) values(c.id,-1,now());
end;
$$;

create function public.confirm_learning_series(p_token uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare c app_private.learning_contacts%rowtype;
begin
  select * into c from app_private.learning_contacts where confirm_token=p_token for update;
  if not found then return false; end if;
  if c.status in ('active','completed') then return true; end if;
  if c.status <> 'pending' or c.requested_at < now()-interval '24 hours' then return false; end if;
  update app_private.learning_contacts set status='active',confirmed_at=now() where id=c.id;
  update app_private.learning_email_outbox set status='cancelled',lease_token=null,lease_expires_at=null
    where contact_id=c.id and step=-1 and status<>'sent';
  insert into app_private.learning_email_outbox(contact_id,step,due_at)
  select c.id,ord-1,now()+make_interval(days=>d)
  from unnest(array[0,2,4,7,10,14,18,23,28]) with ordinality as days(d,ord)
  on conflict(contact_id,step) do nothing;
  return true;
end;
$$;

create function public.stop_learning_series(p_token uuid)
returns void language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
  update app_private.learning_contacts set status='unsubscribed',stopped_at=now()
    where unsubscribe_token=p_token and status<>'suppressed' returning id into cid;
  if cid is not null then
    update app_private.learning_email_outbox set status='cancelled',lease_token=null,lease_expires_at=null
      where contact_id=cid and status in ('pending','processing','failed');
  end if;
end;
$$;

create function public.claim_learning_emails(p_limit integer default 5)
returns table(outbox_id uuid,contact_id uuid,step integer,email text,stage text,confirm_token uuid,unsubscribe_token uuid,lease_token uuid)
language plpgsql security invoker set search_path='' as $$
begin
  -- Remove unconfirmed addresses after a week; retain only a short opt-out
  -- suppression record for confirmed subscribers. No app-client data is copied.
  delete from app_private.learning_contacts c where c.status='pending' and c.requested_at<now()-interval '7 days';
  update app_private.learning_email_outbox q set status='failed',last_error='confirmation_expired'
    from app_private.learning_contacts c where q.contact_id=c.id and q.step=-1
    and q.status in ('pending','processing') and c.requested_at<now()-interval '24 hours';
  return query
  with candidates as (
    select q.id from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id
    where q.due_at<=now() and q.attempt_count<5
      and (q.status='pending' or (q.status='processing' and q.lease_expires_at<now()))
      and ((q.step=-1 and c.status='pending' and c.requested_at>now()-interval '24 hours')
        or (q.step>=0 and c.status='active' and (c.last_sent_at is null or c.last_sent_at<now()-interval '20 hours')))
      and not exists (select 1 from app_private.learning_email_outbox earlier
        where earlier.contact_id=q.contact_id and earlier.step>=0 and earlier.step<q.step and earlier.status<>'sent')
    order by q.due_at,q.id for update of q skip locked limit greatest(1,least(p_limit,10))
  ), claimed as (
    update app_private.learning_email_outbox q set status='processing',attempt_count=q.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '5 minutes'
    where q.id in (select id from candidates) returning q.*
  ) select q.id,c.id,q.step,c.email,c.stage,c.confirm_token,c.unsubscribe_token,q.lease_token
    from claimed q join app_private.learning_contacts c on c.id=q.contact_id;
end;
$$;

create function public.learning_email_still_allowed(p_outbox_id uuid,p_lease_token uuid)
returns boolean language sql security invoker set search_path='' as $$
  select exists(select 1 from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id
    where q.id=p_outbox_id and q.lease_token=p_lease_token and q.status='processing'
      and q.lease_expires_at>now() and ((q.step=-1 and c.status='pending') or (q.step>=0 and c.status='active')));
$$;

create function public.finish_learning_email(p_outbox_id uuid,p_lease_token uuid,p_provider_message_id text,p_error text)
returns void language plpgsql security invoker set search_path='' as $$
declare q app_private.learning_email_outbox%rowtype;
begin
  select * into q from app_private.learning_email_outbox where id=p_outbox_id and lease_token=p_lease_token and status='processing' for update;
  if not found then return; end if;
  update app_private.learning_email_outbox set status=case when p_provider_message_id is not null then 'sent' when attempt_count>=5 then 'failed' else 'pending' end,
    provider_message_id=p_provider_message_id,last_error=left(p_error,160),
    sent_at=case when p_provider_message_id is not null then now() else null end,
    due_at=case when p_provider_message_id is null then now()+interval '1 hour' else due_at end,
    lease_token=null,lease_expires_at=null where id=q.id;
  if p_provider_message_id is not null and q.step>=0 then
    update app_private.learning_contacts set last_sent_at=now(),status=case when q.step=8 then 'completed' else status end where id=q.contact_id and status='active';
  end if;
end;
$$;

create function public.suppress_learning_email(p_provider_message_id text)
returns void language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
  select contact_id into cid from app_private.learning_email_outbox where provider_message_id=p_provider_message_id limit 1;
  if cid is not null then
    update app_private.learning_contacts set status='suppressed',stopped_at=now() where id=cid;
    update app_private.learning_email_outbox set status='cancelled',lease_token=null,lease_expires_at=null
      where contact_id=cid and status in ('pending','processing','failed');
  end if;
end;
$$;

revoke all on function public.request_learning_series(text,text,text,text),public.confirm_learning_series(uuid),
  public.stop_learning_series(uuid),public.claim_learning_emails(integer),public.learning_email_still_allowed(uuid,uuid),
  public.finish_learning_email(uuid,uuid,text,text),public.suppress_learning_email(text) from public,anon,authenticated;
grant execute on function public.request_learning_series(text,text,text,text),public.confirm_learning_series(uuid),
  public.stop_learning_series(uuid),public.claim_learning_emails(integer),public.learning_email_still_allowed(uuid,uuid),
  public.finish_learning_email(uuid,uuid,text,text),public.suppress_learning_email(text) to service_role;

-- Delete optional learning data when the associated app account is deleted.
-- Trigger-only SECURITY DEFINER is required because the Auth administrator has
-- no direct access to the private marketing tables. No public callable RPC.
create function app_private.delete_learning_contact_for_deleted_user()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  delete from app_private.learning_contacts where email=lower(btrim(old.email));
  return old;
end;
$$;
revoke all on function app_private.delete_learning_contact_for_deleted_user() from public,anon,authenticated,service_role;
create trigger delete_learning_contact_on_account_deletion after delete on auth.users
  for each row execute function app_private.delete_learning_contact_for_deleted_user();
