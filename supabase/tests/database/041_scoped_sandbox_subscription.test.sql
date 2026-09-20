begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok(not has_column_privilege('authenticated','app_private.account_access','sandbox_access_until','UPDATE'),'customers cannot grant themselves Sandbox permission');
select ok(not has_column_privilege('anon','app_private.account_access','sandbox_access_until','SELECT'),'anonymous clients cannot inspect tester permissions');
select is((select count(*) from app_private.account_access where sandbox_access_until is not null),0::bigint,'migration grants no existing account Sandbox permission');
update app_private.subscription_config set beta_open=true,enforcement_enabled=false,apple_sales_enabled=false,google_sales_enabled=false;
create temporary table sandbox_original_config as select beta_open,enforcement_enabled,apple_sales_enabled,google_sales_enabled from app_private.subscription_config;
insert into auth.users(id,email,email_confirmed_at,created_at) values
('a4100000-0000-4000-8000-000000000001','review+workloop-iap@example.test',now(),now()),
('a4100000-0000-4000-8000-000000000002','ordinary+workloop-iap@example.test',now(),now()),
('a4100000-0000-4000-8000-000000000003','lifetime-owner@example.test',now(),now()),
('a4100000-0000-4000-8000-000000000004','legacy+workloop-iap@example.test',now(),now());
insert into auth.sessions(id,user_id,created_at,not_after) values
('a4100000-0000-4000-8000-000000000011','a4100000-0000-4000-8000-000000000001',now(),null),
('a4100000-0000-4000-8000-000000000021','a4100000-0000-4000-8000-000000000002',now(),null);
insert into app_private.account_access(user_id,sandbox_access_until) values
('a4100000-0000-4000-8000-000000000001',now()+interval '30 days');
insert into app_private.account_access(user_id,trial_started_at) values
('a4100000-0000-4000-8000-000000000004',now()-interval '2 days');
select throws_ok($q$update app_private.account_access set sandbox_access_until=now()+interval '30 days'
 where user_id='a4100000-0000-4000-8000-000000000003'$q$,'23514',null,'lifetime beta cannot mask a tester purchase journey');
select throws_ok($q$update app_private.account_access set sandbox_access_until=now()+interval '30 days'
 where user_id='a4100000-0000-4000-8000-000000000004'$q$,'23514',null,'legacy free trial cannot mask a tester purchase journey');
select throws_ok($q$update app_private.account_access set sandbox_access_until='infinity'::timestamptz
 where user_id='a4100000-0000-4000-8000-000000000001'$q$,'23514',null,'Sandbox testing permission must have a finite end');
create function pg_temp.qa_access() returns jsonb language sql as $$
 select app_private.workloop_access_for('a4100000-0000-4000-8000-000000000001');
$$;
select is(pg_temp.qa_access()->>'state','trial_available','tester sees real purchase journey before any receipt');
select is(pg_temp.qa_access()->>'has_access','false','tester has no free-beta shortcut while global beta is open');
select is(pg_temp.qa_access()->>'apple_sales_enabled','true','active tester can open Apple checkout while global sales are off');
select is(pg_temp.qa_access()->>'google_sales_enabled','false','Apple tester does not enable unimplemented Google checkout');
select is(pg_temp.qa_access()->>'beta_open','false','effective tester beta flag is closed');
select is(pg_temp.qa_access()->>'enforcement_enabled','true','effective tester access enforcement is enabled');
select is(pg_temp.qa_access()->>'is_sandbox_tester','true','server explicitly describes the testing account');
select is(pg_temp.qa_access()->>'store_environment',null,'permission alone does not invent a purchase environment');
select is(app_private.workloop_access_for('a4100000-0000-4000-8000-000000000002')->>'state','beta','ordinary beta account retains its existing access');
select is(app_private.workloop_access_for('a4100000-0000-4000-8000-000000000002')->>'apple_sales_enabled','false','tester checkout permission cannot enable sales for another account');
select is(app_private.workloop_access_for('a4100000-0000-4000-8000-000000000003')->>'state','beta_lifetime','existing lifetime beta account remains unchanged');
-- The public RPC still checks the real verified session and cannot derive
-- testing permission from attacker-controlled JWT metadata or request flags.
select set_config('request.jwt.claims','{"sub":"a4100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"a4100000-0000-4000-8000-000000000011","aal":"aal1"}',true);
set local role authenticated;
select is(public.get_workloop_access()->>'has_access','false','verified tester RPC still waits for an Apple purchase');
select throws_ok($q$update app_private.account_access set sandbox_access_until=now()+interval '60 days'$q$,'42501',null,'authenticated tester cannot extend its own permission');
reset role;
select set_config('request.jwt.claims','{"sub":"a4100000-0000-4000-8000-000000000002","role":"authenticated","session_id":"a4100000-0000-4000-8000-000000000021","aal":"aal1","sandbox_access_until":"2099-01-01","user_metadata":{"is_sandbox_tester":true}}',true);
set local role authenticated;
select is(public.get_workloop_access()->>'is_sandbox_tester','false','self-assigned metadata cannot create tester status');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

