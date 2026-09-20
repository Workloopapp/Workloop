-- Build 6 remote push delivery.
--
-- The public notifications table remains the user-visible source of truth.
-- New rows are fanned out into a private, durable per-device outbox so provider
-- timeouts cannot lose an alert or duplicate it indefinitely.

alter table public.push_tokens
  add column if not exists app_build text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists disabled_at timestamptz;

-- A refreshed FCM token belongs to exactly one signed-in identity. Keeping the
-- same opaque provider token on two accounts could leak business alerts after
-- a device changes account.
delete from public.push_tokens older
using public.push_tokens newer
where older.token = newer.token
  and (
    older.last_seen_at < newer.last_seen_at
    or (
      older.last_seen_at = newer.last_seen_at
      and older.id::text < newer.id::text
    )
  );

alter table public.push_tokens
  drop constraint if exists push_tokens_user_id_token_key;
drop index if exists public.push_tokens_user_id_token_key;
create unique index if not exists push_tokens_token_uidx
  on public.push_tokens(token);
create index if not exists push_tokens_active_workspace_idx
  on public.push_tokens(workspace_id, last_seen_at desc)
  where disabled_at is null;

drop policy if exists "Members can manage push tokens"
  on public.push_tokens;
drop policy if exists "Users can read own push tokens"
  on public.push_tokens;
create policy "Users can read own push tokens"
on public.push_tokens for select
to authenticated
using (
  user_id = (select auth.uid())
  and app_private.is_workspace_member(workspace_id)
);

-- Token reassignment is intentionally owned by the validated RPCs below.
revoke insert, update, delete on table public.push_tokens from authenticated;
grant select on table public.push_tokens to authenticated;

create or replace function public.register_push_token(
  p_workspace_id uuid,
  p_token text,
  p_platform text,
  p_app_build text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(coalesce(p_token, ''));
  v_platform text := lower(trim(coalesce(p_platform, '')));
  v_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not app_private.is_workspace_member(p_workspace_id) then
    raise exception 'workspace membership required' using errcode = '42501';
  end if;
  if length(v_token) < 20 or length(v_token) > 4096 then
    raise exception 'invalid push token' using errcode = '22023';
  end if;
  if v_platform not in ('ios', 'android') then
    raise exception 'invalid push platform' using errcode = '22023';
  end if;

  insert into public.push_tokens(
    workspace_id,
    user_id,
    token,
    platform,
    app_build,
    last_seen_at,
    updated_at,
    disabled_at
  )
  values (
    p_workspace_id,
    v_user_id,
    v_token,
    v_platform,
    nullif(trim(coalesce(p_app_build, '')), ''),
    now(),
    now(),
    null
  )
  on conflict (token) do update
  set workspace_id = excluded.workspace_id,
      user_id = excluded.user_id,
      platform = excluded.platform,
      app_build = excluded.app_build,
      last_seen_at = now(),
      updated_at = now(),
      disabled_at = null
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.register_push_token(uuid, text, text, text)
  from public, anon;
grant execute on function public.register_push_token(uuid, text, text, text)
  to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_removed integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  delete from public.push_tokens
   where user_id = v_user_id
     and token = trim(coalesce(p_token, ''));
  get diagnostics v_removed = row_count;
  return v_removed > 0;
end;
$function$;

revoke all on function public.unregister_push_token(text)
  from public, anon;
grant execute on function public.unregister_push_token(text)
  to authenticated;

create table if not exists app_private.push_delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null
    references public.notifications(id) on delete cascade,
  push_token_id uuid not null
    references public.push_tokens(id) on delete cascade,
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(notification_id, push_token_id)
);

alter table app_private.push_delivery_outbox enable row level security;
revoke all on table app_private.push_delivery_outbox
  from public, anon, authenticated;
create index if not exists push_delivery_outbox_claim_idx
  on app_private.push_delivery_outbox(next_attempt_at, created_at)
  where status in ('pending', 'processing');

create or replace function app_private.enqueue_notification_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_timezone text := 'UTC';
  v_quiet_hours boolean := true;
  v_delivery_enabled boolean := true;
  v_local_created timestamp without time zone;
  v_next_attempt timestamptz := new.created_at;
begin
  select
    coalesce(settings.timezone, 'UTC'),
    coalesce(preference.quiet_hours_enabled, true),
    coalesce(preference.all_notifications, true)
      and case new.type
        when 'payment_received' then coalesce(preference.payment_received, true)
        when 'payment' then coalesce(preference.payment_received, true)
        when 'new_booking' then coalesce(preference.new_booking, true)
        when 'booking' then coalesce(preference.new_booking, true)
        when 'booking_request' then coalesce(preference.booking_request, true)
        when 'no_show' then coalesce(preference.no_show, true)
        when 'invoice_overdue' then coalesce(preference.invoice_overdue, true)
        when 'lead_followup' then coalesce(preference.lead_followup, true)
        when 'morning_digest' then coalesce(preference.morning_digest, true)
        when 'weekly_summary' then coalesce(preference.weekly_summary, true)
        else true
      end
  into v_timezone, v_quiet_hours, v_delivery_enabled
  from (select 1) seed
  left join public.workspace_settings settings
    on settings.workspace_id = new.workspace_id
  left join public.notification_preferences preference
    on preference.workspace_id = new.workspace_id;

  if not v_delivery_enabled then
    return new;
  end if;

  if v_quiet_hours then
    v_local_created := new.created_at at time zone v_timezone;
    if extract(hour from v_local_created) < 7 then
      v_next_attempt :=
        (v_local_created::date + time '07:00') at time zone v_timezone;
    elsif extract(hour from v_local_created) >= 21 then
      v_next_attempt :=
        (v_local_created::date + 1 + time '07:00') at time zone v_timezone;
    end if;
  end if;

  insert into app_private.push_delivery_outbox(
    notification_id,
    push_token_id,
    workspace_id,
    next_attempt_at
  )
  select new.id, token.id, new.workspace_id, v_next_attempt
    from public.push_tokens token
   where token.workspace_id = new.workspace_id
     and token.disabled_at is null
     and token.last_seen_at >= now() - interval '90 days'
  on conflict (notification_id, push_token_id) do nothing;

  return new;
