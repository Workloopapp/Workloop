begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(28);

select has_column(
  'public',
  'booking_requests',
  'email',
  'public booking requests capture customer email'
);
select has_table(
  'app_private',
  'transactional_email_outbox',
  'transactional email intent is durable and private'
);
select has_index(
  'app_private',
  'transactional_email_outbox',
  'transactional_email_outbox_workspace_id_idx',
  'workspace deletion has a covering outbox foreign-key index'
);
select has_index(
  'app_private',
  'transactional_email_outbox',
  'transactional_email_outbox_booking_request_id_idx',
  'booking-request joins have a covering outbox foreign-key index'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'app_private.transactional_email_outbox',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'app_private.transactional_email_outbox',
    'SELECT'
  ),
  'client roles cannot read email recipient or body data'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_public_booking_request_v2(uuid,text,text,text,uuid,text,text,text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_booking_confirmation_emails(integer,uuid)',
    'EXECUTE'
  ),
  'public intake and delivery controls are service-role-only'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token
) values (
  '41000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'email-owner@example.invalid',
  '', now(), now(), now(), '', ''
);

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('41000000-0000-4000-8000-000000000101','41000000-0000-4000-8000-000000000001',now(),now());

insert into public.workspaces(id, name) values (
  '42000000-0000-4000-8000-000000000001',
  'Confirmation Studio'
);
insert into public.workspace_settings(workspace_id, timezone) values (
  '42000000-0000-4000-8000-000000000001',
  'Europe/London'
);
insert into public.workspace_members(workspace_id, user_id) values (
  '42000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000001'
);
insert into public.business_profiles(workspace_id, handle, booking_mode) values (
  '42000000-0000-4000-8000-000000000001',
  'confirmation-studio',
  'manual'
);
insert into public.contacts(id, workspace_id, name, phone, email, status) values
  (
    '43000000-0000-4000-8000-000000000001',
    '42000000-0000-4000-8000-000000000001',
    'Blank email client',
    '07123 456 781',
    null,
    'active'
  ),
  (
    '43000000-0000-4000-8000-000000000002',
    '42000000-0000-4000-8000-000000000001',
    'Known email client',
    '07123 456 782',
    'known@example.com',
    'active'
  );

set local role service_role;
select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

select is(
  (
    select outcome from public.create_public_booking_request_v2(
      '42000000-0000-4000-8000-000000000001',
      'First Customer',
      '07123 456 781',
      ' First.Customer@Example.COM ',
      null,
      'Tomorrow morning',
      null,
      repeat('a', 64),
      '44000000-0000-4000-8000-000000000001'
    )
  ),
  'created',
  'v2 creates a public request with email'
);
reset role;
select is(
  (
    select email from public.booking_requests
     where request_token = '44000000-0000-4000-8000-000000000001'
  ),
  'first.customer@example.com',
  'v2 stores normalized email'
);
set local role service_role;
select is(
  (
    select outcome from public.create_public_booking_request_v2(
      '42000000-0000-4000-8000-000000000001',
      'First Customer',
      '07123 456 781',
      'changed@example.com',
      null,
      'Tomorrow morning',
      null,
      repeat('a', 64),
      '44000000-0000-4000-8000-000000000001'
    )
  ),
  'duplicate',
  'the existing request token remains idempotent'
);
reset role;
select is(
  (
    select email from public.booking_requests
     where request_token = '44000000-0000-4000-8000-000000000001'
  ),
  'first.customer@example.com',
  'a duplicate token cannot mutate its original email'
);

set local role service_role;
select is(
  (
    select outcome from public.create_public_booking_request_v2(
      '42000000-0000-4000-8000-000000000001',
      'Second Customer',
      '07123 456 782',
      'request-two@example.com',
      null,
      'Next Tuesday',
      null,
      repeat('b', 64),
      '44000000-0000-4000-8000-000000000002'
    )
  ),
  'created',
  'a second bounded request is created for contact preservation coverage'
);
reset role;

create temporary table confirmation_payloads(label text primary key, payload jsonb);
grant select on confirmation_payloads to authenticated;
insert into confirmation_payloads values
  (
    'blank-email',
    jsonb_build_object(
      'workspace_id', '42000000-0000-4000-8000-000000000001',
      'idempotency_key', 'booking-request-confirm:44000000-0000-4000-8000-000000000001',
      'booking_request_id', (
        select id from public.booking_requests
         where request_token = '44000000-0000-4000-8000-000000000001'
      ),
      'new_contact', jsonb_build_object(
        'name', 'First Customer',
        'phone', '07123 456 781',
        'email', 'first.customer@example.com',
        'notes', 'Created from public request.'
      ),
      'reuse_contact_by_phone', true,
      'appointments', jsonb_build_array(jsonb_build_object(
        'start_time', (clock_timestamp() + interval '10 days')::text,
        'end_time', (clock_timestamp() + interval '10 days 1 hour')::text
      )),
      'price', 50,
      'title', 'Consultation',
      'location', 'Studio 1',
      'notification_title', 'Booking request confirmed',
      'notification_body', 'First Customer has been added.'
    )
  ),
  (
    'known-email',
    jsonb_build_object(
      'workspace_id', '42000000-0000-4000-8000-000000000001',
      'idempotency_key', 'booking-request-confirm:44000000-0000-4000-8000-000000000002',
      'booking_request_id', (
        select id from public.booking_requests
         where request_token = '44000000-0000-4000-8000-000000000002'
      ),
      'new_contact', jsonb_build_object(
        'name', 'Second Customer',
        'phone', '07123 456 782',
        'email', 'request-two@example.com',
        'notes', 'Created from public request.'
      ),
      'reuse_contact_by_phone', true,
      'appointments', jsonb_build_array(jsonb_build_object(
        'start_time', (clock_timestamp() + interval '11 days')::text,
        'end_time', (clock_timestamp() + interval '11 days 1 hour')::text
      )),
      'price', 75,
      'title', 'Follow-up',
      'notification_title', 'Booking request confirmed',
      'notification_body', 'Second Customer has been added.'
    )
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"41000000-0000-4000-8000-000000000101"}',
  true
);
select lives_ok(
  'select public.create_booking_workflow(payload) from confirmation_payloads where label = ''blank-email''',
  'owner confirmation commits booking and email intent together'
);
reset role;
select is(
  (
    select email from public.contacts
     where id = '43000000-0000-4000-8000-000000000001'
  ),
  'first.customer@example.com',
  'a reused contact with blank email is safely enriched'
);
select is(
  (
    select count(*)::bigint
      from app_private.transactional_email_outbox
     where booking_request_id = (
       select id from public.booking_requests
        where request_token = '44000000-0000-4000-8000-000000000001'
     )
  ),
  1::bigint,
  'confirmation creates exactly one durable outbox row'
);

