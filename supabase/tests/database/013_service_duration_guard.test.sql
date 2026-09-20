begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(9);

select ok(
  exists (
    select 1
      from pg_constraint
     where conrelid = 'public.services'::regclass
       and conname = 'services_duration_mins_check'
       and contype = 'c'
       and convalidated
  ),
  'services have an authoritative duration check'
);

select is(
  (
    select count(*)::bigint
      from public.services
     where duration_mins not between 5 and 1440
  ),
  0::bigint,
  'the migration leaves no invalid service durations behind'
);

insert into public.workspaces(id, name)
values ('d1000000-0000-4000-8000-000000000001', 'Duration Guard Workspace');

select throws_ok(
  $$
    insert into public.services(workspace_id, name, duration_mins, price)
    values ('d1000000-0000-4000-8000-000000000001', 'Zero', 0, 10)
  $$,
  '23514',
  null,
  'zero-minute services are rejected'
);

select throws_ok(
  $$
    insert into public.services(workspace_id, name, duration_mins, price)
    values ('d1000000-0000-4000-8000-000000000001', 'Too short', 1, 10)
  $$,
  '23514',
  null,
  'services below five minutes are rejected'
);

select throws_ok(
  $$
    insert into public.services(workspace_id, name, duration_mins, price)
    values ('d1000000-0000-4000-8000-000000000001', 'Too long', 1441, 10)
  $$,
  '23514',
  null,
  'services beyond 24 hours are rejected'
);

select throws_ok(
  $$
    insert into public.services(workspace_id, name, duration_mins, price)
    values ('d1000000-0000-4000-8000-000000000001', 'Absurd', 9999999, 10)
  $$,
  '23514',
  null,
  'absurd service durations are rejected'
);

select lives_ok(
  $$
    insert into public.services(
      id, workspace_id, name, duration_mins, price
    ) values (
      'd1100000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000001',
      'Five minutes',
      5,
      10
    )
  $$,
  'the five-minute lower boundary is accepted'
);

select lives_ok(
  $$
    insert into public.services(
      id, workspace_id, name, duration_mins, price
    ) values (
      'd1200000-0000-4000-8000-000000000002',
      'd1000000-0000-4000-8000-000000000001',
      'Twenty-four hours',
      1440,
      10
    )
  $$,
  'the 24-hour upper boundary is accepted'
);

select throws_ok(
  $$
    update public.services
       set duration_mins = 9999999
     where id = 'd1100000-0000-4000-8000-000000000001'
  $$,
  '23514',
  null,
  'existing services cannot be updated to an absurd duration'
);

select * from finish();
rollback;
