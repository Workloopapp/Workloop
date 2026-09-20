begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(16);
insert into auth.users(id,email,email_confirmed_at) values
 ('a4200000-0000-4000-8000-000000000001','bootstrap-a@example.invalid',now()),
 ('a4200000-0000-4000-8000-000000000002','bootstrap-b@example.invalid',now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('a4200000-0000-4000-8000-000000000011','a4200000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id,name) values
 ('a4200000-0000-4000-8000-000000000021','Orphan remains private'),
 ('a4200000-0000-4000-8000-000000000022','Other owner');
insert into public.workspace_members(workspace_id,user_id) values
 ('a4200000-0000-4000-8000-000000000022','a4200000-0000-4000-8000-000000000002');
insert into public.contacts(workspace_id,name) values
 ('a4200000-0000-4000-8000-000000000021','Private orphan record');
select ok(not has_table_privilege('authenticated','public.workspace_members','INSERT'),'client membership INSERT revoked');
select ok(not has_table_privilege('authenticated','public.workspaces','INSERT'),'client workspace INSERT revoked');
select ok(not has_function_privilege('authenticated','app_private.workspace_has_no_members(uuid)','EXECUTE'),'empty workspace helper is private');
select ok(not has_function_privilege('anon','app_private.enqueue_notification_push()','EXECUTE'),'trigger-only function is not anonymous callable');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4200000-0000-4000-8000-000000000001","session_id":"a4200000-0000-4000-8000-000000000011","role":"authenticated","aal":"aal1"}',true);
select throws_ok($$insert into public.workspace_members(workspace_id,user_id) values ('a4200000-0000-4000-8000-000000000021','a4200000-0000-4000-8000-000000000001')$$,'42501','permission denied for table workspace_members','known orphan UUID cannot be claimed');
select throws_ok($$insert into public.workspace_members(workspace_id,user_id) values ('a4200000-0000-4000-8000-000000000022','a4200000-0000-4000-8000-000000000001')$$,'42501','permission denied for table workspace_members','another owner workspace cannot be claimed');
select throws_ok($$insert into public.workspaces(name) values ('Unauthorized creation')$$,'42501','permission denied for table workspaces','client cannot create an unattached workspace');
select is((select count(*)::int from public.contacts),0,'orphan customer data remains unreadable');
select lives_ok($$select public.complete_onboarding('New Business','Other','bootstrap-new','[]','{}',0,null)$$,'existing verified atomic onboarding still works');
select is((select count(*)::int from public.workspaces),1,'new owner sees only their own newly created workspace');
select lives_ok($$select public.complete_onboarding('New Business','Other','bootstrap-new','[]','{}',0,null)$$,'onboarding retry remains idempotent');
select is((select count(*)::int from public.workspace_members),1,'onboarding retry cannot create a second membership');
reset role;
select is((select count(*)::int from public.workspace_members where workspace_id='a4200000-0000-4000-8000-000000000021'),0,'orphan membership remains empty');
select is((select count(*)::int from public.contacts where workspace_id='a4200000-0000-4000-8000-000000000021'),1,'existing orphan records were preserved');
set local role service_role;
select lives_ok($$insert into public.workspaces(name) values ('Authorized server fixture')$$,'service-role workspace administration is preserved');
reset role;
select is((select count(*)::int from public.workspaces),4,'only expected atomic/server workspace creations occurred');
select * from finish();
rollback;
