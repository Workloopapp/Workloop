begin;
set local search_path=public,extensions;
select plan(72);
select ok(not has_function_privilege('anon','public.get_booking_sms_consent(uuid)','EXECUTE'),'anonymous users cannot read customer consent');
select ok(not has_function_privilege('authenticated','public.claim_booking_reminder_sms(integer)','EXECUTE'),'app users cannot claim SMS');
select ok(not has_table_privilege('authenticated','app_private.booking_sms_outbox','SELECT'),'private queue cannot be read by app users');
select ok((select relrowsecurity from pg_class where oid='app_private.booking_sms_consent'::regclass),'consent table uses RLS');
select is(app_private.booking_sms_phone('+44 7700 900123'),'+447700900123','formatting is removed from international UK mobile');
select is(app_private.booking_sms_phone('07700900123'),null,'no country is guessed from local format');
select is(app_private.booking_sms_phone('+442079460123'),null,'landline is not a UK mobile');
select is(app_private.booking_sms_phone('+447012345678'),null,'personal number range is excluded');
select is(app_private.booking_sms_phone('+14155550123'),null,'unapproved international destination is excluded');

insert into auth.users(id,email,email_confirmed_at) values
 ('c1000000-0000-4000-8000-000000000001','sms-owner@example.test',now()),
 ('c1000000-0000-4000-8000-000000000002','sms-other@example.test',now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('c1000000-0000-4000-8000-000000000101','c1000000-0000-4000-8000-000000000001',now(),now()),
('c1000000-0000-4000-8000-000000000102','c1000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
 ('c2000000-0000-4000-8000-000000000001','Valet Studio'),
 ('c2000000-0000-4000-8000-000000000002','Other Business');
insert into public.workspace_members(workspace_id,user_id) values
 ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001'),
 ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id) values('c2000000-0000-4000-8000-000000000001') on conflict do nothing;
select is((select cardinality(customer_sms_reminder_minutes) from public.workspace_settings where workspace_id='c2000000-0000-4000-8000-000000000001'),0,'new and existing businesses start with SMS off');
select throws_ok($$update public.workspace_settings set customer_sms_reminder_minutes=array[120] where workspace_id='c2000000-0000-4000-8000-000000000001'$$,'23514',null,'unsupported reminder interval rejected');
update public.workspace_settings set customer_sms_reminder_minutes=array[1440,60],timezone='Europe/London',customer_contact_phone='+44 7700 900999' where workspace_id='c2000000-0000-4000-8000-000000000001';
insert into public.contacts(id,workspace_id,name,phone) values
 ('c3000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','SMS Customer','+44 7700 900123'),
 ('c3000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000002','Other Customer','+447700900456');
insert into public.appointments(id,workspace_id,contact_id,title,start_time,end_time,status,created_at) values
 ('c4000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','One hour',now()+interval '55 minutes',now()+interval '115 minutes','scheduled',now()-interval '2 days'),
 ('c4000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','One day',now()+interval '23 hours 55 minutes',now()+interval '25 hours','scheduled',now()-interval '2 days'),
 ('c4000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','Already complete',now()+interval '55 minutes',now()+interval '115 minutes','completed',now()-interval '2 days'),
 ('c4000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','Cancelled',now()+interval '55 minutes',now()+interval '115 minutes','cancelled',now()-interval '2 days'),
 ('c4000000-0000-4000-8000-000000000005','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','Too late',now()+interval '30 minutes',now()+interval '90 minutes','scheduled',now()-interval '2 days'),
 ('c4000000-0000-4000-8000-000000000006','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','Just created',now()+interval '55 minutes',now()+interval '115 minutes','scheduled',now());
select is((select count(*)::integer from public.claim_booking_reminder_sms(10)),0,'business opt-in and saved phone alone are not customer consent');
select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"c1000000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','consent starts false');
select throws_ok($$select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900999')$$,'22023',null,'stale phone cannot receive permission');
select throws_ok($$select public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000002')$$,'42501',null,'another business consent cannot be read');
select is(public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123')->>'consented','true','explicit customer permission is recorded');
reset role;

set local role service_role;
create temp table sms_claims as select * from public.claim_booking_reminder_sms(10);
reset role;
select is((select count(*)::integer from sms_claims),2,'only due 24h/1h eligible real bookings claimed; no backlog/completed/cancelled/new sends');
select is((select count(*)::integer from public.claim_booking_reminder_sms(10)),0,'active leases prevent duplicate claims');
set local role service_role;
create temp table sms_dispatch as select public.begin_booking_reminder_sms(q.id,c.lease_token) as value
  from sms_claims c join app_private.booking_sms_outbox q on q.id=c.outbox_id
  where q.appointment_id='c4000000-0000-4000-8000-000000000001';
reset role;
select is((select value->'payload'->>'timezone' from sms_dispatch),'Europe/London','dispatch reads the real business timezone');
select is((select value->>'recipient_phone' from sms_dispatch),'+447700900123','dispatch uses current consented mobile');
select is((select public.begin_booking_reminder_sms(q.id,c.lease_token) from sms_claims c join app_private.booking_sms_outbox q on q.id=c.outbox_id where q.appointment_id='c4000000-0000-4000-8000-000000000001'),null,'a second dispatch reservation cannot submit twice');
select public.finish_booking_reminder_sms((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000001','accepted',null) from sms_dispatch;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000001'),'accepted','acceptance is not delivery');
select public.record_booking_sms_status((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000001','delivered',null) from sms_dispatch;
select public.record_booking_sms_status((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000001','queued',null) from sms_dispatch;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000001'),'delivered','late callbacks cannot downgrade delivery');
update public.appointments set start_time=start_time+interval '2 hours',end_time=end_time+interval '2 hours' where id='c4000000-0000-4000-8000-000000000002';
select is((select public.begin_booking_reminder_sms(q.id,c.lease_token) from sms_claims c join app_private.booking_sms_outbox q on q.id=c.outbox_id where q.appointment_id='c4000000-0000-4000-8000-000000000002'),null,'rescheduled booking rejected immediately before dispatch');
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000002'),'cancelled','stale queued reminder is closed');

-- Reuse explicit test fixtures for independent eligibility and quota checks.
update public.appointments set created_at=now()-interval '2 days' where id='c4000000-0000-4000-8000-000000000006';
create temp table sms_later as select * from public.claim_booking_reminder_sms(10);
update public.workspace_settings set customer_sms_reminder_minutes=array[]::integer[] where workspace_id='c2000000-0000-4000-8000-000000000001';
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_later),null,'turning off SMS after claim blocks dispatch');
update public.workspace_settings set customer_sms_reminder_minutes=array[60] where workspace_id='c2000000-0000-4000-8000-000000000001';
update public.appointments set start_time=now()+interval '55 minutes',end_time=now()+interval '115 minutes' where id='c4000000-0000-4000-8000-000000000005';
truncate sms_later;
insert into sms_later select * from public.claim_booking_reminder_sms(10);
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token,1,100,6) from sms_later),null,'global rolling daily cap blocks an additional text');
select is((select last_error from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000005'),'daily_message_limit','quota stop is explicit');
select public.record_booking_sms_opt_out('+447700900123',true);
select is((select count(*)::integer from app_private.booking_sms_consent where phone='+447700900123' and revoked_at is null),0,'provider STOP revokes existing business permissions');
set local role authenticated;
select throws_ok($$select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123')$$,'42501',null,'business cannot override provider STOP');
reset role;
select public.record_booking_sms_opt_out('+447700900123',false);
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','provider START cannot grant consent to businesses');
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123');
update public.contacts set phone='+44 (7700) 900-123' where id='c3000000-0000-4000-8000-000000000001';
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','true','formatting-only phone changes preserve explicit permission');
insert into public.contacts(id,workspace_id,name,phone) values('c3000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000001','Separate person','+447700900123');
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000003')->>'consented','false','another customer with the same mobile cannot inherit permission');
update public.contacts set phone='+447700900888' where id='c3000000-0000-4000-8000-000000000001';
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','changing mobile does not transfer consent');
update public.contacts set phone='+447700900123' where id='c3000000-0000-4000-8000-000000000001';
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','restoring an older number cannot restore consent');
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123');
-- A provider rejection is also a STOP signal if the inbound callback was lost.
update app_private.booking_sms_outbox set status='sending' where appointment_id='c4000000-0000-4000-8000-000000000001';
select public.finish_booking_reminder_sms((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,null,'rejected','provider_21610') from sms_dispatch;
select is((select count(*)::integer from app_private.booking_sms_suppression where phone='+447700900123'),1,'provider opt-out rejection records suppression');
select public.record_booking_sms_opt_out('+447700900123',false);
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','21610 then START does not silently reactivate old permissions');
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123');
update app_private.booking_sms_outbox set status='uncertain' where appointment_id='c4000000-0000-4000-8000-000000000001';
select public.record_booking_sms_status((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000001','undelivered','provider_21610') from sms_dispatch;
select public.record_booking_sms_opt_out('+447700900123',false);
select is(public.get_booking_sms_consent('c3000000-0000-4000-8000-000000000001')->>'consented','false','delivery opt-out failure also revokes permissions before START');
select throws_ok($$insert into app_private.booking_sms_consent(contact_id,workspace_id,phone) values('c3000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000001','not-a-phone')$$,'23514',null,'invalid mobile cannot enter consent table');
select ok(not has_function_privilege('authenticated','app_private.revoke_booking_sms_on_contact_phone_change()','EXECUTE'),'phone-change trigger cannot be invoked directly by app users');
-- Separate new start times keep the original delivery fixtures intact while
-- exercising crashes, retries and each cost boundary through the real queue.
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000001',true,'+447700900123');
insert into public.appointments(id,workspace_id,contact_id,title,start_time,end_time,status,created_at)
select ('c4000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','Queue reliability fixture',now()+interval '55 minutes',now()+interval '115 minutes','scheduled',now()-interval '2 days'
from generate_series(10,15) n;
create temp table sms_reliability_claims as select * from public.claim_booking_reminder_sms(10);
create temp table sms_reliability as select q.appointment_id,c.* from sms_reliability_claims c join app_private.booking_sms_outbox q on q.id=c.outbox_id;
select is((select count(*)::integer from sms_reliability),6,'all six reliability fixtures received independent leases');
create temp table sms_crash as select public.begin_booking_reminder_sms(outbox_id,lease_token) as value from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000010';
update app_private.booking_sms_outbox set dispatched_at=now()-interval '3 minutes' where appointment_id='c4000000-0000-4000-8000-000000000010';
select is((select count(*)::integer from public.claim_booking_reminder_sms(10)),0,'a dispatched crash is never reclaimed or submitted twice');
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000010'),'uncertain','crash after dispatch stays visibly uncertain');
select public.record_booking_sms_status((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000010','delivered',null) from sms_crash;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000010'),'delivered','late authenticated delivery resolves uncertainty');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token,1000,1,6) from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000011'),null,'workspace daily cap blocks more messages');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token,1000,100,1) from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000012'),null,'recipient daily cap blocks more messages across bookings');
create temp table sms_retry as select public.begin_booking_reminder_sms(outbox_id,lease_token) as value from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000013';
select public.finish_booking_reminder_sms((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,null,'retry','provider_http_429') from sms_retry;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000013'),'pending','definite provider rate rejection retries within the expiry window');
select ok((select due_at>now() from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000013'),'retry has backoff instead of an immediate loop');
update app_private.booking_sms_outbox set status='sending',attempt_count=3 where appointment_id='c4000000-0000-4000-8000-000000000013';
select public.finish_booking_reminder_sms((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,null,'retry','provider_http_429') from sms_retry;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000013'),'failed','rate retries stop after three attempts');
update public.appointments set status='cancelled' where id='c4000000-0000-4000-8000-000000000014';
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000014'),null,'booking cancelled after claim cannot dispatch');
update public.contacts set phone='+447700900888' where id='c3000000-0000-4000-8000-000000000001';
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000015'),'cancelled','contact phone trigger closes an outstanding lease immediately');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_reliability where appointment_id='c4000000-0000-4000-8000-000000000015'),null,'old phone lease cannot dispatch after number change');


-- Cost reservations survive deletions; no customer can reset limits by removing
-- sent bookings, or by recreating their workspace during the same rolling day.
select ok((select relrowsecurity from pg_class where oid='app_private.booking_sms_dispatch_usage'::regclass),'short-lived budget evidence uses RLS');
select ok(not has_table_privilege('authenticated','app_private.booking_sms_dispatch_usage','SELECT'),'app cannot read recipient budget hashes');
select ok((select bool_and(octet_length(recipient_hash)=32) from app_private.booking_sms_dispatch_usage),'usage records contain SHA-256 digests rather than raw numbers');
create temp table sms_usage_before as select count(*)::integer as total from app_private.booking_sms_dispatch_usage;
delete from public.workspaces where id='c2000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.booking_sms_dispatch_usage),(select total from sms_usage_before),'workspace deletion cannot erase rolling cost reservations');
select is((select count(*)::integer from app_private.booking_sms_outbox where workspace_id='c2000000-0000-4000-8000-000000000001'),0,'deletion still removes all detailed booking outbox records');
select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"c1000000-0000-4000-8000-000000000102"}',true);
update public.contacts set phone='+447700900123' where id='c3000000-0000-4000-8000-000000000002';
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000002',true,'+447700900123');
insert into public.workspace_settings(workspace_id) values('c2000000-0000-4000-8000-000000000002') on conflict do nothing;
update public.workspace_settings set customer_sms_reminder_minutes=array[60] where workspace_id='c2000000-0000-4000-8000-000000000002';
insert into public.appointments(id,workspace_id,contact_id,title,start_time,end_time,status,created_at)
select ('c4000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'c2000000-0000-4000-8000-000000000002','c3000000-0000-4000-8000-000000000002','Adversarial queue fixture',now()+interval '55 minutes',now()+interval '115 minutes','scheduled',now()-interval '2 days'
from generate_series(30,34) n;
create temp table sms_adversarial_claims as select * from public.claim_booking_reminder_sms(10);
create temp table sms_adversarial as select q.appointment_id,c.* from sms_adversarial_claims c join app_private.booking_sms_outbox q on q.id=c.outbox_id;
select is((select count(*)::integer from sms_adversarial),5,'adversarial fixtures have real current leases');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token,1,100,6) from sms_adversarial where appointment_id='c4000000-0000-4000-8000-000000000030'),null,'deleting past bookings does not reset global cap');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token,1000,100,1) from sms_adversarial where appointment_id='c4000000-0000-4000-8000-000000000031'),null,'recipient cap survives deletion and applies across businesses');
delete from public.appointments where id='c4000000-0000-4000-8000-000000000032';
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_adversarial where appointment_id='c4000000-0000-4000-8000-000000000032'),null,'deleted booking cannot dispatch from a previously claimed lease');
select lives_ok($$select public.record_booking_sms_status('c5000000-0000-4000-8000-000000000032','c6000000-0000-4000-8000-000000000032','SM00000000000000000000000000000032','delivered',null)$$,'callback for a deleted outbox is harmless');
update app_private.booking_sms_outbox set lease_expires_at=now()-interval '1 second' where appointment_id='c4000000-0000-4000-8000-000000000033';
create temp table sms_reclaimed as select * from public.claim_booking_reminder_sms(10);
select is((select count(*)::integer from sms_reclaimed),1,'only an expired pre-dispatch lease can be reclaimed');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_adversarial where appointment_id='c4000000-0000-4000-8000-000000000033'),null,'worker holding an old lease cannot dispatch after another claim');
create temp table sms_early_callback as select public.begin_booking_reminder_sms(outbox_id,lease_token) as value from sms_reclaimed;
select ok((select value is not null from sms_early_callback),'current reclaimed lease can reserve exactly one dispatch');
select public.record_booking_sms_status((value->>'outbox_id')::uuid,'c6000000-0000-4000-8000-000000000099','SM00000000000000000000000000000033','delivered',null) from sms_early_callback;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000033'),'sending','callback from a different dispatch token cannot mutate current attempt');
select public.record_booking_sms_status((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000033','delivered',null) from sms_early_callback;
select public.finish_booking_reminder_sms((value->>'outbox_id')::uuid,(value->>'dispatch_token')::uuid,'SM00000000000000000000000000000033','accepted',null) from sms_early_callback;
select is((select status from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000033'),'delivered','callback arriving before worker completion is not downgraded');
select public.set_booking_sms_consent('c3000000-0000-4000-8000-000000000002',false,'+447700900123');
select is((select public.begin_booking_reminder_sms(outbox_id,lease_token) from sms_adversarial where appointment_id='c4000000-0000-4000-8000-000000000034'),null,'owner removing customer permission stops a previously claimed text');
select ok(exists(select 1 from cron.job where jobname='workloop-sms-retention' and schedule='*/15 * * * *'),'usage cleanup is scheduled independently of enabled provider sends');


insert into app_private.booking_sms_dispatch_usage(id,workspace_id,recipient_hash,reserved_at) values
 ('c7000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000002',decode(repeat('ff',32),'hex'),clock_timestamp()-interval '26 hours'),
 ('c7000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000002',decode(repeat('ff',32),'hex'),clock_timestamp());
update app_private.booking_sms_outbox set created_at=now()-interval '91 days' where appointment_id='c4000000-0000-4000-8000-000000000030';
do $$declare cleanup text; begin select command into cleanup from cron.job where jobname='workloop-sms-retention'; execute cleanup; end$$;
select is((select count(*)::integer from app_private.booking_sms_dispatch_usage where id='c7000000-0000-4000-8000-000000000001'),0,'scheduled cleanup removes expired budget evidence without sending');
select is((select count(*)::integer from app_private.booking_sms_dispatch_usage where id='c7000000-0000-4000-8000-000000000002'),1,'scheduled cleanup preserves current rolling-limit evidence');
select is((select count(*)::integer from app_private.booking_sms_outbox where appointment_id='c4000000-0000-4000-8000-000000000030'),0,'90-day outbox cleanup also works while provider sending is disabled');

select * from finish();
rollback;
