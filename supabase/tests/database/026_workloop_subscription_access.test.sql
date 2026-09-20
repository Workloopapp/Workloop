begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(not has_table_privilege('authenticated','app_private.store_subscription_owners','INSERT'),'app cannot assign purchase-chain ownership');
select ok(not has_table_privilege('authenticated','app_private.store_subscriptions','UPDATE'),'app cannot edit verified transactions');
select ok(not has_function_privilege('anon','public.get_workloop_access()','EXECUTE'),'anonymous access checks denied');
select ok(not has_function_privilege('authenticated','public.record_verified_store_subscription(jsonb)','EXECUTE'),'only service verification can record transactions');
select ok((select relrowsecurity from pg_class where oid='app_private.store_subscription_owners'::regclass),'purchase ownership has RLS');

update app_private.subscription_config set beta_open=false,apple_sales_enabled=true,enforcement_enabled=true;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2600000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','subscription-a@example.test','',now(),now(),now()),
('a2600000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','subscription-b@example.test','',now(),now(),now()),
('a2600000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','subscription-unverified@example.test','',null,now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('a2600000-0000-4000-8000-000000000011','a2600000-0000-4000-8000-000000000001',now(),now(),null),
('a2600000-0000-4000-8000-000000000012','a2600000-0000-4000-8000-000000000001',now(),now(),now()-interval '1 second'),
('a2600000-0000-4000-8000-000000000021','a2600000-0000-4000-8000-000000000002',now(),now(),null),
('a2600000-0000-4000-8000-000000000031','a2600000-0000-4000-8000-000000000003',now(),now(),null);

create function pg_temp.subscription_claim(session_id text, aal text default 'aal1', user_id text default 'a2600000-0000-4000-8000-000000000001') returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','session_id',session_id,'aal',aal)::text,true);
$$;
set local role authenticated;
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000011');
select is(public.get_workloop_access()->>'state','trial_available','first public use requires the Apple trial or subscription');
select is(public.get_workloop_access()->>'has_access','false','no access is granted before purchase authorisation');
select is(public.get_workloop_access()->>'trial_ends_at',null,'an access check cannot start a no-card trial');
select is(public.get_workloop_access()->>'trial_ends_at',null,'repeated checks cannot manufacture a trial');
select pg_temp.subscription_claim(null);
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','missing session denied');
select pg_temp.subscription_claim('malformed');
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','malformed session denied safely');
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000099');
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','revoked/unknown session denied');
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000012');
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','session not_after expiry checked even with an otherwise valid JWT');
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000021');
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','another account session cannot be reused');
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000031','aal1','a2600000-0000-4000-8000-000000000003');
select throws_ok($$select public.get_workloop_access()$$,'42501','A verified account is required','unverified account denied');
reset role;
-- Simulate a session expiring after the initial check while the account upsert
-- completes. The exception must roll the new account row back as well.
create function pg_temp.expire_subscription_session() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.user_id='a2600000-0000-4000-8000-000000000002' then
    update auth.sessions set not_after=clock_timestamp()-interval '1 second'
      where id='a2600000-0000-4000-8000-000000000021';
  end if;
  return new;
end; $$;
create trigger subscription_session_expiry_test after insert on app_private.account_access
 for each row execute function pg_temp.expire_subscription_session();
set local role authenticated;
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000021','aal1','a2600000-0000-4000-8000-000000000002');
select throws_ok($$select public.get_workloop_access()$$,'42501','Active session required','session expiry during access upsert is rechecked');
reset role;
select is((select count(*) from app_private.account_access where user_id='a2600000-0000-4000-8000-000000000002'),0::bigint,'failed in-transaction recheck does not create an access row');
drop trigger subscription_session_expiry_test on app_private.account_access;
insert into auth.mfa_factors(id,user_id,factor_type,status,secret) values
('a2600000-0000-4000-8000-000000000041','a2600000-0000-4000-8000-000000000001','totp','verified','sample-only');
set local role authenticated;
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000011');
select throws_ok($$select public.get_workloop_access()$$,'42501','MFA verification required','verified factor requires AAL2');
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000011','aal2');
select lives_ok($$select public.get_workloop_access()$$,'valid AAL2 session accepted');
reset role;
update app_private.account_access set trial_started_at=now()-interval '31 days' where user_id='a2600000-0000-4000-8000-000000000001';
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','expired trial has no access');

create function pg_temp.subscription_record(
  tx text, expires timestamptz, signed timestamptz,
  revoked timestamptz default null, environment text default 'Production',
  original text default '100', owner_id text default 'a2600000-0000-4000-8000-000000000001',
  grace timestamptz default null,status_signed timestamptz default null,upgraded boolean default false
) returns jsonb language sql as $$
  select jsonb_build_object('platform','apple','environment',environment,'original_transaction_id',original,
    'user_id',owner_id,'product_id','workloop_monthly','transaction_id',tx,'expires_at',expires,
    'signed_at',signed,'revoked_at',revoked,'grace_expires_at',grace,'status_signed_at',status_signed,'is_upgraded',upgraded);
$$;
set local role service_role;
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('101',now()-interval '1 day',now()-interval '32 days'))$$,'record old paid period');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()-interval '1 day'))$$,'record current renewal in the same chain');
select is((select count(*) from app_private.store_subscriptions where original_transaction_id='100'),2::bigint,'both renewal transactions retained separately');
select is((select count(*) from app_private.store_subscription_owners where original_transaction_id='100'),1::bigint,'one immutable owner binding for chain');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'state','subscribed','current verified renewal grants access');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('101',now()-interval '1 day',now(),now()))$$,'later refund of the old period is recorded');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'state','subscribed','old-period refund cannot revoke current renewal');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now(),now()))$$,'current-period refund recorded');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','current-period refund removes paid access');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()-interval '1 minute'))$$,'stale restored receipt accepted idempotently');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','stale receipt does not erase a newer refund');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()))$$,'same signed instant replay is idempotent');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','equal-time payload does not overwrite refund');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()-interval '1 minute',null,'Production','100','a2600000-0000-4000-8000-000000000001',null,now()+interval '1 minute'))$$,'new notification may carry an older transaction snapshot');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','newer outer notification cannot erase a newer inner refund');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()+interval '1 second'))$$,'newer refund reversal restores the actual transaction');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'state','subscribed','verified reversal can restore access');
select throws_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('103',now()+interval '60 days',now(),null,'Production','100','a2600000-0000-4000-8000-000000000002'))$$,'42501','Purchase belongs to another account','another account cannot claim a new renewal of the same chain');
select throws_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '60 days',now(),null,'Production','999'))$$,'42501','Transaction belongs to another subscription','transaction cannot move to another chain');
select is((select count(*) from app_private.store_subscription_owners where original_transaction_id='999'),0::bigint,'failed chain reassignment rolls back its new binding');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('102',now()+interval '29 days',now()+interval '2 seconds',null,'Production','100','a2600000-0000-4000-8000-000000000001',null,null,true))$$,'upgrade supersedes its old product period');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','upgraded period alone cannot grant stale entitlement');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('201',now()+interval '1 year',now(),null,'Sandbox','200'))$$,'sandbox verification can be retained separately');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','sandbox never grants production access');

