begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(22);

select has_column('public','push_tokens','apns_environment','tokens record the signed APNs environment');
select has_function('public','register_push_token',array['uuid','text','text','text'],'legacy registration remains callable');
select has_function('public','register_push_token',array['uuid','text','text','text','text'],'environment registration exists');
select ok(not has_function_privilege('anon','public.register_push_token(uuid,text,text,text,text)','EXECUTE'),'anon cannot register');
select ok(not (select prosecdef from pg_proc where oid='public.register_push_token(uuid,text,text,text,text)'::regprocedure),'public registration is an invoker wrapper');
select ok(not has_function_privilege('authenticated','public.finish_push_delivery(uuid,uuid,text,text,text,boolean,integer)','EXECUTE'),'users cannot manipulate provider retries');

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,created_at, updated_at) values
('96000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','push-env-a@example.test','',now(),now(),now()),
('96000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','push-env-b@example.test','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
('96000000-0000-4000-8000-000000000011','96000000-0000-4000-8000-000000000001',now(),now()),
('96000000-0000-4000-8000-000000000012','96000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
('97000000-0000-4000-8000-000000000001','Push A'),('97000000-0000-4000-8000-000000000002','Push B');
insert into public.workspace_members(workspace_id,user_id) values
('97000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001'),
('97000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id,timezone) values ('97000000-0000-4000-8000-000000000001','Europe/London');
insert into public.notification_preferences(workspace_id,quiet_hours_enabled) values ('97000000-0000-4000-8000-000000000001',false);

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"96000000-0000-4000-8000-000000000011"}',true);
select lives_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','ios-environment-token-1234567890','ios','6')$$,'old app can register without environment');
select is((select apns_environment from public.push_tokens where token='ios-environment-token-1234567890'),null::text,'legacy token leaves environment unknown');
select lives_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','ios-environment-token-1234567890','ios','10','production')$$,'new app registers production environment');
select is((select apns_environment from public.push_tokens where token='ios-environment-token-1234567890'),'production','signed environment is stored');
select lives_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','ios-environment-token-1234567890','ios','6')$$,'legacy refresh remains compatible');
select is((select apns_environment from public.push_tokens where token='ios-environment-token-1234567890'),'production','legacy refresh preserves known environment');
select throws_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','android-environment-token-1234567890','android','10','sandbox')$$,'22023','invalid APNs environment','Android cannot claim an APNs environment');
select throws_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','ios-environment-token-1234567890','ios','10','release')$$,'22023','invalid APNs environment','build mode is not a signing environment');
select throws_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000002','ios-environment-token-1234567890','ios','10','sandbox')$$,'42501','workspace membership required','foreign-workspace registration is blocked');
reset role;

insert into auth.mfa_factors(id,user_id,friendly_name,factor_type,status,created_at,updated_at,secret) values
('96000000-0000-4000-8000-000000000099','96000000-0000-4000-8000-000000000001','Push QA','totp','verified',now(),now(),'test-secret');
set local role authenticated;
select throws_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','ios-environment-token-1234567890','ios','6')$$,'42501','MFA verification required','legacy registration cannot bypass opted-in MFA');
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"96000000-0000-4000-8000-000000000011"}',true);
select lives_ok($$select public.register_push_token('97000000-0000-4000-8000-000000000001','android-environment-token-1234567890','android','10',null)$$,'verified session can register Android');
reset role;

insert into public.notifications(workspace_id,type,title,body,deep_link) values
('97000000-0000-4000-8000-000000000001','booking','Private title','Private body','/bookings');
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table push_env_claim as select * from public.claim_push_deliveries(5);
reset role;
select is((select count(*)::integer from push_env_claim),2,'worker claims both platforms');
select is((select apns_environment from push_env_claim where platform='ios'),'production','worker receives per-device environment');
set local role service_role;
select ok(public.finish_push_delivery((select delivery_id from push_env_claim where platform='ios'),(select delivery_lease_token from push_env_claim where platform='ios'),'retry',null,'apns_throttled',false,3600),'worker records provider Retry-After');
reset role;
select ok((select next_attempt_at >= now()+interval '1 hour' from app_private.push_delivery_outbox where id=(select delivery_id from push_env_claim where platform='ios')),'Retry-After extends database backoff');

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"96000000-0000-4000-8000-000000000012"}',true);
select public.register_push_token('97000000-0000-4000-8000-000000000002','ios-environment-token-1234567890','ios','10','sandbox');
reset role;
select is((select status from app_private.push_delivery_outbox where id=(select delivery_id from push_env_claim where platform='ios')),'failed','changing account cancels the previous account queued alert');
select * from finish();
rollback;
