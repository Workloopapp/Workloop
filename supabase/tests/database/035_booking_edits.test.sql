begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at,created_at)
values ('93500000-0000-4000-8000-000000000001','booking-edits@example.invalid',now(),now()),
('93500000-0000-4000-8000-000000000002','booking-other@example.invalid',now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('93500000-0000-4000-8000-000000000101','93500000-0000-4000-8000-000000000001',now(),now()),
('93500000-0000-4000-8000-000000000102','93500000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values('93510000-0000-4000-8000-000000000001','Booking edits');
insert into public.workspace_members(workspace_id,user_id) values('93510000-0000-4000-8000-000000000001','93500000-0000-4000-8000-000000000001');
insert into public.services(id,workspace_id,name,duration_mins,price) values
('93520000-0000-4000-8000-000000000001','93510000-0000-4000-8000-000000000001','Window clean',60,45),
('93520000-0000-4000-8000-000000000002','93510000-0000-4000-8000-000000000001','Gutter clean',60,45);
insert into public.appointments(id,workspace_id,service_id,title,start_time,end_time,price,notes)
values('93530000-0000-4000-8000-000000000001','93510000-0000-4000-8000-000000000001','93520000-0000-4000-8000-000000000001','Window clean','2030-01-10T10:00:00Z','2030-01-10T11:00:00Z',45,'Gate code 1234');
insert into public.appointment_items(workspace_id,appointment_id,item_kind,source_service_id,name,duration_mins,price,position)
values('93510000-0000-4000-8000-000000000001','93530000-0000-4000-8000-000000000001','base','93520000-0000-4000-8000-000000000001','Window clean',60,45,0);
insert into public.business_documents(workspace_id,appointment_id,type,status,invoice_number,issued_at,items)
values('93510000-0000-4000-8000-000000000001','93530000-0000-4000-8000-000000000001','invoice','sent','INV-EDIT-1',now(),'[{"description":"Window clean","unit_price":45}]');
create function pg_temp.edit_booking(extra jsonb default '{}', replace_items boolean default true)
returns jsonb language sql as $$
 select public.edit_booking_workflow('93530000-0000-4000-8000-000000000001',
 '{"contact_id":null,"service_id":"93520000-0000-4000-8000-000000000002","title":"Gutter clean","start_time":"2030-01-10T10:00:00Z","end_time":"2030-01-10T11:00:00Z","location":null,"notes":"Gate code 1234","price":45}'::jsonb || extra,replace_items);
$$;
select ok(not has_function_privilege('anon','public.edit_booking_workflow(uuid,jsonb,boolean)','EXECUTE'),'anonymous edit is unavailable');
select ok(not (select prosecdef from pg_proc where oid='public.edit_booking_workflow(uuid,jsonb,boolean)'::regprocedure),'public edit wrapper uses invoker security');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"93500000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"93500000-0000-4000-8000-000000000101"}',true);
select is(pg_temp.edit_booking() #>> '{appointment_items,0,name}','Gutter clean','same-price replacement returns the new service snapshot');
select is((select name from public.appointment_items),'Gutter clean','new invoice source has the edited service');
select is((select notes from public.appointments where id='93530000-0000-4000-8000-000000000001'),'Gate code 1234','work notes are retained');
select is((select items->0->>'description' from public.business_documents),'Window clean','issued invoice description remains unchanged');
select lives_ok($$select pg_temp.edit_booking()$$,'the exact retry is safe');
reset role;
insert into public.appointment_items(workspace_id,appointment_id,item_kind,source_service_id,name,duration_mins,price,position)
values('93510000-0000-4000-8000-000000000001','93530000-0000-4000-8000-000000000001','service','93520000-0000-4000-8000-000000000001','Window clean',30,15,1);
update public.appointments set price=60 where id='93530000-0000-4000-8000-000000000001';
set local role authenticated;
select is(jsonb_array_length(pg_temp.edit_booking('{"price":60,"notes":"Use side entrance"}',false)->'appointment_items'),2,'notes-only editing preserves a multi-service bundle');
select is(pg_temp.edit_booking('{"price":70}',false) #>> '{appointment_items,1,name}','Window clean','total editing retains other service descriptions');
select is((select price from public.appointment_items where position=0),55::numeric,'total adjustment applies only to the base item');
select is((select price from public.appointment_items where position=1),15::numeric,'other service keeps its agreed price');
select lives_ok($$select pg_temp.edit_booking('{"price":70}',false)$$,'total edit retry is safe');
select is((select sum(price) from public.appointment_items),70::numeric,'retry does not add the price difference twice');
select throws_ok($$select pg_temp.edit_booking('{"price":10,"notes":"must rollback"}',false)$$,'22023',
'The total must cover the other booked services and extras. Change the service to replace the item breakdown.','invalid bundle pricing cannot partially save');
select is((select price from public.appointments where id='93530000-0000-4000-8000-000000000001'),70::numeric,'failed item edit rolls back the booking price');
select is((select notes from public.appointments where id='93530000-0000-4000-8000-000000000001'),'Gate code 1234','failed item edit rolls back work notes');
select set_config('request.jwt.claims','{"sub":"93500000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"93500000-0000-4000-8000-000000000102"}',true);
select throws_ok($$select pg_temp.edit_booking()$$,'42501','Booking unavailable','a different owner cannot edit the booking');
reset role;
select * from finish();
rollback;
