begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(38);

select ok(not has_function_privilege('anon','public.claim_push_deliveries(integer)','EXECUTE'),'anonymous callers cannot claim');
select ok(not has_function_privilege('authenticated','public.claim_push_deliveries(integer)','EXECUTE'),'app users cannot claim');
select ok(not has_function_privilege('authenticated','app_private.push_delivery_policy(uuid,text,boolean,timestamptz)','EXECUTE'),'private policy is not an app RPC');
select ok(has_function_privilege('service_role','public.claim_push_deliveries(integer)','EXECUTE'),'service worker retains claim access');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2200000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','push-policy@example.test','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values ('a2200000-0000-4000-8000-000000000011','a2200000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id,name) values ('b2200000-0000-4000-8000-000000000001','Push policy QA');
insert into public.workspace_members(workspace_id,user_id) values
('b2200000-0000-4000-8000-000000000001','a2200000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id,timezone) values ('b2200000-0000-4000-8000-000000000001','Europe/London');
insert into public.notification_preferences(workspace_id,quiet_hours_enabled) values ('b2200000-0000-4000-8000-000000000001',true);
insert into public.push_tokens(id,workspace_id,user_id,auth_session_id,token,platform,apns_environment,last_seen_at) values
('c2200000-0000-4000-8000-000000000001','b2200000-0000-4000-8000-000000000001','a2200000-0000-4000-8000-000000000001','a2200000-0000-4000-8000-000000000011','push-policy-fixture-token-not-real','ios','sandbox',now());

select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 19:59:00+00')),'2026-09-05 19:59:00+00'::timestamptz,'20:59 BST is outside quiet hours');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 20:00:00+00')),'2026-09-06 06:00:00+00'::timestamptz,'21:00 BST defers until next07:00 BST');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 05:59:59+00')),'2026-09-05 06:00:00+00'::timestamptz,'early morning waits until07:00');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 06:00:00+00')),'2026-09-05 06:00:00+00'::timestamptz,'07:00 is deliverable');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-03-28 21:00:00+00')),'2026-03-29 06:00:00+00'::timestamptz,'spring DST uses next local07:00 not fixed elapsed hours');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-10-24 20:00:00+00')),'2026-10-25 07:00:00+00'::timestamptz,'autumn DST uses next local07:00');
update public.workspace_settings set timezone='Asia/Kolkata' where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 16:00:00+00')),'2026-09-06 01:30:00+00'::timestamptz,'half-hour timezone uses business-local morning');
update public.workspace_settings set timezone='Europe/London' where workspace_id='b2200000-0000-4000-8000-000000000001';
update public.notification_preferences set quiet_hours_enabled=false,quiet_sundays=true where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select skip_reason from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','morning_digest',false,'2026-09-06 07:00:00+00')),'sunday_morning_brief_disabled','Sunday morning brief is suppressed');
select is((select skip_reason from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-06 07:00:00+00')),null::text,'Quiet Sundays does not suppress business activity');
select is((select skip_reason from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','morning_digest',false,'2026-09-07 07:00:00+00')),null::text,'Monday brief remains enabled');
select is((select next_allowed_at from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',false,'2026-09-05 22:00:00+00')),'2026-09-05 22:00:00+00'::timestamptz,'disabled quiet hours permit evening delivery');
select is((select skip_reason from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','booking',true,'2026-09-05 12:00:00+00')),'notification_read','read notification no longer needs an alert');

update public.notification_preferences set all_notifications=false where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select skip_reason from app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001','future_category',false,now())),'notification_preferences_disabled','master protects unknown future categories');
update public.notification_preferences set all_notifications=true,payment_received=false,new_booking=false,booking_request=false,no_show=false,invoice_overdue=false,lead_followup=false,morning_digest=false,weekly_summary=false,task_due_morning=false where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select count(*)::integer from unnest(array['payment_received','payment','new_booking','booking','booking_request','no_show','invoice_overdue','lead_followup','morning_digest','weekly_summary','task_due','task']) kind cross join lateral app_private.push_delivery_policy('b2200000-0000-4000-8000-000000000001',kind,false,now()) policy where policy.skip_reason='notification_preferences_disabled'),12,'every known category and legacy alias respects its current switch');
update public.notification_preferences set payment_received=true,new_booking=true,booking_request=true,no_show=true,invoice_overdue=true,lead_followup=true,morning_digest=true,weekly_summary=true,task_due_morning=true,quiet_sundays=false where workspace_id='b2200000-0000-4000-8000-000000000001';

create function pg_temp.add_push_policy_fixture(p_number integer) returns uuid language plpgsql as $$
declare v_notification uuid; v_delivery uuid;
begin
 insert into public.notifications(workspace_id,type,title,body,deep_link)
 values('b2200000-0000-4000-8000-000000000001','booking','QA '||p_number,'No customer data','/bookings') returning id into v_notification;
 select id into v_delivery from app_private.push_delivery_outbox where notification_id=v_notification;
 return v_delivery;
end;
$$;
create temporary table push_policy_ids(label text primary key,id uuid);
insert into push_policy_ids values ('master',pg_temp.add_push_policy_fixture(1));
update public.notification_preferences set all_notifications=false where workspace_id='b2200000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'turning master off after enqueue prevents dispatch');
select is((select last_error_code from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='master')),'notification_preferences_disabled','suppression reason is recorded');
select is((select attempt_count from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='master')),0,'suppression does not consume provider attempts');
update public.notification_preferences set all_notifications=true where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'switching back on does not replay a suppressed old update');

insert into push_policy_ids values ('category',pg_temp.add_push_policy_fixture(2));
update public.notification_preferences set new_booking=false where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'category switch is rechecked after enqueue');
update public.notification_preferences set new_booking=true where workspace_id='b2200000-0000-4000-8000-000000000001';
insert into push_policy_ids values ('read',pg_temp.add_push_policy_fixture(3));
update public.notifications set read=true where id=(select notification_id from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='read'));
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'reading a queued notification prevents its push');

