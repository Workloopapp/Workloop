begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(not has_function_privilege('authenticated','app_private.resolve_notification_entity_route(uuid,text,text,text)','EXECUTE'),'route recovery is not a new client data API');
select ok(not has_function_privilege('anon','app_private.resolve_notification_entity_route(uuid,text,text,text)','EXECUTE'),'anonymous callers cannot inspect route recovery');
select ok(not has_function_privilege('service_role','app_private.resolve_notification_entity_route(uuid,text,text,text)','EXECUTE'),'private resolver stays inside privileged workflow boundary');
select ok(not has_function_privilege('authenticated','app_private.route_notification_to_entity()','EXECUTE'),'client cannot call notification trigger directly');
select ok(not has_function_privilege('anon','app_private.complete_booking_workflow(jsonb)','EXECUTE'),'completion implementation retains anonymous denial');
select ok(not has_function_privilege('authenticated','app_private.run_business_automations(timestamptz)','EXECUTE'),'automation implementation remains unavailable to the client');
select ok(has_function_privilege('service_role','public.create_public_booking_request(uuid,text,text,uuid,text,text,text,uuid)','EXECUTE'),'public request service role API remains available');
select ok(not has_function_privilege('authenticated','public.create_public_booking_request(uuid,text,text,uuid,text,text,text,uuid)','EXECUTE'),'client cannot bypass public request service role entry point');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2400000-0000-4000-8000-000000000001','authenticated','authenticated','route-a@example.test','',now(),now(),now()),
('a2400000-0000-4000-8000-000000000002','authenticated','authenticated','route-b@example.test','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values ('a2400000-0000-4000-8000-000000000011','a2400000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id,name) values
('b2400000-0000-4000-8000-000000000001','Exact route QA'),
('b2400000-0000-4000-8000-000000000002','Other route QA');
insert into public.workspace_members(workspace_id,user_id) values
('b2400000-0000-4000-8000-000000000001','a2400000-0000-4000-8000-000000000001'),
('b2400000-0000-4000-8000-000000000002','a2400000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id,timezone) values ('b2400000-0000-4000-8000-000000000001','Europe/London');
insert into public.notification_preferences(workspace_id,quiet_hours_enabled,task_due_morning) values ('b2400000-0000-4000-8000-000000000001',false,true);
insert into public.business_profiles(workspace_id,handle,booking_mode) values ('b2400000-0000-4000-8000-000000000001','exact-route-qa','manual');

-- Two requests in one transaction make xmin-only latest-row selection unsafe.
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table route_requests as
select 'first'::text label,booking_request_id from public.create_public_booking_request(
 'b2400000-0000-4000-8000-000000000001','First QA','07123456101',null,'Tomorrow',null,repeat('a',64),'e2400000-0000-4000-8000-000000000001');
insert into route_requests select 'second',booking_request_id from public.create_public_booking_request(
 'b2400000-0000-4000-8000-000000000001','Second QA','07123456102',null,'Tomorrow',null,repeat('b',64),'e2400000-0000-4000-8000-000000000002');
select is((select deep_link from public.notifications where body='First QA requested a booking.'),'/booking-requests/'||(select booking_request_id from route_requests where label='first')::text,'first public request targets its own returned identifier');
select is((select deep_link from public.notifications where body='Second QA requested a booking.'),'/booking-requests/'||(select booking_request_id from route_requests where label='second')::text,'second public request cannot open the first request');

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a2400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a2400000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"a2400000-0000-4000-8000-000000000011"}',true);
create temporary table route_bookings as select 'series'::text label, public.create_booking_workflow(jsonb_build_object(
 'workspace_id','b2400000-0000-4000-8000-000000000001','idempotency_key','exact-route-series-0001','title','QA recurring booking','price',25,
 'new_contact',jsonb_build_object('name','QA client'), 'allow_outside_working_hours',true,
 'appointments',jsonb_build_array(
   jsonb_build_object('start_time',now()+interval '2 days','end_time',now()+interval '2 days 1 hour'),
   jsonb_build_object('start_time',now()+interval '3 days','end_time',now()+interval '3 days 1 hour')))) as result;
