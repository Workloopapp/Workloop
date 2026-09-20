begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
select ok(not has_function_privilege('authenticated', 'public.create_public_booking_request_v4(uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[],uuid[])','EXECUTE'), 'public bundle intake is service-role only');
select ok(not has_function_privilege('anon', 'app_private.booking_service_selection(uuid,uuid[],uuid[],boolean)','EXECUTE'), 'anonymous clients cannot inspect private selection helper');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('41000000-0000-4000-8000-000000000001','authenticated','authenticated','bundle-a@example.invalid','',now(),now(),now(),'',''),
('42000000-0000-4000-8000-000000000002','authenticated','authenticated','bundle-b@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('41000000-0000-4000-8000-000000000101','41000000-0000-4000-8000-000000000001',now(),now()),
('42000000-0000-4000-8000-000000000102','42000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
('41100000-0000-4000-8000-000000000001','Bundles A'),('42200000-0000-4000-8000-000000000002','Bundles B');
insert into public.workspace_members(workspace_id,user_id) values
('41100000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001'),
('42200000-0000-4000-8000-000000000002','42000000-0000-4000-8000-000000000002');
insert into public.services(id,workspace_id,name,duration_mins,price) values
('41110000-0000-4000-8000-000000000001','41100000-0000-4000-8000-000000000001','Clean',60,50),
('41110000-0000-4000-8000-000000000002','41100000-0000-4000-8000-000000000001','Polish',30,30),
('41110000-0000-4000-8000-000000000003','41100000-0000-4000-8000-000000000001','Unselected',30,30),
('42220000-0000-4000-8000-000000000002','42200000-0000-4000-8000-000000000002','Other tenant',60,70);
insert into public.service_add_ons(id,workspace_id,service_id,name,duration_mins,price) values
('41111000-0000-4000-8000-000000000001','41100000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002','Wax',15,10),
('41111000-0000-4000-8000-000000000002','41100000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000003','Wrong parent',15,10);
insert into public.business_profiles(workspace_id,handle,booking_mode) values ('41100000-0000-4000-8000-000000000001','bundles-quality-a','manual');
insert into public.workspace_settings(workspace_id,timezone) values ('41100000-0000-4000-8000-000000000001','Europe/London') on conflict(workspace_id) do update set timezone=excluded.timezone;

set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table selected_bundle as select app_private.booking_service_selection(
 '41100000-0000-4000-8000-000000000001',
 array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002']::uuid[],
 array['41111000-0000-4000-8000-000000000001']::uuid[],true) as value;
select is((select value->>'duration' from selected_bundle),'105','duration sums every service and its extra');
select is((select (value->>'price')::numeric from selected_bundle),90::numeric,'price comes from trusted catalogue only');
select is((select jsonb_array_length(value->'items') from selected_bundle),3,'bundle has a snapshot for each selected item');
select is((select value->'items'->1->>'item_kind' from selected_bundle),'service','additional base services are distinct from extras');
select throws_ok($$select app_private.booking_service_selection('41100000-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','42220000-0000-4000-8000-000000000002']::uuid[],'{}',true)$$,'22023','invalid_service','cross-tenant service rejected');
select throws_ok($$select app_private.booking_service_selection('41100000-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000001']::uuid[],'{}',true)$$,'22023','invalid_service','duplicate services rejected');
select throws_ok($$select app_private.booking_service_selection('41100000-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002']::uuid[],array['41111000-0000-4000-8000-000000000002']::uuid[],true)$$,'22023','invalid_add_on','extra belonging to unselected service rejected');

create temporary table bundle_request as select * from public.create_public_booking_request_v4(
 '41100000-0000-4000-8000-000000000001','Customer','07123456901','bundle@example.invalid',
 '41110000-0000-4000-8000-000000000001',null,now()+interval '2 days','Europe/London',null,repeat('a',64),
 '41111111-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002']::uuid[],
 array['41111000-0000-4000-8000-000000000001']::uuid[]);
select is((select outcome from bundle_request),'created','public bundle creates exactly one request');
select is((select outcome from public.create_public_booking_request_v4(
 '41100000-0000-4000-8000-000000000001','Customer','07123456901','bundle@example.invalid',
 '41110000-0000-4000-8000-000000000001',null,now()+interval '2 days','Europe/London',null,repeat('a',64),
 '41111111-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002']::uuid[],
 array['41111000-0000-4000-8000-000000000001']::uuid[])), 'duplicate', 'public replay returns the same complete selection');

