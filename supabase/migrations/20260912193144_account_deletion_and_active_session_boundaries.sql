-- Reuse the existing RLS/MFA entry point to require an actual, unrevoked
-- session. JWT expiry alone does not close access after sign-out/deletion.
create function app_private.account_session_is_active(p_user_id uuid, p_session_id uuid)
returns boolean language sql security definer set search_path='' as $$
  select exists (
    select 1 from auth.users u join auth.sessions s on s.user_id=u.id
    where u.id=p_user_id and s.id=p_session_id
      and u.deleted_at is null and u.email_confirmed_at is not null
      and nullif(btrim(u.email),'') is not null
      and (u.banned_until is null or u.banned_until<=clock_timestamp())
      and (s.not_after is null or s.not_after>clock_timestamp())
  );
$$;
revoke all on function app_private.account_session_is_active(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.account_session_is_active(uuid,uuid) to service_role;

create function app_private.current_user_session_is_active()
returns boolean language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
  begin sid:=nullif(auth.jwt()->>'session_id','')::uuid;
  exception when invalid_text_representation then return false; end;
  return app_private.account_session_is_active(auth.uid(),sid)
    and not public.current_account_deletion_pending();
end;
$$;
revoke all on function app_private.current_user_session_is_active() from public,anon;
grant execute on function app_private.current_user_session_is_active() to authenticated,service_role;

create function public.current_user_session_is_active()
returns boolean language sql security invoker set search_path='' as $$
  select app_private.current_user_session_is_active();
$$;
revoke all on function public.current_user_session_is_active() from public,anon;
grant execute on function public.current_user_session_is_active() to authenticated,service_role;

create or replace function app_private.current_user_meets_mfa_policy()
returns boolean language sql stable security definer set search_path='' as $$
  select case
    when not app_private.current_user_session_is_active() then false
    when exists(select 1 from auth.mfa_factors f
      where f.user_id=auth.uid() and f.status='verified')
      then coalesce(auth.jwt()->>'aal'='aal2',false)
    else true
  end;
$$;
comment on function app_private.current_user_meets_mfa_policy() is
  'Requires current verified, unbanned Auth user, unrevoked session, no pending deletion and AAL2 when MFA is enrolled.';

-- The lock is the same as the existing atomic implementation. Check access
-- AFTER taking it so a waiting onboarding call cannot race account deletion.
create or replace function public.complete_onboarding(
  business_name text, industry_name text, profile_handle text, service_rows jsonb,
  working_hours_value jsonb, revenue_target_value numeric, first_booking_value jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then
    raise exception 'Your sign-in is no longer active' using errcode='28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  if exists(select 1 from auth.users where id=auth.uid()
      and (email_confirmed_at is null or nullif(btrim(email),'') is null)) then
    raise exception 'Verify your account email before setting up your business' using errcode='42501';
  end if;
  if not app_private.current_user_session_is_active() then
    raise exception 'Your sign-in is no longer active' using errcode='28000';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'Multi-factor authentication is required' using errcode='42501';
  end if;
  return app_private.complete_onboarding_implementation(
    business_name,industry_name,profile_handle,service_rows,working_hours_value,
    revenue_target_value,first_booking_value);
end;
$$;

-- workspace_id already permits NULL for completion retries. A user-scoped
-- unique key also covers requests made before any workspace exists.
create unique index account_deletion_requests_one_open_account_idx
  on public.account_deletion_requests(requested_by_user_id)
  where status in ('requested','processing') and requested_by_user_id is not null;
alter table public.account_deletion_requests add column apple_revocation_status text
  not null default 'not_applicable'
  check(apple_revocation_status in ('not_applicable','revoked','manual_action_required'));

create function app_private.request_account_deletion_for_user(
  p_user_id uuid, p_session_id uuid, p_aal text,
  p_workspace_id uuid default null, p_apple_revocation text default 'not_applicable'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare wid uuid; workspace_count integer; request_row public.account_deletion_requests%rowtype;
begin
  if p_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  if not app_private.account_session_is_active(p_user_id,p_session_id) then
    raise exception 'Active verified session required' using errcode='28000';
  end if;
  if exists(select 1 from auth.mfa_factors where user_id=p_user_id and status='verified')
     and p_aal is distinct from 'aal2' then
    raise exception 'Multi-factor authentication is required' using errcode='42501';
  end if;
  if p_apple_revocation is null or p_apple_revocation not in ('not_applicable','revoked','manual_action_required') then
    raise exception 'Invalid provider deletion status' using errcode='22023';
  end if;
  select count(*),min(workspace_id::text)::uuid into workspace_count,wid
    from public.workspace_members where user_id=p_user_id;
  if workspace_count>1 then
    raise exception 'Multiple workspaces require ownership review' using errcode='42501';
  end if;
  if p_workspace_id is not null and p_workspace_id is distinct from wid then
    raise exception 'Workspace access denied' using errcode='42501';
  end if;
  if wid is not null then
    perform 1 from public.workspaces where id=wid for update;
    if (select count(*) from public.workspace_members where workspace_id=wid)<>1 then
      raise exception 'Only the sole workspace owner can delete this account' using errcode='42501';
    end if;
  end if;
  select * into request_row from public.account_deletion_requests
    where requested_by_user_id=p_user_id and status in ('requested','processing') for update;
  if not found then
    insert into public.account_deletion_requests(workspace_id,user_id,requested_by_user_id,email,status,requested_at,notes,apple_revocation_status)
      select wid,u.id,u.id,u.email,'requested',clock_timestamp(),
        'Deletion requested by authenticated account owner.',p_apple_revocation
      from auth.users u where u.id=p_user_id
      returning * into request_row;
  end if;
  -- Pending-state checks and revocation commit together. Even a captured JWT
  -- cannot retain business access while asynchronous provider cleanup runs.
  delete from auth.sessions where user_id=p_user_id;
  return jsonb_build_object('ok',true,'requestId',request_row.id,
    'status',request_row.status,'accessLocked',true,
    'appleRevocation',request_row.apple_revocation_status);
end;
$$;
revoke all on function app_private.request_account_deletion_for_user(uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function app_private.request_account_deletion_for_user(uuid,uuid,text,uuid,text) to service_role;

create function public.request_account_deletion_for_user(
  p_user_id uuid, p_session_id uuid, p_aal text,
  p_workspace_id uuid default null, p_apple_revocation text default 'not_applicable'
) returns jsonb language sql security invoker set search_path='' as $$
  select app_private.request_account_deletion_for_user(p_user_id,p_session_id,p_aal,p_workspace_id,p_apple_revocation);
$$;
revoke all on function public.request_account_deletion_for_user(uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.request_account_deletion_for_user(uuid,uuid,text,uuid,text) to service_role;

-- Public customers have no Auth session; publication instead needs a live,
-- verified owner who has not requested deletion. This is an account-security
-- boundary, not a new moderation/approval workflow.
create function app_private.workspace_has_active_owner(p_workspace_id uuid)
returns boolean language sql security definer set search_path='' as $$
  select exists(select 1 from public.workspace_members m join auth.users u on u.id=m.user_id
    where m.workspace_id=p_workspace_id and u.deleted_at is null
      and u.email_confirmed_at is not null and nullif(btrim(u.email),'') is not null
      and (u.banned_until is null or u.banned_until<=clock_timestamp())
      and not exists(select 1 from public.account_deletion_requests r
        where r.requested_by_user_id=u.id and r.status in ('requested','processing')));
$$;
revoke all on function app_private.workspace_has_active_owner(uuid) from public,anon,authenticated;
grant execute on function app_private.workspace_has_active_owner(uuid) to service_role;
create function public.is_public_workspace_active(p_workspace_id uuid)
returns boolean language sql security invoker set search_path='' as $$
  select app_private.workspace_has_active_owner(p_workspace_id);
$$;
revoke all on function public.is_public_workspace_active(uuid) from public,anon,authenticated;
grant execute on function public.is_public_workspace_active(uuid) to service_role;
create function public.is_public_profile_active(p_handle text)
returns boolean language sql security invoker set search_path='' as $$
  select exists(select 1 from public.business_profiles p
    where p.handle=lower(btrim(p_handle)) and app_private.workspace_has_active_owner(p.workspace_id));
$$;
revoke all on function public.is_public_profile_active(text) from public,anon,authenticated;
grant execute on function public.is_public_profile_active(text) to service_role;
create or replace function app_private.require_booking_request_workspace_member()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not app_private.workspace_has_active_owner(new.workspace_id) then
    raise exception 'Public profile is not available' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app_private.require_booking_request_workspace_member() from public,anon,authenticated;

-- Preserve the subscription contract's distinct expired-session diagnostic.
create or replace function app_private.get_workloop_access() returns jsonb
language plpgsql security definer set search_path='' as $$

declare uid uuid := auth.uid(); u auth.users%rowtype; beta boolean; eligible boolean;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into u from auth.users where id=uid and deleted_at is null;
  if not found or u.email_confirmed_at is null then
    raise exception 'A verified account is required' using errcode='42501';
  end if;
  if not app_private.current_user_session_is_active() then
    raise exception 'Active session required' using errcode='42501';
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
  if not app_private.current_user_session_is_active() then
    raise exception 'Active session required' using errcode='42501';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'MFA verification required' using errcode='42501';
  end if;
  if not exists(select 1 from auth.sessions where user_id=uid and id::text=auth.jwt()->>'session_id'
    and (not_after is null or not_after>clock_timestamp())) then
    raise exception 'Active session required' using errcode='42501';
  end if;
  return app_private.workloop_access_for(uid);
end; 

$$;

-- Preserve push registration diagnostics and recheck account state after its lock.
create or replace function app_private.register_push_token_with_environment(
 p_workspace_id uuid,p_token text,p_platform text,p_app_build text,p_apns_environment text
) returns uuid language plpgsql security definer set search_path='' as $$

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
  if not app_private.current_user_session_is_active() then
    raise exception 'active session required' using errcode='42501';
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
  if not app_private.current_user_session_is_active() or not app_private.push_token_session_is_active(
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


$$;
