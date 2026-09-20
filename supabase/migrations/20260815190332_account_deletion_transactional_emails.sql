-- Queue durable, purpose-specific deletion emails at the two authoritative
-- database transitions: request recorded and deletion completed. The outbox
-- survives Auth/workspace deletion because it belongs to the retained request.

create table app_private.account_deletion_email_outbox (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.account_deletion_requests(id)
    on delete cascade,
  event text not null
    check (event in ('deletion_requested', 'account_deleted')),
  recipient_email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default clock_timestamp(),
  lease_token uuid,
  lease_expires_at timestamptz,
  delivery_expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique (event, request_id),
  constraint account_deletion_email_recipient_check check (
    recipient_email = lower(btrim(recipient_email))
    and char_length(recipient_email) between 3 and 254
    and recipient_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  )
);

create index account_deletion_email_outbox_due_idx
  on app_private.account_deletion_email_outbox(next_attempt_at, created_at)
  where status in ('pending', 'processing');

alter table app_private.account_deletion_email_outbox enable row level security;
revoke all on table app_private.account_deletion_email_outbox
  from public, anon, authenticated;
grant select, insert, update on table app_private.account_deletion_email_outbox
  to service_role;

create or replace function app_private.enqueue_account_deletion_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event text;
  v_email text := lower(btrim(coalesce(new.email, '')));
begin
  if tg_op = 'INSERT' and new.status = 'requested' then
    v_event := 'deletion_requested';
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'requested' then
      v_event := 'deletion_requested';
    elsif new.status = 'completed' then
      v_event := 'account_deleted';
    end if;
  end if;

  if v_event is null or char_length(v_email) not between 3 and 254
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return new;
  end if;

  insert into app_private.account_deletion_email_outbox(
    request_id,
    event,
    recipient_email
  ) values (new.id, v_event, v_email)
  on conflict (event, request_id) do nothing;
  return new;
end;
$$;

revoke all on function app_private.enqueue_account_deletion_email()
  from public, anon, authenticated;

create trigger enqueue_account_deletion_email_after_insert
after insert on public.account_deletion_requests
for each row execute function app_private.enqueue_account_deletion_email();

create trigger enqueue_account_deletion_email_after_status_change
after update of status on public.account_deletion_requests
for each row execute function app_private.enqueue_account_deletion_email();

create or replace function public.claim_account_deletion_emails(
  p_limit integer default 20
)
returns table(
  outbox_id uuid,
  lease_token uuid,
  recipient_email text,
  event text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'claim limit must be between 1 and 50' using errcode = '22023';
  end if;

  update app_private.account_deletion_email_outbox email
  set status = 'failed', lease_token = null, lease_expires_at = null,
    last_error = 'Delivery window expired', updated_at = clock_timestamp()
  where email.status in ('pending', 'processing')
    and (email.delivery_expires_at <= clock_timestamp() or email.attempt_count >= 8);

  return query with candidates as (
    select email.id
    from app_private.account_deletion_email_outbox email
    where email.status in ('pending', 'processing')
      and email.next_attempt_at <= clock_timestamp()
      and email.delivery_expires_at > clock_timestamp()
      and email.attempt_count < 8
      and (email.status = 'pending' or email.lease_expires_at <= clock_timestamp())
    order by email.next_attempt_at, email.created_at
    for update skip locked
    limit p_limit
  ), claimed as (
    update app_private.account_deletion_email_outbox email
    set status = 'processing', attempt_count = email.attempt_count + 1,
      lease_token = gen_random_uuid(),
      lease_expires_at = clock_timestamp() + interval '5 minutes',
      updated_at = clock_timestamp()
    from candidates
    where email.id = candidates.id
    returning email.id, email.lease_token, email.recipient_email,
      email.event, email.attempt_count
  )
  select claimed.id, claimed.lease_token, claimed.recipient_email,
    claimed.event, claimed.attempt_count
  from claimed;
end;
$$;

create or replace function public.finish_account_deletion_email(
  p_outbox_id uuid,
  p_lease_token uuid,
  p_sent boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email app_private.account_deletion_email_outbox%rowtype;
  v_status text;
begin
  if current_user <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  select email.* into v_email
  from app_private.account_deletion_email_outbox email
  where email.id = p_outbox_id and email.status = 'processing'
    and email.lease_token = p_lease_token
  for update;
  if not found then
    raise exception 'email delivery lease was not found' using errcode = 'P0002';
  end if;

  if p_sent then
    v_status := 'sent';
    update app_private.account_deletion_email_outbox
    set status = 'sent',
      provider_message_id = left(nullif(btrim(p_provider_message_id), ''), 200),
      last_error = null, sent_at = clock_timestamp(), lease_token = null,
      lease_expires_at = null, updated_at = clock_timestamp()
    where id = p_outbox_id;
  elsif v_email.attempt_count >= 8
    or v_email.delivery_expires_at <= clock_timestamp() then
    v_status := 'failed';
    update app_private.account_deletion_email_outbox
    set status = 'failed',
      last_error = left(coalesce(nullif(btrim(p_error), ''), 'Provider delivery failed'), 500),
      lease_token = null, lease_expires_at = null,
      updated_at = clock_timestamp()
    where id = p_outbox_id;
  else
    v_status := 'pending';
    update app_private.account_deletion_email_outbox
    set status = 'pending',
      next_attempt_at = clock_timestamp() + make_interval(mins => least(60,
        power(2::numeric, greatest(v_email.attempt_count - 1, 0))::integer)),
      last_error = left(coalesce(nullif(btrim(p_error), ''), 'Provider delivery failed'), 500),
      lease_token = null, lease_expires_at = null,
      updated_at = clock_timestamp()
    where id = p_outbox_id;
  end if;
  return v_status;
end;
$$;

revoke all on function public.claim_account_deletion_emails(integer),
  public.finish_account_deletion_email(uuid, uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.claim_account_deletion_emails(integer),
  public.finish_account_deletion_email(uuid, uuid, boolean, text, text)
  to service_role;
