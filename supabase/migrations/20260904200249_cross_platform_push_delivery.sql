-- Keep APNs routing attached to the signed app token, rather than one global
-- worker setting. NULL preserves the fallback for already-installed clients.
alter table public.push_tokens add column if not exists apns_environment text;
alter table public.push_tokens add constraint push_tokens_apns_environment_check
  check (apns_environment is null or
    (platform = 'ios' and apns_environment in ('production', 'sandbox')));

create or replace function app_private.register_push_token_with_environment(
  p_workspace_id uuid,
  p_token text,
  p_platform text,
  p_app_build text,
  p_apns_environment text
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
  v_environment text := nullif(trim(coalesce(p_apns_environment, '')), '');
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'MFA verification required' using errcode = '42501';
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

  if v_environment is not null and (v_platform <> 'ios' or v_environment not in ('production', 'sandbox')) then
    raise exception 'invalid APNs environment' using errcode = '22023';
  end if;

  -- Invalidate queued work for the previous identity before token reassignment.
  -- The unique-token upsert serializes concurrent registrations.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_token, 0));
  select id into v_id from public.push_tokens where token = v_token for update;
  update app_private.push_delivery_outbox delivery
     set status = 'failed', last_error_code = 'device_account_changed',
         lease_token = null, lease_expires_at = null, updated_at = now()
    from public.push_tokens token
   where token.id = v_id and delivery.push_token_id = token.id
     and (token.user_id <> v_user_id or token.workspace_id <> p_workspace_id)
     and delivery.status in ('pending', 'processing');

  insert into public.push_tokens(
    workspace_id,
    user_id,
    token,
    platform,
    app_build,
    apns_environment,
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
    v_environment,
    now(),
    now(),
    null
  )
  on conflict (token) do update
  set workspace_id = excluded.workspace_id,
      user_id = excluded.user_id,
      platform = excluded.platform,
      app_build = excluded.app_build,
      apns_environment = case when excluded.platform = 'ios'
        then coalesce(excluded.apns_environment, public.push_tokens.apns_environment)
        else null end,
      last_seen_at = now(),
      updated_at = now(),
      disabled_at = null
  returning id into v_id;

  return v_id;
end;
$function$;


revoke all on function app_private.register_push_token_with_environment(uuid,text,text,text,text)
  from public, anon;
grant execute on function app_private.register_push_token_with_environment(uuid,text,text,text,text)
  to authenticated;

-- Preserve the exact four-argument signature used by Builds 6–9. Both public
-- entry points use the same private membership/MFA-checked implementation.
create or replace function public.register_push_token(
  p_workspace_id uuid, p_token text, p_platform text, p_app_build text default null
) returns uuid language sql security invoker set search_path = '' as $$
  select app_private.register_push_token_with_environment(
    p_workspace_id, p_token, p_platform, p_app_build, null);
$$;
create function public.register_push_token(
  p_workspace_id uuid, p_token text, p_platform text, p_app_build text,
  p_apns_environment text
) returns uuid language sql security invoker set search_path = '' as $$
  select app_private.register_push_token_with_environment(
    p_workspace_id, p_token, p_platform, p_app_build, p_apns_environment);
$$;
revoke all on function public.register_push_token(uuid,text,text,text) from public, anon;
revoke all on function public.register_push_token(uuid,text,text,text,text) from public, anon;
grant execute on function public.register_push_token(uuid,text,text,text) to authenticated;
grant execute on function public.register_push_token(uuid,text,text,text,text) to authenticated;

-- Return shape adds one field; old workers ignore it, while old apps never
-- call this service-role-only RPC. Recreate explicitly to change its row type.
drop function public.claim_push_deliveries(integer);
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
       and available_token.workspace_id = delivery.workspace_id
       and exists (select 1 from public.workspace_members member
         where member.workspace_id = available_token.workspace_id and member.user_id = available_token.user_id)
     where (
       delivery.status = 'pending'
       or (
         delivery.status = 'processing'
         and delivery.lease_expires_at < now()
       )
     )
       and delivery.next_attempt_at <= now()
     order by delivery.next_attempt_at, delivery.created_at
     for update of delivery skip locked
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
    notification.deep_link,
    token.apns_environment
  from claimed
  join public.push_tokens token
    on token.id = claimed.push_token_id
   and token.disabled_at is null
   and token.workspace_id = claimed.workspace_id
  join public.notifications notification
    on notification.id = claimed.notification_id
   and notification.workspace_id = token.workspace_id;
end;
$function$;

revoke all on function public.claim_push_deliveries(integer)
  from public, anon, authenticated;
grant execute on function public.claim_push_deliveries(integer)
  to service_role;


-- Preserve the existing six-argument finish API; the new optional provider
-- retry delay can only extend its exponential backoff, never shorten it.
create function public.finish_push_delivery(
  p_delivery_id uuid, p_lease_token uuid, p_outcome text,
  p_provider_message_id text, p_error_code text, p_disable_token boolean,
  p_retry_after_seconds integer
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_finished boolean;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  v_finished := public.finish_push_delivery(p_delivery_id, p_lease_token,
    p_outcome, p_provider_message_id, p_error_code, p_disable_token);
  if v_finished and p_outcome = 'retry' and p_retry_after_seconds > 0 then
    update app_private.push_delivery_outbox
       set next_attempt_at = greatest(next_attempt_at,
         now() + make_interval(secs => least(p_retry_after_seconds, 604800)))
     where id = p_delivery_id and status = 'pending';
  end if;
  return v_finished;
end;
$$;
revoke all on function public.finish_push_delivery(uuid,uuid,text,text,text,boolean,integer)
  from public, anon, authenticated;
grant execute on function public.finish_push_delivery(uuid,uuid,text,text,text,boolean,integer)
  to service_role;

notify pgrst, 'reload schema';