insert into route_bookings select 'zero',public.create_booking_workflow(jsonb_build_object(
 'workspace_id','b2400000-0000-4000-8000-000000000001','idempotency_key','exact-route-zero-00001','title','QA zero-value booking','price',0,
 'new_contact',jsonb_build_object('name','QA second client'), 'allow_outside_working_hours',true,
 'appointments',jsonb_build_array(jsonb_build_object('start_time',now()+interval '4 days','end_time',now()+interval '4 days 1 hour'))));
select is((select deep_link from public.notifications where dedupe_key='workflow:create_booking:exact-route-series-0001'),'/bookings/'||(select result->'appointment_ids'->>0 from route_bookings where label='series'),'recurring creation targets the first returned booking');
select is((select deep_link from public.notifications where dedupe_key='workflow:create_booking:exact-route-zero-00001'),'/bookings/'||(select result->'appointment_ids'->>0 from route_bookings where label='zero'),'later workflow does not inherit an earlier transaction booking');

create temporary table route_completed as select 'paid'::text label,public.complete_booking_workflow(jsonb_build_object(
 'workspace_id','b2400000-0000-4000-8000-000000000001','appointment_id',(select result->'appointment_ids'->>0 from route_bookings where label='series'),
 'idempotency_key','exact-route-paid-00001','payment_mode','paid')) as result;
insert into route_completed select 'unpaid',public.complete_booking_workflow(jsonb_build_object(
 'workspace_id','b2400000-0000-4000-8000-000000000001','appointment_id',(select result->'appointment_ids'->>1 from route_bookings where label='series'),
 'idempotency_key','exact-route-unpaid-0001','payment_mode','unpaid'));
insert into route_completed select 'zero',public.complete_booking_workflow(jsonb_build_object(
 'workspace_id','b2400000-0000-4000-8000-000000000001','appointment_id',(select result->'appointment_ids'->>0 from route_bookings where label='zero'),
 'idempotency_key','exact-route-free-00001','payment_mode','paid'));
select is((select deep_link from public.notifications where dedupe_key='workflow:complete_booking:exact-route-paid-00001'),'/payments/'||(select result->>'invoice_id' from route_completed where label='paid'),'paid completion targets the payment returned by that workflow');
select is((select deep_link from public.notifications where dedupe_key='workflow:complete_booking:exact-route-unpaid-0001'),'/payments/'||(select result->>'invoice_id' from route_completed where label='unpaid'),'unpaid completion targets its own payment among multiple updated invoices');
select is((select deep_link from public.notifications where dedupe_key='workflow:complete_booking:exact-route-free-00001'),'/bookings/'||(select result->>'appointment_id' from route_completed where label='zero'),'zero-value completion without a payment opens the actual booking');

update public.booking_requests set created_at=now()-interval '5 hours' where workspace_id='b2400000-0000-4000-8000-000000000001';
update public.invoices set due_date=current_date-1 where id=(select (result->>'invoice_id')::uuid from route_completed where label='unpaid');
select app_private.run_business_automations(now());
select is((select count(*)::integer from public.notifications where dedupe_key like 'booking_request_waiting:%' and deep_link='/booking-requests/'||split_part(dedupe_key,':',2)),2,'waiting-request automation routes every item to its own request');
select is((select deep_link from public.notifications where dedupe_key='invoice_overdue:'||(select result->>'invoice_id' from route_completed where label='unpaid')),'/payments/'||(select result->>'invoice_id' from route_completed where label='unpaid'),'overdue automation carries the invoice identifier explicitly');

