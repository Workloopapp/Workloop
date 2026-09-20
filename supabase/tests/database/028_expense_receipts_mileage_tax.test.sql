begin;
set local search_path = public, extensions;
select no_plan();
set constraints all immediate;
select ok(not has_table_privilege('anon','public.expense_receipts','SELECT'), 'anonymous users cannot read receipt metadata');
select ok(not has_table_privilege('authenticated','public.expense_receipts','UPDATE'), 'receipt metadata is immutable');
select is((select public from storage.buckets where id='expense-receipts'), false, 'receipt bucket is private');
select is((select file_size_limit from storage.buckets where id='expense-receipts'),10485760::bigint,'receipt file size capped server side');

select is((select allowed_mime_types from storage.buckets where id='expense-receipts'),array['application/pdf','image/jpeg','image/png'],'bucket enforces the supported MIME allowlist');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('71000000-0000-4000-8000-000000000001','authenticated','authenticated','tax-a@example.invalid','',now(),now(),now(),'',''),
('72000000-0000-4000-8000-000000000002','authenticated','authenticated','tax-b@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000001',now(),now()),
('72000000-0000-4000-8000-000000000102','72000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
('71100000-0000-4000-8000-000000000001','Tax A'),('72200000-0000-4000-8000-000000000002','Tax B');
insert into public.workspace_members(workspace_id,user_id) values
('71100000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001'),
('72200000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000002');
insert into public.expenses(id,workspace_id,amount,category,expense_date) values
('71300000-0000-4000-8000-000000000001','71100000-0000-4000-8000-000000000001',10,'Materials','2026-09-08'),
('72300000-0000-4000-8000-000000000002','72200000-0000-4000-8000-000000000002',10,'Materials','2026-09-08');
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"71000000-0000-4000-8000-000000000101"}',true);
select lives_ok($q$insert into public.expense_receipts(workspace_id,expense_id,object_path,file_name,mime_type,size_bytes) values
('71100000-0000-4000-8000-000000000001','71300000-0000-4000-8000-000000000001','71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','receipt.pdf','application/pdf',10)$q$,'owner can reserve a receipt for their expense');
select throws_ok($q$insert into public.expense_receipts(workspace_id,expense_id,object_path,file_name,mime_type,size_bytes) values
('71100000-0000-4000-8000-000000000001','72300000-0000-4000-8000-000000000002','71100000-0000-4000-8000-000000000001/72300000-0000-4000-8000-000000000002/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','receipt.pdf','application/pdf',10)$q$,'23503',null,'cannot link another workspace expense');
select lives_ok($q$insert into storage.objects(bucket_id,name,metadata) values ('expense-receipts',
'71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','{"mimetype":"application/pdf","size":10}')$q$,'owner can upload a reserved path');
select throws_ok($q$insert into storage.objects(bucket_id,name,metadata) values ('expense-receipts',
'71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.pdf','{"mimetype":"application/pdf","size":10}')$q$,'42501',null,'unreserved upload rejected');
select lives_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type) values
('71100000-0000-4000-8000-000000000001','2026-09-08',1250,'Client visit','ab12cde','car_van')$q$,'owner can log precise mileage');
select throws_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type) values
('71100000-0000-4000-8000-000000000001','2026-09-08',0,'Client visit','ab12cde','car_van')$q$,'23514',null,'zero miles rejected');
select lives_ok($q$insert into public.workspace_tax_estimates(workspace_id,tax_year,rules_version,jurisdiction,turnover_minor,non_vehicle_expenses_minor,actual_vehicle_expenses_minor,paid_to_hmrc_minor,reserve_minor,vehicle_method) values
('71100000-0000-4000-8000-000000000001','2026/27','uk-ewni-2026-27-v1','england',5000000,1000000,0,0,0,'actual')$q$,'owner can save reviewed tax inputs');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select lives_ok($q$update storage.objects set metadata='{"mimetype":"application/pdf","size":10}' where bucket_id='expense-receipts'$q$,'Storage service_role completion succeeds without an end-user subject');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"72000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"72000000-0000-4000-8000-000000000102"}',true);
select is((select count(*) from public.expense_receipts),0::bigint,'receipt metadata hidden across tenants');
select is((select count(*) from storage.objects where bucket_id='expense-receipts'),0::bigint,'receipt bytes hidden across tenants');
select is((select count(*) from public.mileage_entries),0::bigint,'mileage hidden across tenants');
select is((select count(*) from public.workspace_tax_estimates),0::bigint,'tax inputs hidden across tenants');
select throws_ok($q$insert into public.mileage_entries(workspace_id,journey_date,miles_hundredths,purpose,vehicle,vehicle_type) values
('71100000-0000-4000-8000-000000000001','2026-09-08',100,'Client visit','ab12cde','car_van')$q$,'42501',null,'cross-workspace writes rejected');
reset role;
insert into auth.mfa_factors(id,user_id,factor_type,status) values ('71400000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','totp','verified');
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"71000000-0000-4000-8000-000000000101"}',true);
select is((select count(*) from public.expense_receipts),0::bigint,'MFA-enrolled owner must step up for metadata');
select is((select count(*) from storage.objects where bucket_id='expense-receipts'),0::bigint,'MFA-enrolled owner must step up for files');
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"71000000-0000-4000-8000-000000000101"}',true);
select is((select count(*) from public.expense_receipts),1::bigint,'stepped-up owner can access receipt');
select is((select count(*) from storage.objects where bucket_id='expense-receipts'),1::bigint,'stepped-up owner can access file');
reset role;
insert into public.account_deletion_requests(workspace_id,user_id,requested_by_user_id,email,status) values
('71100000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','tax-a@example.invalid','requested');
set local role authenticated;
select throws_ok($q$insert into public.expense_receipts(workspace_id,expense_id,object_path,file_name,mime_type,size_bytes) values
('71100000-0000-4000-8000-000000000001','71300000-0000-4000-8000-000000000001','71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.pdf','receipt.pdf','application/pdf',10)$q$,'42501',null,'deletion-pending owner cannot reserve more receipts');
select is((select count(*) from public.expense_receipts),1::bigint,'deletion keeps cleanup metadata readable');
reset role;
set local role service_role;
select throws_ok($q$insert into storage.objects(bucket_id,name,metadata) values ('expense-receipts',
'71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','{}')$q$,'42501',null,'privileged upload completion cannot bypass deletion guard');
reset role;
update public.account_deletion_requests set status='processing' where workspace_id='71100000-0000-4000-8000-000000000001';
set local role service_role;
select throws_ok($q$insert into storage.objects(bucket_id,name,metadata) values ('expense-receipts',
'71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','{}')$q$,'42501',null,'processing deletion rejects in-flight completion');
reset role;
set constraints all deferred;
delete from public.workspaces where id='71100000-0000-4000-8000-000000000001';
select is((select count(*) from public.mileage_entries),0::bigint,'workspace deletion cascades mileage');
select is((select count(*) from public.workspace_tax_estimates),0::bigint,'workspace deletion cascades tax inputs');
select is((select count(*) from public.expense_receipts),0::bigint,'workspace deletion cascades receipt metadata');
select throws_ok($q$insert into storage.objects(bucket_id,name,metadata) values ('expense-receipts',
'71100000-0000-4000-8000-000000000001/71300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','{}')$q$,'42501',null,'upload completion after metadata cascade is rejected');
select * from finish();
rollback;
