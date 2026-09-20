-- Bind provider credentials to the Auth session that registered them. The
-- binding is nullable for already-installed apps: do not guess a user's session
-- or couple this app table to Auth's internal lifecycle with foreign keys or
-- triggers. Both existing RPC signatures bind on their next authenticated call.
alter table public.push_tokens add column auth_session_id uuid;
comment on column public.push_tokens.auth_session_id is
  'Validated registering Auth session. Unbound legacy tokens cannot receive new delivery until the app re-registers.';

-- Invoked only inside the existing privileged registration/enqueue/claim
-- boundary. No role is granted a new Auth-table lookup or metadata API.
create function app_private.push_token_session_is_active(
  p_session_id uuid, p_user_id uuid, p_at timestamptz default now()
) returns boolean language sql stable security invoker set search_path = '' as $$
  select p_session_id is not null and p_user_id is not null and exists (
    select 1 from auth.sessions session
     where session.id = p_session_id and session.user_id = p_user_id
       and (session.not_after is null or session.not_after > p_at)
  );
$$;
revoke all on function app_private.push_token_session_is_active(uuid,uuid,timestamptz)
  from public, anon, authenticated, service_role;

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
  v_session_id uuid;
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
  -- Recheck after waiting for this token's registration lock. A JWT can still
  -- be cryptographically valid after sign-out has removed its Auth session.
  begin
    v_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'active session required' using errcode = '42501';
  end;
  if not app_private.push_token_session_is_active(
    v_session_id, v_user_id, clock_timestamp()) then
    raise exception 'active session required' using errcode = '42501';
  end if;
  select id into v_id from public.push_tokens where token = v_token for update;
  update app_private.push_delivery_outbox delivery
     set status = 'failed', last_error_code = case
           when token.user_id <> v_user_id or token.workspace_id <> p_workspace_id
           then 'device_account_changed' else 'device_session_changed' end,
         lease_token = null, lease_expires_at = null, updated_at = now()
    from public.push_tokens token
   where token.id = v_id and delivery.push_token_id = token.id
     and (token.user_id <> v_user_id or token.workspace_id <> p_workspace_id
       or token.auth_session_id is distinct from v_session_id)
     and delivery.status in ('pending', 'processing');

  insert into public.push_tokens(
    workspace_id,
    user_id,
    auth_session_id,
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
    v_session_id,
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
      auth_session_id = excluded.auth_session_id,
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
     and app_private.push_token_session_is_active(token.auth_session_id, token.user_id)
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
           token.auth_session_id, token.user_id,
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
    -- Signed-out or legacy unbound devices cannot receive queued business
    -- alerts. Retain the token so the next real sign-in can re-register it.
    if not app_private.push_token_session_is_active(
      v_delivery.auth_session_id, v_delivery.user_id) then
      update app_private.push_delivery_outbox
         set status = 'failed', last_error_code = 'push_session_inactive',
             lease_token = null, lease_expires_at = null, updated_at = now()
       where id = v_delivery.id;
      continue;
    end if;
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

notify pgrst, 'reload schema';
