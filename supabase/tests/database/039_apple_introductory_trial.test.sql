begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
select is((select billing_reminders_enabled from app_private.subscription_config),false,'migration does not enable billing emails');
select ok(not has_table_privilege('authenticated','app_private.subscription_trial_email_outbox','SELECT'),'billing email receipts are private to service role');
select ok(not has_function_privilege('authenticated','public.claim_subscription_trial_emails(integer)','EXECUTE'),'customers cannot claim other accounts email');
select ok(not has_function_privilege('anon','public.prepare_subscription_trial_email(uuid,uuid)','EXECUTE'),'anonymous users cannot read email recipients');
update app_private.subscription_config set beta_open=false,apple_sales_enabled=true,enforcement_enabled=true;
insert into auth.users(id,email,email_confirmed_at,created_at) values
('a3900000-0000-4000-8000-000000000001','trial-one@example.test',now(),now()),
('a3900000-0000-4000-8000-000000000002','trial-two@example.test',now(),now());
insert into app_private.account_access(user_id,trial_started_at) values
('a3900000-0000-4000-8000-000000000001',now()-interval '10 days');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'state','trial','a trial started before rollout is honored');
select is((app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'trial_ends_at')::timestamptz,now()+interval '20 days','legacy trial keeps its original expiry');
update app_private.account_access set trial_started_at=now()-interval '31 days';
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000002')->>'state','trial_available','new account waits for Apple authorisation');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000002')->>'has_access','false','available trial does not grant access');
create function pg_temp.intro_record(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
 select jsonb_build_object('platform','apple','environment','Production',
 'user_id','a3900000-0000-4000-8000-000000000001','original_transaction_id','3900','transaction_id','3901',
 'product_id','workloop_monthly','expires_at',now()+interval '6 days 23 hours',
 'purchased_at',now()-interval '23 days','is_free_trial',true,'signed_at',now())||extra;
$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object('environment','Sandbox')));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'has_access','false','a sandbox introductory trial cannot grant production access');
select public.record_verified_store_subscription(pg_temp.intro_record());
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'state','store_trial','signed Apple free intro period is a store trial');
select is((app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'trial_ends_at')::timestamptz,now()+interval '6 days 23 hours','Apple expiry replaces legacy expiry while store trial is active');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'auto_renews',null,'transaction-only receipt cannot invent renewal consent');
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'renewal_signed_at',now(),'auto_renews',true,'renews_at',now()+interval '6 days 23 hours')));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'auto_renews','true','verified renewal status is exposed');
select is((app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'renews_at')::timestamptz,now()+interval '6 days 23 hours','next renewal uses signed Apple date');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'disabled rollout flag suppresses all email claims');
select is((select count(*) from app_private.subscription_trial_email_outbox),0::bigint,'disabled flag queues no email receipts');
update app_private.subscription_config set billing_reminders_enabled=true;
create temporary table intro_claims as select * from public.claim_subscription_trial_emails();
select is((select count(*) from intro_claims),1::bigint,'seven-day reminder claimed once for production account');
select is((select days_before from app_private.subscription_trial_email_outbox),7,'first reminder is seven days before first charge');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'another worker cannot duplicate a leased claim');
select is((select count(*) from intro_claims c cross join lateral public.prepare_subscription_trial_email(c.outbox_id,c.lease_token)),1::bigint,'eligible claim resolves verified recipient immediately before send');
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'renewal_signed_at',now()+interval '1 minute','auto_renews',false)));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'state','store_trial','cancelling renewal preserves trial access through expiry');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'renews_at',null,'cancelled trial shows no future charge date');
select is((select count(*) from intro_claims c cross join lateral public.prepare_subscription_trial_email(c.outbox_id,c.lease_token)),0::bigint,'cancellation after claim suppresses provider send');
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'signed_at',now()+interval '2 minutes')));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'auto_renews','false','a newer transaction restore cannot erase cancellation');
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'renewal_signed_at',now(),'auto_renews',true)));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'auto_renews','false','older renewal snapshot cannot re-enable billing');
select is((select public.finish_subscription_trial_email(outbox_id,lease_token,false,true) from intro_claims),'skipped','suppressed claim is completed without delivery');
-- A corrected signed period places the three-day reminder in its own window.
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'expires_at',now()+interval '2 days 23 hours','signed_at',now()+interval '3 minutes',
 'renewal_signed_at',now()+interval '3 minutes','auto_renews',true,'renews_at',now()+interval '2 days 23 hours')));