select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('301',now()-interval '1 day',now(),null,'Production','300','a2600000-0000-4000-8000-000000000001',now()+interval '6 days',now()))$$,'verified grace period recorded');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'state','subscribed','verified grace allows access');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('301',now()-interval '1 day',now()+interval '2 seconds',null,'Production','300'))$$,'fresh transaction restore without renewal data is allowed');
select is((select grace_expires_at from app_private.store_subscriptions where transaction_id='301'),now()+interval '6 days','restore cannot erase independently verified grace period');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('301',now()-interval '1 day',now()+interval '1 second',null,'Production','300','a2600000-0000-4000-8000-000000000001',null,now()+interval '1 second'))$$,'grace-end notification applies even after a newer transaction-only restore');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','newer renewal-status snapshot clears grace');
select lives_ok($$select public.record_verified_store_subscription(pg_temp.subscription_record('301',now()-interval '1 day',now()+interval '3 seconds',null,'Production','300','a2600000-0000-4000-8000-000000000001',now()+interval '6 days',now()))$$,'older grace status is ignored independently of newer transaction signature');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000001')->>'has_access','false','old grace status cannot resurrect entitlement');
reset role;

-- Exercise the real write-trigger body on an isolated temporary business row.
-- Full local Supabase runs also attach it to the real tables via the migration.
create temporary table subscription_guard_probe(id integer primary key,note text);
insert into subscription_guard_probe values(1,'existing data');
grant select,insert,update,delete on subscription_guard_probe to authenticated,service_role;
create trigger subscription_guard_probe before insert or update on subscription_guard_probe
 for each row execute function app_private.guard_workloop_subscription_write();
set local role authenticated;
select pg_temp.subscription_claim('a2600000-0000-4000-8000-000000000011','aal2');
select throws_ok($$insert into subscription_guard_probe values(2,'new record')$$,'PT402','Your Workloop trial has ended. Choose a plan to make changes.','expired accounts cannot create business records');
select throws_ok($$update subscription_guard_probe set note='changed' where id=1$$,'PT402','Your Workloop trial has ended. Choose a plan to make changes.','expired accounts cannot update business records');
select is((select note from subscription_guard_probe where id=1),'existing data','existing records remain readable/exportable');
select lives_ok($$delete from subscription_guard_probe where id=1$$,'expiry does not block deletion');
reset role;
update app_private.subscription_config set enforcement_enabled=false;
set local role authenticated;
select lives_ok($$insert into subscription_guard_probe values(2,'non-enforced beta')$$,'disabled enforcement preserves the beta workflow');
reset role;
update app_private.subscription_config set enforcement_enabled=true;
select set_config('request.jwt.claims','{}',true);
set local role service_role;
select lives_ok($$insert into subscription_guard_probe values(3,'provider reconciliation')$$,'trusted provider reconciliation remains possible');
reset role;

-- Existing beta ownership survives closure; accounts joining after closure do not.
update app_private.subscription_config set beta_open=true;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2600000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','subscription-beta@example.test','',now(),now(),now());
update app_private.subscription_config set beta_open=false;
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000004')->>'state','beta_lifetime','verified beta entry retains lifetime after beta closes');
select is(app_private.workloop_access_for('a2600000-0000-4000-8000-000000000002')->>'has_access','false','an untouched public account does not inherit lifetime or someone else payment');
delete from auth.users where id='a2600000-0000-4000-8000-000000000001';
select is((select count(*) from app_private.store_subscription_owners where user_id='a2600000-0000-4000-8000-000000000001'),0::bigint,'account deletion removes private owner bindings');
select is((select count(*) from app_private.store_subscriptions where user_id='a2600000-0000-4000-8000-000000000001'),0::bigint,'account deletion removes private purchase snapshots');
select * from finish();
rollback;
