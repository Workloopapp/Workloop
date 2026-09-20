-- Business-update choices must still apply when a queued alert is dispatched.
-- This adds no user data or settings: the policy is computed from the existing
-- notification, workspace timezone and notification_preferences row. Local
-- booking/task reminders remain separate device features.
create function app_private.push_delivery_policy(
  p_workspace_id uuid,
  p_notification_type text,
  p_notification_read boolean,
  p_now timestamptz default now()
)
returns table (skip_reason text, next_allowed_at timestamptz)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_preferences public.notification_preferences%rowtype;
  v_timezone text := 'UTC';
  v_local_now timestamp without time zone;
  v_enabled boolean;
begin
  skip_reason := null;
  next_allowed_at := p_now;
  if coalesce(p_notification_read, false) then
    skip_reason := 'notification_read';
    return next;
    return;
  end if;

  select * into v_preferences from public.notification_preferences
   where workspace_id = p_workspace_id;
  v_enabled := coalesce(v_preferences.all_notifications, true) and
    case p_notification_type
      when 'payment_received' then coalesce(v_preferences.payment_received, true)
      when 'payment' then coalesce(v_preferences.payment_received, true)
      when 'new_booking' then coalesce(v_preferences.new_booking, true)
      when 'booking' then coalesce(v_preferences.new_booking, true)
      when 'booking_request' then coalesce(v_preferences.booking_request, true)
      when 'no_show' then coalesce(v_preferences.no_show, true)
      when 'invoice_overdue' then coalesce(v_preferences.invoice_overdue, true)
      when 'lead_followup' then coalesce(v_preferences.lead_followup, true)
      when 'morning_digest' then coalesce(v_preferences.morning_digest, true)
      when 'weekly_summary' then coalesce(v_preferences.weekly_summary, true)
      when 'task_due' then coalesce(v_preferences.task_due_morning, false)
      when 'task' then coalesce(v_preferences.task_due_morning, false)
      else true
    end;
  if not v_enabled then
    skip_reason := 'notification_preferences_disabled';
    return next;
    return;
  end if;

  select coalesce(timezone, 'UTC') into v_timezone
    from public.workspace_settings where workspace_id = p_workspace_id;
  v_timezone := coalesce(v_timezone, 'UTC');
  begin
    v_local_now := p_now at time zone v_timezone;
  exception when invalid_parameter_value then
    -- A malformed legacy timezone must not break delivery for other businesses.
    v_timezone := 'UTC';
    v_local_now := p_now at time zone v_timezone;
  end;

  -- Quiet Sundays has always meant the morning brief only; payment/booking
  -- activity and independently scheduled device reminders are not suppressed.
  if p_notification_type = 'morning_digest'
     and coalesce(v_preferences.quiet_sundays, false)
     and extract(isodow from v_local_now) = 7 then
    skip_reason := 'sunday_morning_brief_disabled';
    return next;
    return;
  end if;

  if coalesce(v_preferences.quiet_hours_enabled, true) then
    if v_local_now::time < time '07:00' then
      next_allowed_at := (v_local_now::date + time '07:00') at time zone v_timezone;
    elsif v_local_now::time >= time '21:00' then
      next_allowed_at := (v_local_now::date + 1 + time '07:00') at time zone v_timezone;
    end if;
  end if;
  return next;
end;
$$;

revoke all on function app_private.push_delivery_policy(uuid,text,boolean,timestamptz)
  from public, anon, authenticated;
grant execute on function app_private.push_delivery_policy(uuid,text,boolean,timestamptz)
  to service_role;

create or replace function app_private.enqueue_notification_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_policy record;
begin
  select * into v_policy from app_private.push_delivery_policy(
    new.workspace_id, new.type, new.read, now());
  if v_policy.skip_reason is not null then return new; end if;

  insert into app_private.push_delivery_outbox(
    notification_id, push_token_id, workspace_id, next_attempt_at
  )
  select new.id, token.id, new.workspace_id, v_policy.next_allowed_at
    from public.push_tokens token
   where token.workspace_id = new.workspace_id
     and token.disabled_at is null
     and token.last_seen_at >= now() - interval '90 days'
  on conflict (notification_id, push_token_id) do nothing;
  return new;
end;
$$;

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
  deep_link text,
  apns_environment text
)
language plpgsql security definer set search_path = '' as $$
declare
  v_delivery record;
  v_policy record;
  v_lease_token uuid;
  v_claimed integer := 0;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  -- Scan a bounded page, including suppressed/deferred rows, so a disabled
  -- category at the front does not consume every useful claim in a small batch.
  for v_delivery in
    select delivery.id, delivery.workspace_id, token.id as token_id,
           token.token, token.platform, token.apns_environment,
           notification.type, notification.title, notification.body,
           notification.deep_link, notification.read
      from app_private.push_delivery_outbox delivery
      join public.push_tokens token
        on token.id = delivery.push_token_id
       and token.disabled_at is null
       and token.workspace_id = delivery.workspace_id
       and exists (select 1 from public.workspace_members member
         where member.workspace_id = token.workspace_id and member.user_id = token.user_id)
      join public.notifications notification
        on notification.id = delivery.notification_id
       and notification.workspace_id = token.workspace_id
     where (delivery.status = 'pending' or
            (delivery.status = 'processing' and delivery.lease_expires_at < now()))
       and delivery.next_attempt_at <= now()
     order by delivery.next_attempt_at, delivery.created_at, delivery.id
     limit 100
     for update of delivery skip locked
  loop
    exit when v_claimed >= v_limit;
    select * into v_policy from app_private.push_delivery_policy(
      v_delivery.workspace_id, v_delivery.type, v_delivery.read, now());

    if v_policy.skip_reason is not null then
      update app_private.push_delivery_outbox
         set status = 'failed', last_error_code = v_policy.skip_reason,
             lease_token = null, lease_expires_at = null, updated_at = now()
       where id = v_delivery.id;
      continue;
    end if;
    if v_policy.next_allowed_at > now() then
      update app_private.push_delivery_outbox
         set status = 'pending', next_attempt_at = v_policy.next_allowed_at,
             lease_token = null, lease_expires_at = null, updated_at = now()
       where id = v_delivery.id;
      continue;
    end if;

    v_lease_token := gen_random_uuid();
    update app_private.push_delivery_outbox
       set status = 'processing', attempt_count = attempt_count + 1,
           lease_token = v_lease_token, lease_expires_at = now() + interval '2 minutes',
           updated_at = now()
     where id = v_delivery.id;
    v_claimed := v_claimed + 1;
    return query select v_delivery.id, v_lease_token, v_delivery.token_id,
      v_delivery.token, v_delivery.platform, v_delivery.type, v_delivery.title,
      v_delivery.body, v_delivery.deep_link, v_delivery.apns_environment;
  end loop;
end;
$$;

revoke all on function public.claim_push_deliveries(integer)
  from public, anon, authenticated;
grant execute on function public.claim_push_deliveries(integer) to service_role;

comment on function app_private.push_delivery_policy(uuid,text,boolean,timestamptz) is
  'Computed business-update delivery policy, reapplied at enqueue and claim; local device reminders are independent.';
notify pgrst, 'reload schema';