create temporary table route_probe (like public.notifications including defaults);
alter table route_probe alter column body set default 'Synthetic route test';
create trigger route_probe_trigger before insert or update on route_probe for each row execute function app_private.route_notification_to_entity();
insert into route_probe(workspace_id,type,title,deep_link) values
('b2400000-0000-4000-8000-000000000001','booking','Ambiguous booking','/work'),
('b2400000-0000-4000-8000-000000000001','payment','Ambiguous payment','/payments'),
('b2400000-0000-4000-8000-000000000001','booking_request','Ambiguous request','/booking-requests'),
('b2400000-0000-4000-8000-000000000001','morning_digest','Summary','/home');
select is((select deep_link from route_probe where title='Ambiguous booking'),'/work','legacy batch without a stable ID does not guess one booking');
select is((select deep_link from route_probe where title='Ambiguous payment'),'/payments','legacy batch does not guess one payment');
select is((select deep_link from route_probe where title='Ambiguous request'),'/booking-requests','legacy batch does not guess one request');
select is((select deep_link from route_probe where title='Summary'),'/home','multi-record morning summary retains Today destination');

insert into public.tasks(id,workspace_id,title,status) values
('f2400000-0000-4000-8000-000000000001','b2400000-0000-4000-8000-000000000001','Local task','open'),
('f2400000-0000-4000-8000-000000000002','b2400000-0000-4000-8000-000000000002','Other task','open');
insert into public.notes(id,workspace_id,title,body) values ('f2400000-0000-4000-8000-000000000003','b2400000-0000-4000-8000-000000000001','Local note','QA only');
insert into route_probe(workspace_id,type,title,deep_link,dedupe_key) values
('b2400000-0000-4000-8000-000000000001','task_due','Exact task','/tasks','task_due:f2400000-0000-4000-8000-000000000001'),
('b2400000-0000-4000-8000-000000000001','task_due','Foreign task','/tasks','task_due:f2400000-0000-4000-8000-000000000002'),
('b2400000-0000-4000-8000-000000000001','task_due','Malformed task','/tasks','task_due:not-a-uuid'),
('b2400000-0000-4000-8000-000000000001','note','Unambiguous note','/notes',null);
select is((select deep_link from route_probe where title='Exact task'),'/tasks/f2400000-0000-4000-8000-000000000001','stable task identifier resolves its record');
select is((select deep_link from route_probe where title='Foreign task'),'/tasks','foreign dedupe cannot resolve another workspace or be replaced by unrelated local task');
select is((select deep_link from route_probe where title='Malformed task'),'/tasks','malformed structured identifier does not fall back to an unrelated task');
select is((select deep_link from route_probe where title='Unambiguous note'),'/notes/f2400000-0000-4000-8000-000000000003','single legacy note can retain the useful fallback');
insert into public.notes(id,workspace_id,title,body) values ('f2400000-0000-4000-8000-000000000004','b2400000-0000-4000-8000-000000000001','Second note','QA only');
insert into route_probe(workspace_id,type,title,deep_link) values ('b2400000-0000-4000-8000-000000000001','note','Ambiguous note','/notes');
select is((select deep_link from route_probe where title='Ambiguous note'),'/notes','multiple legacy notes cannot pick the first row');
insert into route_probe(workspace_id,type,title,deep_link) values ('b2400000-0000-4000-8000-000000000001','note','Explicit note','/notes/f2400000-0000-4000-8000-000000000004');
select is((select deep_link from route_probe where title='Explicit note'),'/notes/f2400000-0000-4000-8000-000000000004','explicit record route wins over other transaction entities');
delete from public.notes where id='f2400000-0000-4000-8000-000000000004';
update route_probe set body='Updated QA text' where title='Explicit note';
select is((select deep_link from route_probe where title='Explicit note'),'/notes/f2400000-0000-4000-8000-000000000004','removed record retains its exact route for client unavailable state');
update route_probe set body='Old generic alert edited' where title='Ambiguous note';
select is((select deep_link from route_probe where title='Ambiguous note'),'/notes','updating an old alert never guesses a newly touched entity');

