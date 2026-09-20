begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(34);

select has_column('public','push_tokens','auth_session_id','tokens bind to their registering session');
select ok(not has_function_privilege('anon','app_private.push_token_session_is_active(uuid,uuid,timestamptz)','EXECUTE'),'anonymous callers cannot probe Auth sessions');
select ok(not has_function_privilege('authenticated','app_private.push_token_session_is_active(uuid,uuid,timestamptz)','EXECUTE'),'app callers cannot probe Auth sessions');
select ok(not has_function_privilege('service_role','app_private.push_token_session_is_active(uuid,uuid,timestamptz)','EXECUTE'),'helper does not expose a new service RPC');
select ok(not has_table_privilege('authenticated','public.push_tokens','UPDATE'),'users cannot assign session bindings directly');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2300000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','push-session-a@example.test','',now(),now(),now()),
('a2300000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','push-session-b@example.test','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('a2300000-0000-4000-8000-000000000011','a2300000-0000-4000-8000-000000000001',now()-interval '1 day',now(),null),
('a2300000-0000-4000-8000-000000000012','a2300000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
('a2300000-0000-4000-8000-000000000013','a2300000-0000-4000-8000-000000000001',now(),now(),now()-interval '1 second'),
('a2300000-0000-4000-8000-000000000021','a2300000-0000-4000-8000-000000000002',now(),now(),null);
insert into public.workspaces(id,name) values ('b2300000-0000-4000-8000-000000000001','Push session QA');
insert into public.workspace_members(workspace_id,user_id) values ('b2300000-0000-4000-8000-000000000001','a2300000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id,timezone) values ('b2300000-0000-4000-8000-000000000001','Europe/London');
insert into public.notification_preferences(workspace_id,quiet_hours_enabled) values ('b2300000-0000-4000-8000-000000000001',false);

create function pg_temp.push_session_claim(p_session text, p_aal text default 'aal1') returns text language sql as $$
 select set_config('request.jwt.claims',jsonb_build_object(
   'sub','a2300000-0000-4000-8000-000000000001','role','authenticated','aal',p_aal,
   'session_id',p_session,'iat',extract(epoch from now()-interval '30 minutes')::bigint,
   'exp',extract(epoch from now()+interval '30 minutes')::bigint)::text,true);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a2300000-0000-4000-8000-000000000001',true);
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000011');
select lives_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'valid older access JWT with an active session can register');
select is((select auth_session_id from public.push_tokens where token='push-session-token-not-real-123'),'a2300000-0000-4000-8000-000000000011'::uuid,'server records the verified session binding');
select lives_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','6')$$,'legacy four-argument API binds real sessions too');
select is((select apns_environment from public.push_tokens where token='push-session-token-not-real-123'),'sandbox','legacy refresh preserves signing environment');

select pg_temp.push_session_claim(null);
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'42501','active session required','missing session claim is rejected');
select pg_temp.push_session_claim('not-a-uuid');
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','6')$$,'42501','active session required','malformed session does not leak a cast error');
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000099');
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'42501','active session required','unknown or already revoked session is rejected');
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000021');
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'42501','active session required','another user active session cannot authorize this user');
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000013');
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'42501','active session required','not_after expiry rejects registration even while JWT exp remains future');
select is((select auth_session_id from public.push_tokens where token='push-session-token-not-real-123'),'a2300000-0000-4000-8000-000000000011'::uuid,'failed attempts cannot rebind an existing token');
reset role;

insert into auth.mfa_factors(id,user_id,friendly_name,factor_type,status,created_at,updated_at,secret) values
('a2300000-0000-4000-8000-000000000031','a2300000-0000-4000-8000-000000000001','Push session QA','totp','verified',now(),now(),'test-secret');
set local role authenticated;
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000011');
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','6')$$,'42501','MFA verification required','active session does not bypass existing MFA requirement');
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000011','aal2');
select lives_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'MFA-verified session remains accepted');
reset role;

