create or replace function public.authorize_apple_reporting_collector(
  p_token text
)
returns boolean
language sql
security definer
set search_path = ''
as $function$
  select
    coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    and coalesce(
      extensions.digest(coalesce(p_token, ''), 'sha256') =
        extensions.digest(
          (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'apple_reporting_drain_token'
          ),
          'sha256'
        ),
      false
    );
$function$;

revoke all on function public.authorize_apple_reporting_collector(text)
  from public, anon, authenticated;
grant execute on function public.authorize_apple_reporting_collector(text)
  to service_role;

comment on function public.authorize_apple_reporting_collector(text) is
  'Service-role-only, digest-based authentication for the scheduled Apple reporting collector. The Vault token is never returned.';
