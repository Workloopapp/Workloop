begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(43);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.service_add_ons'::regclass),
  'service add-ons have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.booking_request_items'::regclass),
  'booking request snapshots have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.appointment_items'::regclass),
  'appointment snapshots have RLS enabled'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_public_booking_request_v3(uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[])',
    'EXECUTE'
  ),
  'anonymous clients cannot call the service-role intake RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_public_booking_request_v3(uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[])',
    'EXECUTE'
  ),
  'authenticated clients cannot call the service-role intake RPC directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.create_public_booking_request_v3(uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[])',
    'EXECUTE'
  ),
  'service role can call the v3 intake RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_booking_slot_suggestions_v2(text,uuid,text,uuid[])',
    'EXECUTE'
  ),
  'anonymous customers cannot call the add-on availability RPC directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_public_booking_slot_suggestions_v2(text,uuid,text,uuid[])',
    'EXECUTE'
  ),
  'signed-in clients cannot bypass the availability Edge boundary'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.get_public_booking_slot_suggestions_v2(text,uuid,text,uuid[])',
    'EXECUTE'
  ),
  'availability Edge service role can request add-on-aware suggestions'
);
select has_function(
  'public',
  'get_public_booking_slot_suggestions_v3',
  array['text', 'uuid', 'text', 'uuid[]', 'date'],
  'target-date availability RPC exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_booking_slot_suggestions_v3(text,uuid,text,uuid[],date)',
    'EXECUTE'
  ),
  'anonymous customers cannot call target-date availability directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_public_booking_slot_suggestions_v3(text,uuid,text,uuid[],date)',
    'EXECUTE'
  ),
  'signed-in clients cannot call target-date availability directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.get_public_booking_slot_suggestions_v3(text,uuid,text,uuid[],date)',
    'EXECUTE'
  ),
  'availability Edge service role can request one selected date'
);
select has_index(
  'public',
  'booking_request_items',
  'booking_request_items_workspace_source_service_idx',
  'booking-request service-source foreign keys have a covering index'
);
select has_index(
  'public',
  'booking_request_items',
  'booking_request_items_workspace_source_add_on_idx',
  'booking-request add-on-source foreign keys have a covering index'
);
select has_index(
  'public',
  'appointment_items',
  'appointment_items_workspace_source_service_idx',
  'appointment service-source foreign keys have a covering index'
);
select has_index(
  'public',
  'appointment_items',
  'appointment_items_workspace_source_add_on_idx',
  'appointment add-on-source foreign keys have a covering index'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token
) values
  (
    '31000000-0000-4000-8000-000000000001', 'authenticated',
    'authenticated', 'addons-a@example.invalid', '', now(), now(), now(), '', ''
  ),
  (
    '32000000-0000-4000-8000-000000000002', 'authenticated',
    'authenticated', 'addons-b@example.invalid', '', now(), now(), now(), '', ''
  );

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('31000000-0000-4000-8000-000000000101','31000000-0000-4000-8000-000000000001',now(),now());

insert into public.workspaces(id, name) values
  ('31100000-0000-4000-8000-000000000001', 'Add-ons Workspace A'),
  ('32200000-0000-4000-8000-000000000002', 'Add-ons Workspace B');
insert into public.workspace_members(workspace_id, user_id) values
  ('31100000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001'),
  ('32200000-0000-4000-8000-000000000002', '32000000-0000-4000-8000-000000000002');
insert into public.services(id, workspace_id, name, duration_mins, price) values
  ('31110000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001', 'Window clean', 60, 50),
  ('32220000-0000-4000-8000-000000000002', '32200000-0000-4000-8000-000000000002', 'Other tenant service', 45, 40);

set local role authenticated;
select set_config('request.jwt.claim.sub', '31000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"31000000-0000-4000-8000-000000000101"}',
  true
);

insert into public.service_add_ons(
  id, workspace_id, service_id, name, duration_mins, price, position
) values (
  '31111000-0000-4000-8000-000000000001',
  '31100000-0000-4000-8000-000000000001',
  '31110000-0000-4000-8000-000000000001',
  'Frames and sills', 15, 12, 0
);
select is(
  (select count(*)::bigint from public.service_add_ons),
  1::bigint,
  'a member can create and read an add-on in their workspace'
);

