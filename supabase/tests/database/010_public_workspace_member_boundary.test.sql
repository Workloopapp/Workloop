begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select has_function(
  'app_private',
  'require_booking_request_workspace_member',
  array[]::text[],
  'booking-request ownership trigger exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'app_private.require_booking_request_workspace_member()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke the ownership trigger directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app_private.require_booking_request_workspace_member()',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the ownership trigger directly'
);
select ok(
  not has_function_privilege(
    'service_role',
    'app_private.require_booking_request_workspace_member()',
    'EXECUTE'
  ),
  'the service role cannot bypass the trigger through direct execution'
);

insert into public.workspaces(id, name)
values ('a2000000-0000-4000-8000-000000000001', 'Orphaned Studio');

select throws_ok(
  $$insert into public.booking_requests(workspace_id, name, phone)
    values (
      'a2000000-0000-4000-8000-000000000001',
      'Orphan request',
      '07123456789'
    )$$,
  '23514',
  'booking requests require an active workspace member',
  'orphaned workspaces cannot receive booking requests'
);

insert into auth.users(
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  created_at,
  updated_at
)
values (
  'a1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'public-owner@example.test',
  '',
  now(),
  now()
);
insert into public.workspace_members(workspace_id, user_id)
values (
  'a2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001'
);

select lives_ok(
  $$insert into public.booking_requests(workspace_id, name, phone)
    values (
      'a2000000-0000-4000-8000-000000000001',
      'Owned request',
      '07123456789'
    )$$,
  'a workspace with a member can receive booking requests'
);

select * from finish();
rollback;
