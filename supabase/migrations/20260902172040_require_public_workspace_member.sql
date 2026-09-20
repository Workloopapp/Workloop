-- A service-role Edge Function bypasses RLS. Keep orphaned workspaces from
-- accepting public booking requests even if an endpoint regression omits its
-- explicit workspace-member check.

create or replace function app_private.require_booking_request_workspace_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
      from public.workspace_members member
     where member.workspace_id = new.workspace_id
  ) then
    raise exception 'booking requests require an active workspace member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function app_private.require_booking_request_workspace_member()
  from public, anon, authenticated, service_role;

drop trigger if exists booking_requests_require_workspace_member
  on public.booking_requests;
create trigger booking_requests_require_workspace_member
before insert on public.booking_requests
for each row
execute function app_private.require_booking_request_workspace_member();