create function pg_temp.qa_record(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
 select jsonb_build_object('platform','apple','environment','Sandbox',
 'user_id','a4100000-0000-4000-8000-000000000001','original_transaction_id','4100','transaction_id','4101',
 'product_id','workloop_monthly','expires_at',now()+interval '5 minutes',
 'purchased_at',now()-interval '1 minute','is_free_trial',true,'signed_at',now(),
 'renewal_signed_at',now(),'auto_renews',true,'renews_at',now()+interval '5 minutes')||extra;
$$;
select public.record_verified_store_subscription(pg_temp.qa_record());
select is(pg_temp.qa_access()->>'state','store_trial','verified Sandbox introductory period uses the real trial state');
select is(pg_temp.qa_access()->>'has_access','true','explicitly allowed tester obtains access from its own verified receipt');
select is(pg_temp.qa_access()->>'store_environment','Sandbox','test entitlement remains labelled Sandbox');
select is((pg_temp.qa_access()->>'paid_until')::timestamptz,now()+interval '5 minutes','Sandbox access uses actual accelerated expiry');
select is((pg_temp.qa_access()->>'trial_ends_at')::timestamptz,now()+interval '5 minutes','trial end remains the exact signed Apple date');
update app_private.subscription_config set billing_reminders_enabled=true;
select is(pg_temp.qa_access()->>'billing_reminders_enabled','false','Sandbox trial UI cannot promise real billing emails');
select is((select count(*) from public.claim_subscription_trial_emails()),0::bigint,'Sandbox trial cannot enter production email delivery');
select is((select count(*) from app_private.store_subscriptions where environment='Production'),0::bigint,'Sandbox access creates no Production ledger transaction');
-- An ordinary account may retain a verified Sandbox receipt for diagnostics,
-- but neither that receipt nor a copied reviewer chain grants it paid access.
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object(
 'user_id','a4100000-0000-4000-8000-000000000002','original_transaction_id','4200','transaction_id','4201')));
select throws_ok($q$select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object(
 'user_id','a4100000-0000-4000-8000-000000000002','transaction_id','4102')))$q$,
 '42501','Purchase belongs to another account','Sandbox renewal ownership cannot cross accounts');
update app_private.subscription_config set beta_open=false,apple_sales_enabled=true,enforcement_enabled=true;
select is(app_private.workloop_access_for('a4100000-0000-4000-8000-000000000002')->>'has_access','false','ordinary account cannot use its Sandbox receipt after beta closes');
select is(app_private.workloop_access_for('a4100000-0000-4000-8000-000000000002')->>'store_environment',null,'ordinary account never selects a Sandbox entitlement');
update app_private.subscription_config set beta_open=true,apple_sales_enabled=false,enforcement_enabled=false;

select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('renewal_signed_at',now()+interval '1 second','auto_renews',false)));
select is(pg_temp.qa_access()->>'has_access','true','cancelling test renewal preserves the current paid/trial period');
select is(pg_temp.qa_access()->>'auto_renews','false','verified Sandbox cancellation is reflected');
select is(pg_temp.qa_access()->>'renews_at',null,'cancelled Sandbox subscription claims no next charge');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('signed_at',now()-interval '1 second')));
select is(pg_temp.qa_access()->>'auto_renews','false','stale restore cannot erase newer cancellation');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('signed_at',now()+interval '2 seconds','revoked_at',now())));
select is(pg_temp.qa_access()->>'has_access','false','refund removes test access even with global enforcement off');
select is(pg_temp.qa_access()->>'state','expired','refund does not fall back to open beta');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('transaction_id','4102','is_free_trial',false,
 'expires_at',now()+interval '10 minutes','signed_at',now()+interval '3 seconds')));