select throws_ok(
  $$
    insert into public.service_add_ons(
      workspace_id, service_id, name, duration_mins, price
    ) values (
      '32200000-0000-4000-8000-000000000002',
      '32220000-0000-4000-8000-000000000002',
      'Forbidden extra', 5, 5
    )
  $$,
  '42501',
  null,
  'a member cannot create an add-on in another workspace'
);

select throws_ok(
  $$
    insert into public.booking_request_items(
      workspace_id, booking_request_id, item_kind, name, duration_mins, price, position
    ) values (
      '31100000-0000-4000-8000-000000000001',
      gen_random_uuid(), 'base', 'Forged item', 10, 1, 0
    )
  $$,
  '42501',
  null,
  'authenticated clients cannot forge booking request snapshots'
);

select throws_ok(
  $$
    insert into public.appointment_items(
      workspace_id, appointment_id, item_kind, name, duration_mins, price, position
    ) values (
      '31100000-0000-4000-8000-000000000001',
      gen_random_uuid(), 'base', 'Forged item', 10, 1, 0
    )
  $$,
  '42501',
  null,
  'authenticated clients cannot forge appointment snapshots'
);

reset role;
insert into public.business_profiles(workspace_id, handle, booking_mode)
values ('31100000-0000-4000-8000-000000000001', 'addons-quality-a', 'manual');
insert into public.workspace_settings(workspace_id, timezone)
values ('31100000-0000-4000-8000-000000000001', 'Europe/London')
on conflict (workspace_id) do update set timezone = excluded.timezone;
-- The newer JSON JWT claims remain present even when the legacy role GUC is absent.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', '', true);
set local role service_role;

select lives_ok(
  $test$
    create temporary table add_on_request_result as
    select * from public.create_public_booking_request_v3(
      '31100000-0000-4000-8000-000000000001',
      'Public Customer',
      '07123456789',
      'customer@example.invalid',
      '31110000-0000-4000-8000-000000000001',
      null,
      now() + interval '1 day',
      'Europe/London',
      null,
      repeat('a', 64),
      '31111111-0000-4000-8000-000000000001',
      array['31111000-0000-4000-8000-000000000001'::uuid]
    )
  $test$,
  'the service-role ACL works without a legacy JWT role claim'
);

select is(
  (select outcome from add_on_request_result),
  'created',
  'v3 creates a request using trusted catalog identifiers'
);
select is(
  (
    select count(*)::bigint
    from public.booking_request_items item
    join add_on_request_result result
      on result.booking_request_id = item.booking_request_id
  ),
  2::bigint,
  'v3 snapshots the base service and selected add-on'
);
select is(
  (
    select sum(item.duration_mins)::bigint
    from public.booking_request_items item
    join add_on_request_result result
      on result.booking_request_id = item.booking_request_id
  ),
  75::bigint,
  'snapshot duration comes from trusted catalog values'
);
select is(
  (
    select sum(item.price)::numeric
    from public.booking_request_items item
    join add_on_request_result result
      on result.booking_request_id = item.booking_request_id
  ),
  62::numeric,
  'snapshot price comes from trusted catalog values'
);
select is(
  (
    select string_agg(item.name, ', ' order by item.position)
    from public.booking_request_items item
    join add_on_request_result result
      on result.booking_request_id = item.booking_request_id
  ),
  'Window clean, Frames and sills',
  'snapshot names preserve the selected service breakdown'
);

