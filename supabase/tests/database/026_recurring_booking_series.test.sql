begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
select ok(not has_function_privilege('anon','public.create_recurring_booking_workflow(jsonb)','EXECUTE'), 'anonymous clients cannot create series');
select ok(has_function_privilege('authenticated','public.create_recurring_booking_workflow(jsonb)','EXECUTE'), 'authenticated series entry exists');
select ok(not (select prosecdef from pg_proc where oid='public.create_recurring_booking_workflow(jsonb)'::regprocedure), 'series wrapper obeys caller RLS');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('61000000-0000-4000-8000-000000000001','authenticated','authenticated','series-a@example.invalid','',now(),now(),now(),'',''),
('62000000-0000-4000-8000-000000000002','authenticated','authenticated','series-b@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000001',now(),now()),
('62000000-0000-4000-8000-000000000102','62000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
('61100000-0000-4000-8000-000000000001','Series A'),('62200000-0000-4000-8000-000000000002','Series B');
insert into public.workspace_members(workspace_id,user_id) values
('61100000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001'),
('62200000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id,timezone) values
('61100000-0000-4000-8000-000000000001','Europe/London') on conflict(workspace_id) do update set timezone=excluded.timezone;
create temporary table series_payload(payload jsonb);
grant select,update on series_payload to authenticated;
insert into series_payload values (jsonb_build_object(
 'workspace_id','61100000-0000-4000-8000-000000000001','idempotency_key','series-create-retry-000001',
 'new_contact',jsonb_build_object('name','Series customer','phone','07123456991'),
 'title','Regular clean','price',70,'recurrence_rule','FREQ=WEEKLY;INTERVAL=1',
 'recurrence_timezone','Europe/London','create_payment_due',true,
 'task_titles',jsonb_build_array('Prepare supplies'),'task_due_date','2027-03-21',
 'appointments',jsonb_build_array(
 jsonb_build_object('start_time','2027-03-21T09:00:00Z','end_time','2027-03-21T10:00:00Z'),
 jsonb_build_object('start_time','2027-03-28T08:00:00Z','end_time','2027-03-28T09:00:00Z'),
 jsonb_build_object('start_time','2027-04-04T08:00:00Z','end_time','2027-04-04T09:00:00Z'))));
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"61000000-0000-4000-8000-000000000101"}',true);
select lives_ok('select public.create_recurring_booking_workflow(payload) from series_payload','weekly series crosses spring DST at the same business hour');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'creates all three occurrences');
create temporary table series_saved_result as select public.create_recurring_booking_workflow(payload) as result from series_payload;
select is((select count(*) from public.appointments where recurrence_rule='FREQ=WEEKLY;INTERVAL=1' and recurrence_timezone='Europe/London'),3::bigint,'every occurrence retains the rule and original zone');
select is((select count(distinct coalesce(recurrence_parent_id,id)) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),1::bigint,'occurrences share one existing parent chain');
select is((select count(*) from public.invoices where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'optional payment due created once per occurrence');
select is((select count(*) from public.tasks task join public.appointments appointment on appointment.id=task.appointment_id where task.workspace_id='61100000-0000-4000-8000-000000000001' and task.due_date=(appointment.start_time at time zone 'Europe/London')::date),1::bigint,'inline prep task belongs to the first booking only');
select lives_ok('select public.create_recurring_booking_workflow(payload) from series_payload','retry recovers the same transaction');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'retry creates no duplicate booking');
select is((select count(*) from public.contacts where workspace_id='61100000-0000-4000-8000-000000000001'),1::bigint,'retry creates no duplicate client');
update public.appointments set status='cancelled' where start_time='2027-03-28T08:00:00Z' and workspace_id='61100000-0000-4000-8000-000000000001';
update public.appointments set start_time='2027-04-05T09:00:00Z',end_time='2027-04-05T10:00:00Z' where start_time='2027-04-04T08:00:00Z' and workspace_id='61100000-0000-4000-8000-000000000001';
select lives_ok('select public.create_recurring_booking_workflow(payload) from series_payload','retry after exceptions returns existing series');
select is((select count(*) from public.appointments where status='cancelled' and workspace_id='61100000-0000-4000-8000-000000000001'),1::bigint,'skipped occurrence stays cancelled after retry');
select is((select count(*) from public.appointments where start_time='2027-04-05T09:00:00Z' and workspace_id='61100000-0000-4000-8000-000000000001'),1::bigint,'rescheduled occurrence stays moved after retry');
select is((select count(*) from public.appointments where start_time='2027-03-21T09:00:00Z' and status='scheduled' and workspace_id='61100000-0000-4000-8000-000000000001'),1::bigint,'editing an occurrence preserves its neighbour');
-- A lost response can still resolve if workspace settings changed meanwhile.
update public.workspace_settings set timezone='America/New_York'
  where workspace_id='61100000-0000-4000-8000-000000000001';
