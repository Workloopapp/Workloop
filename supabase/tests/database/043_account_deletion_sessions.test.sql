begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(28);
insert into auth.users(id,email,email_confirmed_at) values
 ('a4300000-0000-4000-8000-000000000001','session-a@example.invalid',now()),
 ('a4300000-0000-4000-8000-000000000002','session-b@example.invalid',now()),
 ('a4300000-0000-4000-8000-000000000003','session-new@example.invalid',now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('a4300000-0000-4000-8000-000000000011','a4300000-0000-4000-8000-000000000001',now(),now()),
 ('a4300000-0000-4000-8000-000000000012','a4300000-0000-4000-8000-000000000002',now(),now()),
 ('a4300000-0000-4000-8000-000000000013','a4300000-0000-4000-8000-000000000003',now(),now());
insert into public.workspaces(id,name) values
 ('a4300000-0000-4000-8000-000000000021','Session owner A'),
 ('a4300000-0000-4000-8000-000000000022','Session owner B');
insert into public.workspace_members(workspace_id,user_id) values
 ('a4300000-0000-4000-8000-000000000021','a4300000-0000-4000-8000-000000000001'),
 ('a4300000-0000-4000-8000-000000000022','a4300000-0000-4000-8000-000000000002');
insert into public.contacts(workspace_id,name) values ('a4300000-0000-4000-8000-000000000021','Owner record');
select ok(not has_function_privilege('authenticated','public.request_account_deletion_for_user(uuid,uuid,text,uuid,text)','EXECUTE'),'caller cannot forge service deletion request');
select ok(not has_function_privilege('anon','app_private.account_session_is_active(uuid,uuid)','EXECUTE'),'private session lookup is not public');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000001","session_id":"a4300000-0000-4000-8000-000000000011","role":"authenticated","aal":"aal1"}',true);
select ok(public.current_user_session_is_active(),'real active session accepted');
select is((select count(*)::int from public.contacts),1,'active owner reads own records');
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000001","session_id":"a4300000-0000-4000-8000-000000000012","role":"authenticated","aal":"aal1"}',true);
select ok(not public.current_user_session_is_active(),'another users session cannot authorize caller');
select is((select count(*)::int from public.contacts),0,'wrong session blocks RLS reads');
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000001","session_id":"invalid","role":"authenticated","aal":"aal1"}',true);
select ok(not public.current_user_session_is_active(),'malformed session fails closed without SQL exception');
reset role;
update auth.sessions set not_after=now()-interval '1 second' where id='a4300000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000001","session_id":"a4300000-0000-4000-8000-000000000011","role":"authenticated","aal":"aal1"}',true);
select ok(not public.current_user_session_is_active(),'expired session denied');
reset role;
update auth.sessions set not_after=null where id='a4300000-0000-4000-8000-000000000011';
update auth.users set banned_until=now()+interval '1 day' where id='a4300000-0000-4000-8000-000000000001';
set local role authenticated;
select ok(not public.current_user_session_is_active(),'banned account denied even with extant session');
reset role;
update auth.users set banned_until=null where id='a4300000-0000-4000-8000-000000000001';
insert into auth.mfa_factors(id,user_id,factor_type,status,secret) values(gen_random_uuid(),'a4300000-0000-4000-8000-000000000001','totp','verified','disposable-fixture');
set local role authenticated;
select ok(not app_private.current_user_meets_mfa_policy(),'existing enrolled MFA still requires AAL2');
reset role;
set local role service_role;
select throws_ok($$select public.request_account_deletion_for_user('a4300000-0000-4000-8000-000000000001','a4300000-0000-4000-8000-000000000011','aal1',null,'not_applicable')$$,'42501','Multi-factor authentication is required','final deletion transaction repeats MFA');
select throws_ok($$select public.request_account_deletion_for_user('a4300000-0000-4000-8000-000000000001','a4300000-0000-4000-8000-000000000011','aal2','a4300000-0000-4000-8000-000000000022','not_applicable')$$,'42501','Workspace access denied','explicit foreign workspace refused');
select throws_ok($$select public.request_account_deletion_for_user('a4300000-0000-4000-8000-000000000003','a4300000-0000-4000-8000-000000000012','aal1',null,'not_applicable')$$,'28000','Active verified session required','service transaction binds session to intended account');
select lives_ok($$select public.request_account_deletion_for_user('a4300000-0000-4000-8000-000000000003','a4300000-0000-4000-8000-000000000013','aal1',null,'manual_action_required')$$,'account without workspace can request deletion');
reset role;
select is((select count(*)::int from public.account_deletion_requests where requested_by_user_id='a4300000-0000-4000-8000-000000000003' and workspace_id is null),1,'no-workspace request persists without inventing a workspace');
select is((select count(*)::int from auth.sessions where user_id='a4300000-0000-4000-8000-000000000003'),0,'all account-only sessions revoked atomically');
select is((select apple_revocation_status from public.account_deletion_requests where requested_by_user_id='a4300000-0000-4000-8000-000000000003'),'manual_action_required','manual Apple unlink status retained without token');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000003","session_id":"a4300000-0000-4000-8000-000000000013","role":"authenticated","aal":"aal1"}',true);
select throws_ok($$select public.complete_onboarding('Late Business','Other','late-business','[]','{}',0,null)$$,'28000','Your sign-in is no longer active','deleted-session onboarding cannot race/recreate a workspace');
reset role;
insert into auth.sessions(id,user_id,created_at,updated_at) values('a4300000-0000-4000-8000-000000000014','a4300000-0000-4000-8000-000000000003',now(),now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000003","session_id":"a4300000-0000-4000-8000-000000000014","role":"authenticated","aal":"aal1"}',true);
select ok(not public.current_user_session_is_active(),'pending deletion blocks even a newly issued session');
reset role;
set local role service_role;
select lives_ok($$select public.request_account_deletion_for_user('a4300000-0000-4000-8000-000000000001','a4300000-0000-4000-8000-000000000011','aal2',null,'not_applicable')$$,'omitted workspace resolves existing sole-owned workspace');
reset role;
select is((select workspace_id from public.account_deletion_requests where requested_by_user_id='a4300000-0000-4000-8000-000000000001'),'a4300000-0000-4000-8000-000000000021'::uuid,'account deletion retains its real workspace for worker cleanup');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a4300000-0000-4000-8000-000000000001","session_id":"a4300000-0000-4000-8000-000000000011","role":"authenticated","aal":"aal2"}',true);
select is((select count(*)::int from public.contacts),0,'captured JWT loses RLS read access immediately');
select throws_ok($$insert into public.contacts(workspace_id,name) values('a4300000-0000-4000-8000-000000000021','Stale write')$$,'42501',null::text,'captured JWT loses write access immediately');
reset role;
select is((select count(*)::int from public.contacts),1,'request did not delete business data before worker');
select is((select count(*)::int from auth.sessions where user_id='a4300000-0000-4000-8000-000000000002'),1,'unrelated users session preserved');
select is((select count(*)::int from public.workspaces),2,'account-only request and guards create no workspaces');
select is((select count(*)::int from public.account_deletion_requests),2,'only two accepted deletion requests exist');
select ok(has_function_privilege('service_role','public.request_account_deletion_for_user(uuid,uuid,text,uuid,text)','EXECUTE'),'worker request permission remains service-only');
select * from finish();
rollback;