-- Pick a named timezone currently inside quiet hours without changing the real
-- database clock. This exercises dispatch/retry logic at any CI wall-clock time.
insert into push_policy_ids values ('quiet',pg_temp.add_push_policy_fixture(4));
update public.workspace_settings set timezone=(select zone from (values ('Pacific/Honolulu'),('Asia/Tokyo'),('Europe/London'),('America/New_York')) zones(zone) where (now() at time zone zone)::time<time '07:00' or (now() at time zone zone)::time>=time '21:00' limit 1) where workspace_id='b2200000-0000-4000-8000-000000000001';
update public.notification_preferences set quiet_hours_enabled=true where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'quiet hours switched on after enqueue defer dispatch');
select ok((select status='pending' and next_attempt_at>now() and attempt_count=0 from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='quiet')),'deferred job remains pending without using attempts');
update public.notification_preferences set quiet_hours_enabled=false where workspace_id='b2200000-0000-4000-8000-000000000001';
update app_private.push_delivery_outbox set next_attempt_at=now() where id=(select id from push_policy_ids where label='quiet');
create temporary table push_policy_claim as select * from public.claim_push_deliveries(5);
select is((select count(*)::integer from push_policy_claim),1,'an allowed job still obtains a delivery lease');
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'another claim cannot take an active lease');
select ok(public.finish_push_delivery((select delivery_id from push_policy_claim),(select delivery_lease_token from push_policy_claim),'retry',null,'apns_unavailable',false),'provider failure retains existing retry API');
update public.notification_preferences set quiet_hours_enabled=true where workspace_id='b2200000-0000-4000-8000-000000000001';
update app_private.push_delivery_outbox set next_attempt_at=now() where id=(select id from push_policy_ids where label='quiet');
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'provider retry is rechecked against quiet hours');
select is((select attempt_count from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='quiet')),1,'quiet retry deferral preserves existing attempt count');
update public.notification_preferences set quiet_hours_enabled=false where workspace_id='b2200000-0000-4000-8000-000000000001';
update app_private.push_delivery_outbox set next_attempt_at=now(),status='processing',lease_expires_at=now()-interval '1 second',lease_token=gen_random_uuid() where id=(select id from push_policy_ids where label='quiet');
delete from push_policy_claim;
insert into push_policy_claim select * from public.claim_push_deliveries(5);
select is((select count(*)::integer from push_policy_claim),1,'expired processing lease is reclaimable');
update app_private.push_delivery_outbox set attempt_count=8 where id=(select id from push_policy_ids where label='quiet');
select ok(public.finish_push_delivery((select delivery_id from push_policy_claim),(select delivery_lease_token from push_policy_claim),'retry',null,'apns_unavailable',false),'eighth provider attempt can finish');
select is((select status from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='quiet')),'failed','existing retry ceiling is preserved');

insert into push_policy_ids values ('front-read',pg_temp.add_push_policy_fixture(6)),('behind-valid',pg_temp.add_push_policy_fixture(7));
update public.notifications set read=true where id=(select notification_id from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='front-read'));
update app_private.push_delivery_outbox set next_attempt_at=now()-interval '2 seconds' where id=(select id from push_policy_ids where label='front-read');
update app_private.push_delivery_outbox set next_attempt_at=now()-interval '1 second' where id=(select id from push_policy_ids where label='behind-valid');
delete from push_policy_claim;
insert into push_policy_claim select * from public.claim_push_deliveries(1);
select is((select delivery_id from push_policy_claim),(select id from push_policy_ids where label='behind-valid'),'a suppressed front row does not consume a one-item delivery batch');
select is((select status from app_private.push_delivery_outbox where id=(select id from push_policy_ids where label='front-read')),'failed','the scanned front row is terminally suppressed');

insert into push_policy_ids values ('membership',pg_temp.add_push_policy_fixture(5));
delete from public.workspace_members where workspace_id='b2200000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.claim_push_deliveries(5)),0,'lost workspace membership still blocks dispatch');
select is((select count(*)::integer from public.notifications where workspace_id='b2200000-0000-4000-8000-000000000001'),7,'delivery suppression preserves the existing in-app history');

select * from finish();
rollback;
