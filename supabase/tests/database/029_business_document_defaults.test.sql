begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(12);

insert into auth.users(id,email,email_confirmed_at,created_at)
values ('73100000-0000-4000-8000-000000000001','defaults-a@example.invalid',now(),now()),
       ('73100000-0000-4000-8000-000000000002','defaults-b@example.invalid',now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('73100000-0000-4000-8000-000000000101','73100000-0000-4000-8000-000000000001',now(),now()),
('73100000-0000-4000-8000-000000000102','73100000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name)
values ('73200000-0000-4000-8000-000000000001','Defaults A'),
       ('73200000-0000-4000-8000-000000000002','Defaults B');
insert into public.workspace_members(workspace_id,user_id)
values ('73200000-0000-4000-8000-000000000001','73100000-0000-4000-8000-000000000001'),
       ('73200000-0000-4000-8000-000000000002','73100000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id)
values ('73200000-0000-4000-8000-000000000001'),('73200000-0000-4000-8000-000000000002')
on conflict do nothing;
select is((select default_quote_validity_days from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),30,'new quote validity default');
select is((select business_structure from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),null::text,'does not infer legal structure');

set local role authenticated;
select set_config('request.jwt.claim.sub','73100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"73100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"73100000-0000-4000-8000-000000000101"}',true);
select lives_ok($q$update workspace_settings set business_structure='sole_trader',business_legal_name='Alex Owner',business_address='1 High Street',customer_contact_email='hello@example.invalid',default_payment_instructions='Transfer using invoice reference',default_quote_validity_days=45 where workspace_id='73200000-0000-4000-8000-000000000001'$q$,'owner saves canonical fields');
select is((select business_legal_name from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),'Alex Owner','legal name round trip');
select is((select customer_contact_email from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),'hello@example.invalid','same existing email column is reused');
select throws_ok($q$update workspace_settings set default_quote_validity_days=0 where workspace_id='73200000-0000-4000-8000-000000000001'$q$,'23514',null,'zero quote validity denied');
select throws_ok($q$update workspace_settings set default_quote_validity_days=366 where workspace_id='73200000-0000-4000-8000-000000000001'$q$,'23514',null,'unbounded quote validity denied');
select throws_ok($q$update workspace_settings set default_payment_instructions=repeat('x',3001) where workspace_id='73200000-0000-4000-8000-000000000001'$q$,'23514',null,'instructions bounded');
select throws_ok($q$update workspace_settings set business_structure='invented' where workspace_id='73200000-0000-4000-8000-000000000001'$q$,'23514',null,'unsupported structure denied');
select set_config('request.jwt.claim.sub','73100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"73100000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"73100000-0000-4000-8000-000000000102"}',true);
select is((select count(*) from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),0::bigint,'other tenant cannot read legal or banking instructions');
update workspace_settings set business_legal_name='Wrong tenant' where workspace_id='73200000-0000-4000-8000-000000000001';
reset role;
select is((select business_legal_name from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000001'),'Alex Owner','other tenant cannot change legal details');
select is((select business_legal_name from workspace_settings where workspace_id='73200000-0000-4000-8000-000000000002'),null::text,'one workspace does not inherit another setup');
select * from finish();
rollback;