create temporary table duplicate_request_result as
select * from public.create_public_booking_request_v3(
  '31100000-0000-4000-8000-000000000001',
  'Public Customer',
  '07123456789',
  'customer@example.invalid',
  '31110000-0000-4000-8000-000000000001',
  null,
  now() + interval '1 day',
  'Europe/London',
  null,
  repeat('a', 64),
  '31111111-0000-4000-8000-000000000001',
  '{}'::uuid[]
);
select is(
  (select outcome from duplicate_request_result),
  'duplicate',
  'request-token retries preserve the original item snapshots'
);
select is(
  (
    select count(*)::bigint
    from public.booking_requests
    where workspace_id = '31100000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'a duplicate token does not create a second request'
);

create temporary table invalid_add_on_result as
select * from public.create_public_booking_request_v3(
  '31100000-0000-4000-8000-000000000001',
  'Public Customer',
  '07123456789',
  'customer@example.invalid',
  '31110000-0000-4000-8000-000000000001',
  null,
  now() + interval '1 day',
  'Europe/London',
  null,
  repeat('b', 64),
  '31111111-0000-4000-8000-000000000002',
  array['32220000-0000-4000-8000-000000000002'::uuid]
);
select is(
  (select outcome from invalid_add_on_result),
  'invalid_add_on',
  'cross-service or unknown add-on IDs are rejected before insertion'
);

select is(
  public.get_public_booking_slot_suggestions_v2(
    'addons-quality-a',
    '31110000-0000-4000-8000-000000000001',
    repeat('c', 64),
    array['31111000-0000-4000-8000-000000000001'::uuid]
  ) ->> 'durationMinutes',
  '75',
  'suggested-slot duration includes trusted active add-on duration'
);
select is(
  public.get_public_booking_slot_suggestions_v2(
    'addons-quality-a',
    '31110000-0000-4000-8000-000000000001',
    repeat('d', 64),
    array['32220000-0000-4000-8000-000000000002'::uuid]
  ) ->> 'outcome',
  'invalid_add_on',
  'availability rejects add-ons outside the selected public service'
);

update public.workspace_settings
   set working_hours = '{
     "mon":{"enabled":true,"start":"09:00","end":"18:00"},
     "tue":{"enabled":true,"start":"09:00","end":"18:00"},
     "wed":{"enabled":true,"start":"09:00","end":"18:00"},
     "thu":{"enabled":true,"start":"09:00","end":"18:00"},
     "fri":{"enabled":true,"start":"09:00","end":"18:00"},
     "sat":{"enabled":true,"start":"09:00","end":"18:00"},
     "sun":{"enabled":true,"start":"09:00","end":"18:00"}
   }'::jsonb,
       min_booking_notice_hours = 0,
       max_booking_window_weeks = 12
 where workspace_id = '31100000-0000-4000-8000-000000000001';

create temporary table target_date_availability(payload jsonb);
insert into target_date_availability(payload)
select public.get_public_booking_slot_suggestions_v3(
  'addons-quality-a',
  '31110000-0000-4000-8000-000000000001',
  repeat('e', 64),
  '{}'::uuid[],
  (now() at time zone 'Europe/London')::date + 14
);
select is(
  jsonb_array_length((select payload -> 'days' from target_date_availability)),
  1,
  'a future target date returns only that day when it has suggestions'
);
select is(
  (select payload -> 'days' -> 0 ->> 'date' from target_date_availability),
  to_char((now() at time zone 'Europe/London')::date + 14, 'YYYY-MM-DD'),
  'target-date suggestions use the requested workspace-local date'
);
reset role;

-- A completed direct-booking retry must resolve from the stable workflow
-- result before checking today's mutable add-on catalogue.
create temporary table direct_booking_payload(payload jsonb);
grant select on direct_booking_payload to authenticated;
insert into direct_booking_payload values (jsonb_build_object(
  'workspace_id', '31100000-0000-4000-8000-000000000001',
  'idempotency_key', 'direct-booking-with-add-on:31111111-0000-4000-8000-000000000004',
  'service_id', '31110000-0000-4000-8000-000000000001',
  'add_on_ids', jsonb_build_array('31111000-0000-4000-8000-000000000001'),
  'new_contact', jsonb_build_object(
    'name', 'Direct Customer',
    'phone', '07123456770',
    'email', 'direct.customer@example.invalid'
  ),
  'appointments', jsonb_build_array(jsonb_build_object(
    'start_time', (clock_timestamp() + interval '5 days')::text,
    'end_time', (clock_timestamp() + interval '5 days 75 minutes')::text
  )),
  'price', 62,
  'title', 'Direct add-on booking',
  'notification_title', 'New booking created',
  'notification_body', 'A direct booking was added to the calendar.'
));

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"31000000-0000-4000-8000-000000000101"}', true);
select lives_ok(
  'select public.create_booking_workflow(payload) from direct_booking_payload',
  'a direct booking with an active add-on succeeds'
);
reset role;