select is((select count(*) from public.booking_request_items where booking_request_id=(select booking_request_id from bundle_request)),3::bigint,'all public requested items are retained');
select is((select service_id::text from public.booking_requests where id=(select booking_request_id from bundle_request)),'41110000-0000-4000-8000-000000000001','primary service stays compatible');
select is(public.get_public_booking_slot_suggestions_v4('bundles-quality-a','41110000-0000-4000-8000-000000000001',repeat('b',64),array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002']::uuid[],array['41111000-0000-4000-8000-000000000001']::uuid[])->>'durationMinutes','105','suggestions use the whole bundle duration');
reset role;
update public.services set duration_mins=1440 where id='41110000-0000-4000-8000-000000000003';
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select app_private.booking_service_selection('41100000-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000003']::uuid[],'{}',true)$$,'22023','invalid_bundle_total','aggregate duration is bounded at one day');
reset role;
update public.services set show_on_profile=false where id='41110000-0000-4000-8000-000000000003';
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select app_private.booking_service_selection('41100000-0000-4000-8000-000000000001',array['41110000-0000-4000-8000-000000000003']::uuid[],'{}',true)$$,'22023','invalid_service','hidden services cannot be added through public intake');
reset role;

create temporary table bundle_payload(payload jsonb);
grant select on bundle_payload to authenticated;
insert into bundle_payload select jsonb_build_object(
 'workspace_id','41100000-0000-4000-8000-000000000001','idempotency_key','bundle-direct-request-00001',
 'service_id','41110000-0000-4000-8000-000000000001',
 'service_ids',jsonb_build_array('41110000-0000-4000-8000-000000000001','41110000-0000-4000-8000-000000000002'),
 'add_on_ids',jsonb_build_array('41111000-0000-4000-8000-000000000001'),
 'new_contact',jsonb_build_object('name','Owner customer','phone','07123456902','email','owner.customer@example.invalid'),
 'appointments',jsonb_build_array(jsonb_build_object('start_time',now()+interval '5 days','end_time',now()+interval '5 days 1 minute')),
 'price',0.01,'title','Forged totals','create_payment_due',true,'notification_title','Booking','notification_body','Created');
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"41000000-0000-4000-8000-000000000101"}',true);
select lives_ok('select public.create_booking_workflow(payload) from bundle_payload','owner can create one combined booking');
reset role;
select is((select price::numeric from public.appointments where workspace_id='41100000-0000-4000-8000-000000000001'),90::numeric,'owner caller cannot forge combined price');
select is((select extract(epoch from end_time-start_time)::integer/60 from public.appointments where workspace_id='41100000-0000-4000-8000-000000000001'),105,'owner caller cannot shorten combined duration');
select is((select count(*) from public.appointment_items where workspace_id='41100000-0000-4000-8000-000000000001'),3::bigint,'owner booking snapshots all selected items');
select is((select total::numeric from public.invoices where workspace_id='41100000-0000-4000-8000-000000000001'),90::numeric,'payment due uses computed bundle price');

-- Catalogue changes must not rewrite a customer's request or break replay.
update public.services set name='Changed Polish',price=900,duration_mins=120 where id='41110000-0000-4000-8000-000000000002';
update public.service_add_ons set active=false where id='41111000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select lives_ok('select public.create_booking_workflow(payload) from bundle_payload','successful retry ignores changed/deactivated catalogue');
reset role;
select is((select count(*) from public.appointments where workspace_id='41100000-0000-4000-8000-000000000001'),1::bigint,'retry does not duplicate the booking');

create temporary table confirm_bundle(payload jsonb);
grant select on confirm_bundle to authenticated;
insert into confirm_bundle select payload - 'service_ids' - 'add_on_ids' || jsonb_build_object(
 'idempotency_key','bundle-confirm-request-00001','booking_request_id',(select booking_request_id from bundle_request),
 'appointments',jsonb_build_array(jsonb_build_object('start_time',now()+interval '7 days','end_time',now()+interval '7 days 1 minute'))
) from bundle_payload;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select lives_ok('select public.create_booking_workflow(payload) from confirm_bundle','confirmation uses requested snapshots after catalogue changes');
reset role;
select is((select count(*) from public.appointments where workspace_id='41100000-0000-4000-8000-000000000001' and price=90 and extract(epoch from end_time-start_time)::integer/60=105),2::bigint,'confirmed price/duration preserve original customer bundle');
select is((select count(*) from public.appointment_items where workspace_id='41100000-0000-4000-8000-000000000001' and name='Polish'),2::bigint,'both owner and requested item names remain immutable');
select is((select count(*) from app_private.transactional_email_outbox where booking_request_id=(select booking_request_id from bundle_request)),1::bigint,'bundle confirmation preserves one transactional email intent');

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','42000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"42000000-0000-4000-8000-000000000102"}',true);
select throws_ok('select public.create_booking_workflow(payload) from bundle_payload','42501','Workspace access denied','another tenant cannot create or replay owner bundle');
reset role;

set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select outcome from public.create_public_booking_request_v2(
 '41100000-0000-4000-8000-000000000001','Legacy customer','07123456904','legacy.bundle@example.invalid',
 '41110000-0000-4000-8000-000000000001','Tomorrow',null,repeat('d',64),'41111111-0000-4000-8000-000000000004')),'created','Build6 unstructured single-service intake stays valid');
reset role;
select * from finish();
rollback;
