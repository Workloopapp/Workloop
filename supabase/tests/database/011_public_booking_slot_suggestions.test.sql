begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(13);

select has_function(
  'public',
  'get_public_booking_slot_suggestions',
  array['text', 'uuid', 'text', 'integer'],
  'public suggestion RPC exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_booking_slot_suggestions(text,uuid,text,integer)',
    'EXECUTE'
  ),
  'anonymous callers cannot bypass the Edge boundary'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_public_booking_slot_suggestions(text,uuid,text,integer)',
    'EXECUTE'
  ),
  'signed-in clients cannot inspect public availability directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.get_public_booking_slot_suggestions(text,uuid,text,integer)',
    'EXECUTE'
  ),
  'only the Edge service role can request suggestions'
);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password, created_at, updated_at
) values (
  'b1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'availability-owner@example.test',
  '',
  now(),
  now()
);
insert into public.workspaces(id, name)
values ('b2000000-0000-4000-8000-000000000001', 'Availability Studio');
insert into public.workspace_members(workspace_id, user_id) values (
  'b2000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001'
);
insert into public.workspace_settings(
  workspace_id,
  timezone,
  working_hours,
  min_booking_notice_hours,
  max_booking_window_weeks,
  buffer_mins
) values (
  'b2000000-0000-4000-8000-000000000001',
  'Europe/London',
  '{
    "mon":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "tue":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "wed":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "thu":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "fri":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "sat":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]},
    "sun":{"enabled":true,"blocks":[{"start":"09:00","end":"12:00"},{"start":"14:00","end":"18:00"}]}
  }'::jsonb,
  0,
  12,
  15
);
insert into public.business_profiles(workspace_id, handle, booking_mode) values (
  'b2000000-0000-4000-8000-000000000001',
  'availability-studio',
  'manual'
);
insert into public.services(
  id, workspace_id, name, duration_mins, price, active, show_on_profile
) values (
  'b3000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000001',
  'Private diary test service',
  60,
  75,
  true,
  true
);
insert into public.appointments(
  id, workspace_id, title, start_time, end_time, status
) values
  (
    'b4000000-0000-4000-8000-000000000001',
    'b2000000-0000-4000-8000-000000000001',
    'Private customer name',
    ((now() at time zone 'Europe/London')::date + 1 + time '09:00') at time zone 'Europe/London',
    ((now() at time zone 'Europe/London')::date + 1 + time '10:00') at time zone 'Europe/London',
    'scheduled'
  ),
  (
    'b4000000-0000-4000-8000-000000000002',
    'b2000000-0000-4000-8000-000000000001',
    'Cancelled private customer',
    ((now() at time zone 'Europe/London')::date + 1 + time '14:00') at time zone 'Europe/London',
    ((now() at time zone 'Europe/London')::date + 1 + time '18:00') at time zone 'Europe/London',
    'cancelled'
  );

create temporary table availability_result(payload jsonb);
grant insert, select on availability_result to service_role;
set local role service_role;
insert into availability_result(payload)
select public.get_public_booking_slot_suggestions(
  'availability-studio',
  'b3000000-0000-4000-8000-000000000001',
  repeat('a', 64)
);
reset role;

select is(
  (select payload ->> 'outcome' from availability_result),
  'ok',
  'published active service returns suggestions'
);
select is(
  (select payload ->> 'timezone' from availability_result),
  'Europe/London',
  'suggestions declare the workspace timezone'
);
select ok(
  jsonb_array_length((select payload -> 'days' from availability_result)) <= 5,
  'response contains at most five suggested days'
);
select ok(
  not exists (
    select 1
      from availability_result result,
           jsonb_array_elements(result.payload -> 'days') day,
           jsonb_array_elements_text(day -> 'slots') slots
     group by day
    having count(*) > 6
  ),
  'response contains at most six starts per day'
);
select ok(
  (select payload from availability_result) ?&
    array['outcome', 'timezone', 'durationMinutes', 'generatedAt', 'days'],
  'response exposes only useful availability metadata'
);
select ok(
  (select payload::text from availability_result) not like '%b4000000%'
    and (select payload::text from availability_result) not like '%Private customer%'
    and (select payload::text from availability_result) not like '%busy%'
    and (select payload::text from availability_result) not like '%count%',
  'response does not leak diary identifiers, names, intervals, or counts'
);
select ok(
  not exists (
    select 1
      from availability_result result,
           jsonb_array_elements(result.payload -> 'days') day,
           jsonb_array_elements_text(day -> 'slots') slot
     where slot::timestamptz <
       (((now() at time zone 'Europe/London')::date + 1 + time '10:15') at time zone 'Europe/London')
       and slot::timestamptz >
       (((now() at time zone 'Europe/London')::date + 1 + time '08:45') at time zone 'Europe/London')
  ),
  'scheduled work and its buffer are excluded'
);
select ok(
  exists (
    select 1
      from availability_result result,
           jsonb_array_elements(result.payload -> 'days') day,
           jsonb_array_elements_text(day -> 'slots') slot
     where (slot::timestamptz at time zone 'Europe/London')::time >= time '14:00'
  ),
  'cancelled work does not block later suggestions'
);

set local role service_role;
select is(
  public.get_public_booking_slot_suggestions(
    'availability-studio',
    'b3000000-0000-4000-8000-000000000099',
    repeat('b', 64)
  ) ->> 'outcome',
  'invalid_service',
  'unknown services are rejected without diary detail'
);
reset role;

select * from finish();
rollback;