select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000001','new_booking','/work','workflow:create_booking:exact-route-series-0001'),'/bookings/'||(select result->'appointment_ids'->>0 from route_bookings where label='series'),'saved workflow result recovers a historical booking route');
select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000001','payment_received','/payments','workflow:complete_booking:exact-route-paid-00001'),'/payments/'||(select result->>'invoice_id' from route_completed where label='paid'),'saved workflow result recovers a historical payment route');
select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000002','new_booking','/work','workflow:create_booking:exact-route-series-0001'),'/work','workflow recovery stays workspace-scoped');
insert into app_private.workflow_idempotency(workspace_id,user_id,operation,idempotency_key,result) values
('b2400000-0000-4000-8000-000000000001','a2400000-0000-4000-8000-000000000002','create_booking','exact-route-series-0001',jsonb_build_object('appointment_ids',jsonb_build_array('f2400000-0000-4000-8000-000000000099')));
select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000001','new_booking','/work','workflow:create_booking:exact-route-series-0001'),'/work','conflicting workflow result with a missing record cannot silently choose the surviving result');
update app_private.workflow_idempotency set result=(select result from route_bookings where label='zero') where user_id='a2400000-0000-4000-8000-000000000002';
select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000001','new_booking','/work','workflow:create_booking:exact-route-series-0001'),'/work','two surviving workflow targets remain ambiguous');
select is(app_private.resolve_notification_entity_route('b2400000-0000-4000-8000-000000000001','new_booking','/work',null),'/work','identifier-free history is not matched by customer text or date');

-- Claim fetches the current canonical route, including a deterministic legacy
-- repair made after enqueue, without queuing a second push.

insert into public.push_tokens(id,workspace_id,user_id,auth_session_id,token,platform,apns_environment,last_seen_at) values ('c2400000-0000-4000-8000-000000000001','b2400000-0000-4000-8000-000000000001','a2400000-0000-4000-8000-000000000001','a2400000-0000-4000-8000-000000000011','exact-route-test-token-not-real','ios','sandbox',now());
insert into public.notifications(id,workspace_id,type,title,body,deep_link) values ('d2400000-0000-4000-8000-000000000001','b2400000-0000-4000-8000-000000000001','booking_request','QA queued repair','No customer data','/booking-requests');
update public.notifications set dedupe_key='booking_request_waiting:'||(select booking_request_id::text from route_requests where label='first')||':invalid' where id='d2400000-0000-4000-8000-000000000001';
create temporary table route_repair_before as select to_jsonb(notification)-'deep_link'-'dedupe_key' as stable_fields from public.notifications notification where id='d2400000-0000-4000-8000-000000000001';
create temporary table route_preferences_before as select to_jsonb(preference) as stable_fields from public.notification_preferences preference;
create temporary table route_outbox_before as select to_jsonb(delivery) as stable_fields from app_private.push_delivery_outbox delivery;
-- Use a second durable request form so it does not collide with the automation.
update public.notifications set dedupe_key='booking_request_received:'||(select booking_request_id::text from route_requests where label='first') where id='d2400000-0000-4000-8000-000000000001';
select is((select to_jsonb(notification)-'deep_link'-'dedupe_key' from public.notifications notification where id='d2400000-0000-4000-8000-000000000001'),(select stable_fields from route_repair_before),'route repair preserves read state, creation time, content and ownership');
select is((select jsonb_agg(to_jsonb(preference) order by workspace_id) from public.notification_preferences preference),(select jsonb_agg(stable_fields order by stable_fields->>'workspace_id') from route_preferences_before),'route repair does not change notification preferences');
select is((select to_jsonb(delivery) from app_private.push_delivery_outbox delivery),(select stable_fields from route_outbox_before),'route repair leaves the existing delivery lease, state and timestamps unchanged');
select is((select count(*)::integer from app_private.push_delivery_outbox),1,'repairing a saved route does not enqueue another push');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select deep_link from public.claim_push_deliveries(1)),'/booking-requests/'||(select booking_request_id from route_requests where label='first')::text,'worker receives repaired exact route from the canonical notification');

select * from finish();
rollback;