update public.service_add_ons
   set active = false
 where id = '31111000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"31000000-0000-4000-8000-000000000101"}', true);
select lives_ok(
  'select public.create_booking_workflow(payload) from direct_booking_payload',
  'the completed retry survives later add-on deactivation'
);
reset role;

select is(
  (
    select count(*)::bigint
      from public.appointments
     where workspace_id = '31100000-0000-4000-8000-000000000001'
       and title = 'Direct add-on booking'
  ),
  1::bigint,
  'the idempotent retry does not create a second appointment'
);
select is(
  (
    select count(*)::bigint
      from public.appointment_items item
      join public.appointments appointment on appointment.id = item.appointment_id
     where appointment.workspace_id = '31100000-0000-4000-8000-000000000001'
       and appointment.title = 'Direct add-on booking'
  ),
  2::bigint,
  'the original immutable base and add-on snapshots remain intact'
);

-- Build 6 payloads still use the unstructured v2 overload during the staged
-- Edge rollout. The base-snapshot trigger must protect that path too, and the
-- current outer wrapper must preserve both appointment snapshots and the
-- existing confirmation-email transaction.
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table legacy_request_result as
select * from public.create_public_booking_request_v2(
  '31100000-0000-4000-8000-000000000001',
  'Legacy Customer',
  '07123456780',
  'legacy.customer@example.invalid',
  '31110000-0000-4000-8000-000000000001',
  'Friday morning',
  null,
  repeat('e', 64),
  '31111111-0000-4000-8000-000000000003'
);

select is(
  (select outcome from legacy_request_result),
  'created',
  'legacy v2 intake remains available during the staged rollout'
);
select is(
  (
    select string_agg(item.item_kind || ':' || item.name, ', ' order by item.position)
      from public.booking_request_items item
      join legacy_request_result result
        on result.booking_request_id = item.booking_request_id
  ),
  'base:Window clean',
  'legacy v2 intake receives an automatic trusted base snapshot'
);

reset role;
create temporary table legacy_confirmation_payload(payload jsonb);
grant select on legacy_confirmation_payload to authenticated;
insert into legacy_confirmation_payload values (jsonb_build_object(
  'workspace_id', '31100000-0000-4000-8000-000000000001',
  'idempotency_key', 'booking-request-confirm:31111111-0000-4000-8000-000000000003',
  'booking_request_id', (select booking_request_id from legacy_request_result),
  'service_id', '31110000-0000-4000-8000-000000000001',
  'new_contact', jsonb_build_object(
    'name', 'Legacy Customer',
    'phone', '07123456780',
    'email', 'legacy.customer@example.invalid',
    'notes', 'Created from a legacy public booking request.'
  ),
  'reuse_contact_by_phone', true,
  'appointments', jsonb_build_array(jsonb_build_object(
    'start_time', (clock_timestamp() + interval '3 days')::text,
    'end_time', (clock_timestamp() + interval '3 days 1 hour')::text
  )),
  'price', 50,
  'title', 'Legacy window clean',
  'notification_title', 'Booking request confirmed',
  'notification_body', 'A booking request was added to the calendar.'
));

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"31000000-0000-4000-8000-000000000101"}', true);
select lives_ok(
  'select public.create_booking_workflow(payload) from legacy_confirmation_payload',
  'legacy request confirmation passes through the current wrapper chain'
);
reset role;

select is(
  (
    select string_agg(item.item_kind || ':' || item.name, ', ' order by item.position)
      from public.appointment_items item
      join public.appointments appointment on appointment.id = item.appointment_id
     where appointment.workspace_id = '31100000-0000-4000-8000-000000000001'
       and appointment.title = 'Legacy window clean'
  ),
  'base:Window clean',
  'legacy confirmation copies the immutable request snapshot to the appointment'
);
select is(
  (
    select count(*)::bigint
      from app_private.transactional_email_outbox email
      join legacy_request_result result
        on result.booking_request_id = email.booking_request_id
     where email.event = 'booking_request_confirmed'
  ),
  1::bigint,
  'snapshot wrapping preserves the confirmation-email outbox side effect'
);

rollback;
