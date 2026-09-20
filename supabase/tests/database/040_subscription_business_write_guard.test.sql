begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

-- Real business tables and RPCs: a closed app gate must not be the only
-- protection when an older client or a direct Data API request makes a write.
update app_private.subscription_config
  set beta_open=false,apple_sales_enabled=true,enforcement_enabled=false;
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
values('a4000000-0000-4000-8000-000000000001','authenticated','authenticated','subscription-owner@example.invalid',now(),now(),now()),
      ('a4000000-0000-4000-8000-000000000002','authenticated','authenticated','subscription-new@example.invalid',now(),now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('a4000000-0000-4000-8000-000000000101','a4000000-0000-4000-8000-000000000001',now(),now()),
('a4000000-0000-4000-8000-000000000102','a4000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name)
values('a4010000-0000-4000-8000-000000000001','Subscription business'),
      ('a4010000-0000-4000-8000-000000000002','New subscription business');
insert into public.workspace_members(workspace_id,user_id)
values('a4010000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001'),
      ('a4010000-0000-4000-8000-000000000002','a4000000-0000-4000-8000-000000000002');
insert into public.contacts(id,workspace_id,name)
values('a4020000-0000-4000-8000-000000000001','a4010000-0000-4000-8000-000000000001','Client to retain in snapshot');
insert into public.expenses(id,workspace_id,amount,category,expense_date)
values('a4030000-0000-4000-8000-000000000001','a4010000-0000-4000-8000-000000000001',10,'Materials',current_date);

create function pg_temp.save_subscription_document(
  document_id uuid,expected_revision integer default null,notes_value text default 'Saved scope')
returns jsonb language sql as $$
  select public.save_business_document(
    'a4010000-0000-4000-8000-000000000001',
    jsonb_build_object('type','quote','contact_id','a4020000-0000-4000-8000-000000000001',
      'issue_date',current_date,'due_date',current_date+7,'tax_rate',0,
      'business_snapshot',jsonb_build_object('name','Business','address','Business address'),
      'client_snapshot',jsonb_build_object('name','Client to retain in snapshot','address','Client address'),
      'notes',notes_value),
    '[{"description":"Client work","quantity":1,"unit_price":25}]'::jsonb,
    document_id,expected_revision);
$$;

select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"a4000000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select lives_ok($q$insert into public.mileage_entries(id,workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type)
 values('a4040000-0000-4000-8000-000000000001','a4010000-0000-4000-8000-000000000001',current_date,100,'Original visit','ab12cde','car_van')$q$,
 'disabled rollout still permits valid mileage writes');
select is(pg_temp.save_subscription_document('a4050000-0000-4000-8000-000000000001')->>'status','draft',
 'disabled rollout still permits a valid document workflow');
select lives_ok($q$insert into public.workspace_tax_estimates(workspace_id,tax_year,rules_version,jurisdiction,turnover_minor,non_vehicle_expenses_minor,actual_vehicle_expenses_minor,paid_to_hmrc_minor,reserve_minor,vehicle_method)
 values('a4010000-0000-4000-8000-000000000001','2026/27','uk-ewni-2026-27-v1','england',5000000,1000000,0,0,0,'actual')$q$,
 'disabled rollout still permits reviewed tax inputs');
reset role;
select set_config('request.jwt.claims','{}',true);
insert into app_private.account_access(user_id,trial_started_at)
values('a4000000-0000-4000-8000-000000000001',now()-interval '31 days');
update app_private.subscription_config set enforcement_enabled=true;
select is(app_private.workloop_access_for('a4000000-0000-4000-8000-000000000001')->>'has_access','false',
 'expired fixture has no business write access');
select is(app_private.workloop_access_for('a4000000-0000-4000-8000-000000000002')->>'state','trial_available',
 'new fixture has no separate no-card trial');

select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"a4000000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select throws_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type)
 values('a4010000-0000-4000-8000-000000000001',current_date,200,'Unpaid new visit','ab12cde','car_van')$q$,
 'PT402',null,'expired owner cannot insert mileage through the Data API');
select throws_ok($q$update public.mileage_entries set miles_hundredths=200 where id='a4040000-0000-4000-8000-000000000001'$q$,
 'PT402',null,'expired owner cannot update existing mileage');
select throws_ok($q$select pg_temp.save_subscription_document('a4050000-0000-4000-8000-000000000002')$q$,
 'PT402',null,'expired owner cannot create a document through a definer-backed workflow');
select throws_ok($q$select pg_temp.save_subscription_document('a4050000-0000-4000-8000-000000000001',1,'Unpaid edit')$q$,
 'PT402',null,'expired owner cannot change a saved document through the RPC');
select throws_ok($q$update public.workspace_tax_estimates set reserve_minor=1000 where workspace_id='a4010000-0000-4000-8000-000000000001'$q$,
 'PT402',null,'expired owner cannot bypass access through tax inputs');
select throws_ok($q$insert into public.expense_receipts(workspace_id,expense_id,object_path,file_name,mime_type,size_bytes)
 values('a4010000-0000-4000-8000-000000000001','a4030000-0000-4000-8000-000000000001',
 'a4010000-0000-4000-8000-000000000001/a4030000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','receipt.pdf','application/pdf',10)$q$,
 'PT402',null,'expired owner cannot reserve another receipt upload');
select is((select miles_hundredths from public.mileage_entries where id='a4040000-0000-4000-8000-000000000001'),100,
 'failed write leaves existing mileage readable and unchanged');
select is((select notes from public.business_documents where id='a4050000-0000-4000-8000-000000000001'),'Saved scope',
 'failed RPC leaves document content readable and unchanged');
select is((select count(*) from public.business_documents),1::bigint,
 'failed document creation leaves no partial draft');
select lives_ok($q$delete from public.contacts where id='a4020000-0000-4000-8000-000000000001'$q$,
 'expired access does not prevent deleting a client with a linked document');
select is((select contact_id from public.business_documents where id='a4050000-0000-4000-8000-000000000001'),null::uuid,
 'client deletion clears only the optional document relationship');
select is((select client_snapshot->>'name' from public.business_documents where id='a4050000-0000-4000-8000-000000000001'),'Client to retain in snapshot',
 'client deletion preserves the saved document snapshot');
select lives_ok($q$delete from public.mileage_entries where id='a4040000-0000-4000-8000-000000000001'$q$,
 'expired owner can still remove an existing mileage record');
reset role;

select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"a4000000-0000-4000-8000-000000000102"}',true);
set local role authenticated;
select throws_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type)
 values('a4010000-0000-4000-8000-000000000002',current_date,100,'Before Apple authorisation','ab12cde','car_van')$q$,
 'PT402',null,'new owner cannot write before authorising a verified store trial');
select is((select count(*) from public.business_documents),0::bigint,
 'export access remains isolated from another business');
reset role;
select set_config('request.jwt.claims','{}',true);
insert into app_private.account_access(user_id,beta_lifetime,beta_granted_at,grant_reason)
values('a4000000-0000-4000-8000-000000000002',true,now(),'test_lifetime_beta');
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"a4000000-0000-4000-8000-000000000102"}',true);
set local role authenticated;
select lives_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type)
 values('a4010000-0000-4000-8000-000000000002',current_date,100,'Lifetime beta visit','ab12cde','car_van')$q$,
 'lifetime beta owner retains normal business writes');
reset role;

select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select lives_ok($q$update public.business_documents set notes='Provider reconciliation' where id='a4050000-0000-4000-8000-000000000001'$q$,
 'trusted provider reconciliation with no end-user subject is not blocked');
reset role;
select set_config('request.jwt.claims','{}',true);
select * from finish();
rollback;