select is(pg_temp.qa_access()->>'state','subscribed','verified Sandbox renewal replaces the refunded older trial period');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('signed_at',now()+interval '4 seconds','revoked_at',now())));
select is(pg_temp.qa_access()->>'has_access','true','later refund of the old test period cannot remove the newer renewal');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('transaction_id','4102','is_free_trial',false,
 'expires_at',now()-interval '1 minute','signed_at',now()+interval '5 seconds')));
select is(pg_temp.qa_access()->>'has_access','false','Sandbox renewal expires on its actual Apple expiry');
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('transaction_id','4102','is_free_trial',false,
 'expires_at',now()-interval '1 minute','signed_at',now()+interval '6 seconds',
 'status_signed_at',now()+interval '6 seconds','grace_expires_at',now()+interval '3 minutes')));
select is(pg_temp.qa_access()->>'has_access','true','independently verified Sandbox grace remains usable');
update app_private.account_access set sandbox_access_until=now()+interval '1 minute'
 where user_id='a4100000-0000-4000-8000-000000000001';
select is((pg_temp.qa_access()->>'paid_until')::timestamptz,now()+interval '1 minute','test permission caps the app/server access expiry');
select is((pg_temp.qa_access()->>'grace_ends_at')::timestamptz,now()+interval '3 minutes','Apple grace metadata remains truthful when test permission ends earlier');
update app_private.account_access set sandbox_access_until=now()-interval '1 second'
 where user_id='a4100000-0000-4000-8000-000000000001';
select is(pg_temp.qa_access()->>'has_access','false','expired permission cannot use still-valid Sandbox grace');
select is(pg_temp.qa_access()->>'state','expired','expired permission stays fail-closed instead of open beta');
select is(pg_temp.qa_access()->>'is_sandbox_tester','true','expired permission retains its dedicated account classification');
select is(pg_temp.qa_access()->>'apple_sales_enabled','false','expired tester permission disables its checkout override');
select is(pg_temp.qa_access()->>'trial_ends_at',null,'revoked tester permission cannot manufacture a new legacy trial');

-- The same authoritative write guard consumes this effective access policy.
create temporary table qa_guard_probe(id integer primary key);
grant insert,select,delete on qa_guard_probe to authenticated;
create trigger qa_guard_probe before insert or update on qa_guard_probe
 for each row execute function app_private.guard_workloop_subscription_write();
select set_config('request.jwt.claims','{"sub":"a4100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"a4100000-0000-4000-8000-000000000011","aal":"aal1"}',true);
set local role authenticated;
select throws_ok($q$insert into qa_guard_probe values(1)$q$,'PT402',null,'revoked test permission cannot bypass the database write guard');
select is(public.get_workloop_access()->>'has_access','false','RPC refresh cannot re-enrol expired tester into free beta');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update app_private.account_access set sandbox_access_until=now()+interval '30 days'
 where user_id='a4100000-0000-4000-8000-000000000001';
select is(pg_temp.qa_access()->>'has_access','true','operator can renew finite permission without fabricating another receipt');
-- Production always wins, including when Sandbox would last longer.
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('transaction_id','4103','is_free_trial',false,
 'expires_at',now()+interval '20 days','signed_at',now()+interval '7 seconds')));
select public.record_verified_store_subscription(pg_temp.qa_record(jsonb_build_object('environment','Production','original_transaction_id','5100','transaction_id','5101',
 'is_free_trial',false,'expires_at',now()+interval '2 days')));
select is(pg_temp.qa_access()->>'store_environment','Production','valid Production entitlement takes precedence over a longer Sandbox one');
select is((pg_temp.qa_access()->>'paid_until')::timestamptz,now()+interval '2 days','selected Production period is not extended by Sandbox');
select is(pg_temp.qa_access()->>'billing_reminders_enabled','true','a genuine Production subscription retains its real billing capability');
update app_private.account_access set sandbox_access_until=now()-interval '1 second'
 where user_id='a4100000-0000-4000-8000-000000000001';
select is(pg_temp.qa_access()->>'has_access','true','expiring tester permission cannot revoke a genuine Production entitlement');
select is(pg_temp.qa_access()->>'store_environment','Production','Production remains authoritative after tester permission expires');
select is((select count(*) from app_private.store_subscriptions where environment='Production'),1::bigint,'only the explicit genuine Production input entered the Production ledger');
select is((select count(*) from app_private.subscription_trial_email_outbox),0::bigint,'test lifecycle never queued a production billing email');
select results_eq('select beta_open,enforcement_enabled,apple_sales_enabled,google_sales_enabled from app_private.subscription_config',
 'select * from sandbox_original_config','scoped testing does not alter global beta/enforcement/store flags');
select * from finish();
rollback;