end;
$function$;

drop trigger if exists enqueue_notification_push
  on public.notifications;
create trigger enqueue_notification_push
after insert on public.notifications
for each row execute function app_private.enqueue_notification_push();

create or replace function public.claim_push_deliveries(p_limit integer default 50)
returns table (
  delivery_id uuid,
  delivery_lease_token uuid,
  push_token_id uuid,
  device_token text,
  platform text,
  notification_type text,
  notification_title text,
  notification_body text,
  deep_link text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  return query
  with candidates as (
    select delivery.id
      from app_private.push_delivery_outbox delivery
      join public.push_tokens available_token
        on available_token.id = delivery.push_token_id
       and available_token.disabled_at is null
     where (
       delivery.status = 'pending'
       or (
         delivery.status = 'processing'
         and delivery.lease_expires_at < now()
       )
     )
       and delivery.next_attempt_at <= now()
     order by delivery.next_attempt_at, delivery.created_at
     for update skip locked
     limit greatest(1, least(coalesce(p_limit, 50), 100))
  ),
  claimed as (
    update app_private.push_delivery_outbox delivery
       set status = 'processing',
           attempt_count = delivery.attempt_count + 1,
           lease_token = gen_random_uuid(),
           lease_expires_at = now() + interval '2 minutes',
           updated_at = now()
      from candidates
     where delivery.id = candidates.id
     returning delivery.*
  )
  select
    claimed.id,
    claimed.lease_token,
    token.id,
    token.token,
    token.platform,
    notification.type,
    notification.title,
    notification.body,
    notification.deep_link
  from claimed
  join public.push_tokens token
    on token.id = claimed.push_token_id
   and token.disabled_at is null
  join public.notifications notification
    on notification.id = claimed.notification_id;
end;
$function$;

revoke all on function public.claim_push_deliveries(integer)
  from public, anon, authenticated;
grant execute on function public.claim_push_deliveries(integer)
  to service_role;

create or replace function public.finish_push_delivery(
  p_delivery_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_provider_message_id text default null,
  p_error_code text default null,
  p_disable_token boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_push_token_id uuid;
  v_attempt_count integer;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_outcome not in ('sent', 'retry', 'failed') then
    raise exception 'invalid push outcome' using errcode = '22023';
  end if;

  select push_token_id, attempt_count
    into v_push_token_id, v_attempt_count
    from app_private.push_delivery_outbox
   where id = p_delivery_id
     and lease_token = p_lease_token
     and status = 'processing'
   for update;
  if not found then return false; end if;

  if p_disable_token then
    update public.push_tokens
       set disabled_at = now(),
           updated_at = now()
     where id = v_push_token_id;
    update app_private.push_delivery_outbox
       set status = 'failed',
           last_error_code = 'device_token_invalid',
           lease_token = null,
           lease_expires_at = null,
           updated_at = now()
     where push_token_id = v_push_token_id
       and id <> p_delivery_id
       and status in ('pending', 'processing');
  end if;

  if p_outcome = 'sent' then
    update app_private.push_delivery_outbox
       set status = 'sent',
           provider_message_id = nullif(trim(coalesce(p_provider_message_id, '')), ''),
           last_error_code = null,
           sent_at = now(),
           lease_token = null,
           lease_expires_at = null,
           updated_at = now()
     where id = p_delivery_id;
  elsif p_outcome = 'retry' and v_attempt_count < 8 then
    update app_private.push_delivery_outbox
       set status = 'pending',
           next_attempt_at = now() + make_interval(
             mins => least(power(2, least(v_attempt_count, 6))::integer, 60)
           ),
           last_error_code = left(nullif(trim(coalesce(p_error_code, '')), ''), 120),
           lease_token = null,
           lease_expires_at = null,
           updated_at = now()
     where id = p_delivery_id;
  else
    update app_private.push_delivery_outbox
       set status = 'failed',
           last_error_code = left(nullif(trim(coalesce(p_error_code, '')), ''), 120),
           lease_token = null,
           lease_expires_at = null,
           updated_at = now()
     where id = p_delivery_id;
  end if;

  return true;
end;
$function$;

revoke all on function public.finish_push_delivery(
  uuid, uuid, text, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.finish_push_delivery(
  uuid, uuid, text, text, text, boolean
) to service_role;
