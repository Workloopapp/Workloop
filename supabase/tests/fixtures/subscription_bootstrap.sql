-- Standalone PostgreSQL test bootstrap ONLY. Never a production migration.
-- Minimal Auth roles/tables/functions model the fields used by subscription SQL.
-- The MFA function below is copied from the actual Workloop migration.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create schema app_private;
create schema extensions;
grant usage on schema public,auth,app_private,extensions to anon,authenticated,service_role;
create table auth.users (
 id uuid primary key, instance_id uuid, aud text, role text, email text,
 encrypted_password text, email_confirmed_at timestamptz, deleted_at timestamptz,
 created_at timestamptz, updated_at timestamptz
);
create table auth.sessions (
 id uuid primary key, user_id uuid references auth.users(id) on delete cascade,
 created_at timestamptz, updated_at timestamptz, not_after timestamptz
);
create table auth.mfa_factors (
 id uuid primary key, user_id uuid references auth.users(id) on delete cascade,
 factor_type text, status text, secret text
);
create function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(auth.jwt()->>'sub','')::uuid
$$;
-- Users who opt in to MFA must present an AAL2 session before any direct
-- authenticated Data API access is allowed. Accounts without a verified
-- factor keep the existing AAL1 behaviour so rollout does not lock them out.
create or replace function app_private.current_user_meets_mfa_policy()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    when exists (
      select 1
      from auth.mfa_factors as factor
      where factor.user_id = (select auth.uid())
        and factor.status = 'verified'
    ) then coalesce((select auth.jwt() ->> 'aal') = 'aal2', false)
    else true
  end;
$$;

comment on function app_private.current_user_meets_mfa_policy() is
  'Requires an AAL2 JWT only when the current user has opted in with a verified MFA factor.';

revoke all on function app_private.current_user_meets_mfa_policy()
  from public, anon;
grant execute on function app_private.current_user_meets_mfa_policy()
  to authenticated, service_role;