set local role authenticated;
select lives_ok(
  'select public.create_booking_workflow(payload) from confirmation_payloads where label = ''blank-email''',
  'retry returns the stored booking result'
);
reset role;
select is(
  (
    select count(*)::bigint
      from app_private.transactional_email_outbox
     where booking_request_id = (
       select id from public.booking_requests
        where request_token = '44000000-0000-4000-8000-000000000001'
     )
  ),
  1::bigint,
  'workflow retry cannot duplicate the email intent'
);
select is(
  (
    select count(*)::bigint from public.appointments
     where workspace_id = '42000000-0000-4000-8000-000000000001'
       and title = 'Consultation'
  ),
  1::bigint,
  'workflow retry cannot duplicate the appointment'
);

set local role authenticated;
select lives_ok(
  'select public.create_booking_workflow(payload) from confirmation_payloads where label = ''known-email''',
  'a second request with an existing phone converts successfully'
);
reset role;
select is(
  (
    select email from public.contacts
     where id = '43000000-0000-4000-8000-000000000002'
  ),
  'known@example.com',
  'a different existing contact email is never overwritten silently'
);
select is(
  (
    select recipient_email
      from app_private.transactional_email_outbox
     where booking_request_id = (
       select id from public.booking_requests
        where request_token = '44000000-0000-4000-8000-000000000002'
     )
  ),
  'request-two@example.com',
  'confirmation remains addressed to the request email'
);

create temporary table claimed_email as
select null::uuid outbox_id, null::uuid booking_request_id,
  null::uuid lease_token, null::text recipient_email,
  null::jsonb payload, null::integer attempt_count
where false;
grant insert, select on claimed_email to service_role;
create temporary table target_request as
select id from public.booking_requests
where request_token = '44000000-0000-4000-8000-000000000001';
grant select on target_request to service_role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into claimed_email
select * from public.claim_booking_confirmation_emails(
  1,
  (select id from target_request)
);
reset role;
select is(
  (select count(*)::bigint from claimed_email),
  1::bigint,
  'one worker atomically claims the pending email'
);

set local role service_role;
select throws_ok(
  format(
    'select public.finish_booking_confirmation_email(%L, %L, false, null, %L)',
    (select outbox_id from claimed_email),
    gen_random_uuid(),
    'provider unavailable'
  ),
  'P0002',
  null,
  'a worker cannot finish another lease'
);
select is(
  public.finish_booking_confirmation_email(
    (select outbox_id from claimed_email),
    (select lease_token from claimed_email),
    false,
    null,
    'provider unavailable'
  ),
  'pending',
  'a provider failure schedules retry without changing the booking'
);
reset role;
select ok(
  (
    select next_attempt_at >= updated_at + interval '1 minute'
      from app_private.transactional_email_outbox
     where id = (select outbox_id from claimed_email)
  ),
  'retry uses bounded exponential backoff'
);

update app_private.transactional_email_outbox
   set status = 'processing',
       next_attempt_at = clock_timestamp() - interval '1 minute',
       lease_token = gen_random_uuid(),
       lease_expires_at = clock_timestamp() - interval '1 minute'
 where id = (select outbox_id from claimed_email);
truncate claimed_email;
set local role service_role;
insert into claimed_email
select * from public.claim_booking_confirmation_emails(
  1,
  (select id from target_request)
);
reset role;
select is(
  (select attempt_count from claimed_email),
  2,
  'an expired processing lease is safely recovered'
);

update app_private.transactional_email_outbox
   set status = 'pending',
       attempt_count = 7,
       next_attempt_at = clock_timestamp() - interval '1 minute',
       lease_token = null,
       lease_expires_at = null
 where id = (select outbox_id from claimed_email);
truncate claimed_email;
set local role service_role;
insert into claimed_email
select * from public.claim_booking_confirmation_emails(
  1,
  (select id from target_request)
);
select is(
  public.finish_booking_confirmation_email(
    (select outbox_id from claimed_email),
    (select lease_token from claimed_email),
    false,
    null,
    'provider unavailable'
  ),
  'failed',
  'the eighth failed attempt reaches the terminal cap'
);
select is(
  public.booking_confirmation_email_status(
    (select id from target_request)
  ),
  'failed',
  'terminal delivery failure remains explicit for operations'
);
reset role;

set local role anon;
select throws_ok(
  $$ select public.booking_confirmation_email_status(
    '44000000-0000-4000-8000-000000000001'
  ) $$,
  '42501',
  null,
  'anonymous callers cannot inspect delivery status'
);
reset role;

select * from finish();
rollback;