create temporary table push_session_notes(label text primary key,id uuid);
with note as (insert into public.notifications(workspace_id,type,title,body,deep_link) values ('b2300000-0000-4000-8000-000000000001','booking','QA before signout','No customer data','/bookings') returning id)
insert into push_session_notes select 'before-signout',id from note;
select is((select count(*)::integer from app_private.push_delivery_outbox),1,'active session queues one device alert');
delete from auth.sessions where id='a2300000-0000-4000-8000-000000000011';
set local role authenticated;
select throws_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'42501','active session required','still-unexpired access JWT cannot register after Auth signout');
reset role;
with note as (insert into public.notifications(workspace_id,type,title,body,deep_link) values ('b2300000-0000-4000-8000-000000000001','booking','QA after signout','No customer data','/bookings') returning id)
insert into push_session_notes select 'after-signout',id from note;
select is((select count(*)::integer from app_private.push_delivery_outbox),1,'revoked binding cannot queue new business alerts');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'session deletion after registration prevents queued delivery');
select is((select last_error_code from app_private.push_delivery_outbox),'push_session_inactive','revoked queued delivery is terminally suppressed');
select is((select attempt_count from app_private.push_delivery_outbox),0,'session suppression consumes no provider attempts');

set local role authenticated;
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000012','aal2');
select lives_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox')$$,'fresh sign-in can rebind the same device');
select is((select auth_session_id from public.push_tokens where token='push-session-token-not-real-123'),'a2300000-0000-4000-8000-000000000012'::uuid,'relogin records the new session');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'relogin does not replay the signed-out session alert');

-- Existing devices stay unbound until authenticated app registration. No Auth
-- session is guessed from a user's last sign-in or another active device.
insert into public.push_tokens(id,workspace_id,user_id,token,platform,last_seen_at) values ('c2300000-0000-4000-8000-000000000001','b2300000-0000-4000-8000-000000000001','a2300000-0000-4000-8000-000000000001','push-legacy-token-not-real-123','android',now());
with note as (insert into public.notifications(workspace_id,type,title,body,deep_link) values ('b2300000-0000-4000-8000-000000000001','booking','QA legacy device','No customer data','/bookings') returning id)
insert into push_session_notes select 'legacy',id from note;
select is((select count(*)::integer from app_private.push_delivery_outbox where notification_id=(select id from push_session_notes where label='legacy')),1,'new alerts only queue for the bound device, not legacy token');
insert into app_private.push_delivery_outbox(notification_id,push_token_id,workspace_id) values ((select id from push_session_notes where label='before-signout'),'c2300000-0000-4000-8000-000000000001','b2300000-0000-4000-8000-000000000001');
create temporary table push_session_claims as select * from public.claim_push_deliveries(5);
select is((select count(*)::integer from push_session_claims),1,'eligible bound device can still obtain a lease');
select is((select last_error_code from app_private.push_delivery_outbox where push_token_id='c2300000-0000-4000-8000-000000000001'),'push_session_inactive','pre-existing legacy queue is also suppressed');

set local role authenticated;
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000012','aal2');
select lives_ok($$select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-legacy-token-not-real-123','android','6')$$,'legacy API upgrades an unbound Android token');
reset role;
-- A different still-active session must not inherit pending or claimed work
-- from the prior session even when account/workspace did not change.
insert into auth.sessions(id,user_id,created_at,updated_at) values ('a2300000-0000-4000-8000-000000000014','a2300000-0000-4000-8000-000000000001',now(),now());
set local role authenticated;
select pg_temp.push_session_claim('a2300000-0000-4000-8000-000000000014','aal2');
select public.register_push_token('b2300000-0000-4000-8000-000000000001','push-session-token-not-real-123','ios','10','sandbox');
reset role;
select is((select last_error_code from app_private.push_delivery_outbox where id=(select delivery_id from push_session_claims)),'device_session_changed','session rebinding cancels old claimed work');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select ok(not public.finish_push_delivery((select delivery_id from push_session_claims),(select delivery_lease_token from push_session_claims),'sent','not-a-real-provider-message',null,false),'obsolete claim cannot finish after session rebinding');

insert into public.notifications(workspace_id,type,title,body,deep_link) values ('b2300000-0000-4000-8000-000000000001','booking','QA expiry while queued','No customer data','/bookings');
update auth.sessions set not_after=now()-interval '1 second' where id in ('a2300000-0000-4000-8000-000000000012','a2300000-0000-4000-8000-000000000014');
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'session lifetime expiry is rechecked before delivery');
select is((select count(*)::integer from app_private.push_delivery_outbox where status in ('pending','processing')),0,'inactive sessions leave no eligible queued backlog');

select * from finish();
rollback;