truncate intro_claims;
insert into intro_claims select * from public.claim_subscription_trial_emails();
select is((select count(*) from intro_claims),1::bigint,'three-day reminder has a separate durable receipt');
select is((select days_before from app_private.subscription_trial_email_outbox where status='processing'),3,'second reminder is three days before first charge');
select is((select public.finish_subscription_trial_email(outbox_id,lease_token,false,false,null,'provider unavailable') from intro_claims),'pending','transient provider error is retried');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'retry respects its backoff');
update app_private.subscription_trial_email_outbox set next_attempt_at=now() where status='pending';
create temporary table retry_claims as select * from public.claim_subscription_trial_emails();
select is((select outbox_id from retry_claims),(select outbox_id from intro_claims),'retry retains provider idempotency identity');
select isnt((select lease_token from retry_claims),(select lease_token from intro_claims),'retry obtains a fresh lease');
select is((select count(*) from intro_claims c cross join lateral public.prepare_subscription_trial_email(c.outbox_id,c.lease_token)),0::bigint,'stale lease cannot send');
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'expires_at',now()+interval '2 days 23 hours','signed_at',now()+interval '4 minutes','revoked_at',now())));
select is((select count(*) from retry_claims c cross join lateral public.prepare_subscription_trial_email(c.outbox_id,c.lease_token)),0::bigint,'refund after claim suppresses reminder');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'has_access','false','refunded trial loses access');
select is((select public.finish_subscription_trial_email(outbox_id,lease_token,false,true) from retry_claims),'skipped','refunded reminder is not retried');
-- An expired trial can continue only via Apple's verified grace period.
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'expires_at',now()-interval '1 hour','signed_at',now()+interval '5 minutes',
 'status_signed_at',now()+interval '5 minutes','grace_expires_at',now()+interval '2 days',
 'renewal_signed_at',now()+interval '5 minutes','auto_renews',true,'in_billing_retry',true)));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'state','subscribed','billing grace after trial is not represented as free trial');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'trial_ends_at',null,'grace does not fabricate a new free period');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'in_billing_retry','true','billing retry state reaches the app');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'expired trial never sends late renewal reminders');
-- Paid renewal wins over the older trial; old-chain events cannot change owner.
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'transaction_id','3902','is_free_trial',false,'expires_at',now()+interval '30 days','signed_at',now()+interval '6 minutes',
 'renewal_signed_at',now()+interval '6 minutes','auto_renews',true,'in_billing_retry',false,'renews_at',now()+interval '30 days')));
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'state','subscribed','paid renewal replaces introductory trial');
select is(app_private.workloop_access_for('a3900000-0000-4000-8000-000000000001')->>'trial_ends_at',null,'paid renewal does not retain old trial messaging');
select throws_ok($$select public.record_verified_store_subscription(pg_temp.intro_record('{"transaction_id":"3903","user_id":"a3900000-0000-4000-8000-000000000002"}'))$$,'42501','Purchase belongs to another account','trial ownership remains immutable across renewal');
-- A different customer demonstrates successful finish and no inbox deletion replay.
select public.record_verified_store_subscription(pg_temp.intro_record(jsonb_build_object(
 'original_transaction_id','4900','transaction_id','4901','user_id','a3900000-0000-4000-8000-000000000002',
 'renewal_signed_at',now(),'auto_renews',true)));
truncate intro_claims;
insert into intro_claims select * from public.claim_subscription_trial_emails();
select is((select count(*) from intro_claims),1::bigint,'independent account gets its own first reminder');
update app_private.subscription_trial_email_outbox set attempt_count=8
  where id=(select outbox_id from intro_claims);
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'concurrent worker does not claim an active eighth attempt');
select is((select status from app_private.subscription_trial_email_outbox where id=(select outbox_id from intro_claims)),'processing','final allowed attempt keeps its active lease');
select is((select count(*) from intro_claims c cross join lateral public.prepare_subscription_trial_email(c.outbox_id,c.lease_token)),1::bigint,'eighth attempt can still prepare its send');

select throws_ok($$select public.finish_subscription_trial_email(outbox_id,lease_token,true) from intro_claims$$,'22023','Provider message ID required','successful delivery requires provider evidence');
select is((select public.finish_subscription_trial_email(outbox_id,lease_token,true,false,'test-provider-id') from intro_claims),'sent','provider acceptance completes delivery');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'successful delivery never replays');
update app_private.subscription_trial_email_outbox set status='processing',attempt_count=8,
 lease_token=gen_random_uuid(),lease_expires_at=now()-interval '1 second'
 where id=(select outbox_id from intro_claims);
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'expired eighth attempt cannot be retried a ninth time');
select is((select status from app_private.subscription_trial_email_outbox where id=(select outbox_id from intro_claims)),'failed','exhausted attempts become terminal only after lease expiry');

select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select throws_ok($$select public.claim_subscription_trial_emails()$$,'42501','service role required','claim checks service identity in its body');
select set_config('request.jwt.claims','{}',true);
delete from auth.users where id='a3900000-0000-4000-8000-000000000002';
select is((select count(*) from app_private.subscription_trial_email_outbox where user_id='a3900000-0000-4000-8000-000000000002'),0::bigint,'account deletion removes billing email receipts');
select * from finish();
rollback;
