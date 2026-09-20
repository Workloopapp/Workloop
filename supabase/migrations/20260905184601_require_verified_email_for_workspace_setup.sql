-- Phone verification proves control of a number, not an account email. Keep
-- onboarding's existing identity/deletion/MFA checks and require a real verified
-- email before its transactional workspace implementation can run.
create or replace function public.complete_onboarding(
  business_name text,
  industry_name text,
  profile_handle text,
  service_rows jsonb,
  working_hours_value jsonb,
  revenue_target_value numeric,
  first_booking_value jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not exists (
       select 1 from auth.users where id = (select auth.uid())
     ) then
    raise exception 'Your sign-in is no longer active'
      using errcode = '28000';
  end if;

  if public.current_account_deletion_pending() then
    raise exception 'Account deletion is already in progress'
      using errcode = '42501';
  end if;

  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'Multi-factor authentication is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from auth.users
    where id = (select auth.uid())
      and email_confirmed_at is not null
      and nullif(btrim(email), '') is not null
  ) then
    raise exception 'Verify your account email before setting up your business'
      using errcode = '42501';
  end if;

  return app_private.complete_onboarding_implementation(
    business_name,
    industry_name,
    profile_handle,
    service_rows,
    working_hours_value,
    revenue_target_value,
    first_booking_value
  );
end;
$$;

revoke all on function public.complete_onboarding(
  text, text, text, jsonb, jsonb, numeric, jsonb
) from public, anon;
grant execute on function public.complete_onboarding(
  text, text, text, jsonb, jsonb, numeric, jsonb
) to authenticated;
