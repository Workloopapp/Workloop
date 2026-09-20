begin;
set local search_path=public,extensions;
select no_plan();
select ok(not has_function_privilege('authenticated','app_private.guard_receipt_object_write()','EXECUTE'),'receipt guard is not an authenticated RPC');
select ok(not has_function_privilege('anon','app_private.guard_receipt_object_write()','EXECUTE'),'receipt guard is not an anonymous RPC');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('e1000000-0000-4000-8000-000000000001','authenticated','authenticated','receipt-role@example.invalid','',now(),now(),now(),'','');
insert into workspaces(id,name) values('e2000000-0000-4000-8000-000000000001','Receipt role');
insert into workspace_members(workspace_id,user_id) values('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001');
insert into expenses(id,workspace_id,amount,category,expense_date) values('e3000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001',10,'Materials','2026-09-12');
insert into expense_receipts(workspace_id,expense_id,object_path,file_name,mime_type,size_bytes) values
('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf','receipt.pdf','application/pdf',10);
set local role supabase_storage_admin;
select lives_ok($q$insert into storage.objects(bucket_id,name) values('expense-receipts','e2000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf')$q$,'native Storage role completes reserved receipt');
select throws_ok($q$insert into storage.objects(bucket_id,name) values('expense-receipts','e2000000-0000-4000-8000-000000000001/missing.pdf')$q$,'42501',null,'native Storage role cannot complete an unreserved receipt');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','e9000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"e9000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
select throws_ok($q$insert into storage.objects(bucket_id,name) values('expense-receipts','e2000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf')$q$,'42501',null,'receipt guard retains authenticated workspace check');
reset role;
insert into account_deletion_requests(workspace_id,user_id,requested_by_user_id,email,status) values('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','receipt-role@example.invalid','processing');
set local role supabase_storage_admin;
select throws_ok($q$update storage.objects set metadata='{}' where bucket_id='expense-receipts' and name like 'e2000000-%'$q$,'42501',null,'native Storage receipt completion is denied during deletion');
reset role;
select * from finish();
rollback;