select lives_ok('select public.create_recurring_booking_workflow(payload) from series_payload','committed retry resolves after the business timezone changes');
select is((select public.create_recurring_booking_workflow(payload) from series_payload),(select result from series_saved_result),'settings-change recovery returns the exact original result');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'settings-change recovery keeps one finite series');
select is((select count(*) from public.appointments where recurrence_timezone='Europe/London' and workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'recovery preserves the original series timezone');
select throws_ok($$select public.create_recurring_booking_workflow(payload || '{"idempotency_key":"series-new-stale-zone-000001"}'::jsonb) from series_payload$$,'22023','Use the current business timezone for recurring bookings','new series still requires current business timezone');
update public.workspace_settings set timezone='Europe/London'
  where workspace_id='61100000-0000-4000-8000-000000000001';
select throws_ok($$select public.create_recurring_booking_workflow(payload || '{"recurrence_timezone":"UTC","idempotency_key":"series-invalid-zone-000001"}'::jsonb) from series_payload$$,'22023','Use the current business timezone for recurring bookings','rejects client supplied zone mismatch');
select throws_ok($$select public.create_recurring_booking_workflow(payload || '{"recurrence_rule":"FREQ=WEEKLY;INTERVAL=5","idempotency_key":"series-invalid-rule-000001"}'::jsonb) from series_payload$$,'22023','Repeat every one to four weeks','frequency is bounded');
select throws_ok($$select public.create_recurring_booking_workflow(payload || jsonb_build_object('idempotency_key','series-invalid-count-000001','appointments',jsonb_build_array(payload->'appointments'->0))) from series_payload$$,'22023','Provide between two and 24 bookings','one-item series rejected');
select throws_ok($$select public.create_recurring_booking_workflow(jsonb_set(jsonb_set(payload,'{appointments,1,start_time}','"2027-03-28T09:00:00Z"'),'{appointments,1,end_time}','"2027-03-28T10:00:00Z"') || '{"idempotency_key":"series-invalid-dst-000001"}'::jsonb) from series_payload$$,'22023','Recurring bookings must keep their business time and duration','DST hour drift rejected');
-- An overlap at a later occurrence must roll back earlier ones and all side effects.
update series_payload set payload=payload || jsonb_build_object('idempotency_key','series-conflict-retry-000001','appointments',jsonb_build_array(
 jsonb_build_object('start_time','2027-03-14T09:00:00Z','end_time','2027-03-14T10:00:00Z'),
 jsonb_build_object('start_time','2027-03-21T09:00:00Z','end_time','2027-03-21T10:00:00Z')));
select throws_ok('select public.create_recurring_booking_workflow(payload) from series_payload','23P01','Appointment overlaps an existing booking','later conflict aborts whole series');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'no partial occurrence survives a failed series');
select is((select count(*) from public.invoices where workspace_id='61100000-0000-4000-8000-000000000001'),3::bigint,'no partial payment survives a failed series');
select lives_ok($$select public.create_recurring_booking_workflow(payload || '{"allow_overlap":true}'::jsonb) from series_payload$$,'explicit owner overlap consent recovers failed series');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),5::bigint,'recovery creates exactly the two requested bookings');
reset role;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('63000000-0000-4000-8000-000000000003','authenticated','authenticated','series-c@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('63000000-0000-4000-8000-000000000103','63000000-0000-4000-8000-000000000003',now(),now());
insert into public.workspace_members(workspace_id,user_id) values
('61100000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000003');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values
('64000000-0000-4000-8000-000000000004','61000000-0000-4000-8000-000000000001','totp','verified',now(),now());
set local role authenticated;
select throws_ok('select public.create_recurring_booking_workflow(payload) from series_payload','42501','Workspace access denied','completed result recovery still requires enrolled MFA');
select throws_ok($$select app_private.recurring_booking_result('61100000-0000-4000-8000-000000000001','series-create-retry-000001')$$,'42501','Multi-factor authentication is required','private recovery helper explicitly enforces MFA');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"61000000-0000-4000-8000-000000000101"}',true);
select lives_ok('select public.create_recurring_booking_workflow(payload) from series_payload','MFA verified caller can recover own completed result');
select set_config('request.jwt.claim.sub','63000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"63000000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1","session_id":"63000000-0000-4000-8000-000000000103"}',true);
select is(app_private.recurring_booking_result('61100000-0000-4000-8000-000000000001','series-create-retry-000001'),null::jsonb,'another member cannot read the original caller result');
select ok(not has_function_privilege('anon','app_private.recurring_booking_result(uuid,text)','EXECUTE'),'anonymous callers cannot access private result helper');
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"62000000-0000-4000-8000-000000000102"}',true);
select throws_ok('select public.create_recurring_booking_workflow(payload) from series_payload','42501','Workspace access denied','another tenant cannot create or replay a series');
select is((select count(*) from public.appointments where workspace_id='61100000-0000-4000-8000-000000000001'),0::bigint,'RLS hides the other workspace series');
select throws_ok($$select app_private.recurring_booking_result('61100000-0000-4000-8000-000000000001','series-create-retry-000001')$$,'42501','Workspace access denied','private helper also rejects a different tenant');
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select app_private.recurring_booking_result('61100000-0000-4000-8000-000000000001','series-create-retry-000001')$$,'28000','Authentication required','private helper rejects an absent user identity');
reset role;
select * from finish();
rollback;
