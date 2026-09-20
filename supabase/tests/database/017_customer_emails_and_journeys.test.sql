begin;
set local search_path=public,extensions;
select plan(43);
-- Match hosted Auth permissions rather than a permissive local bootstrap.
revoke all on auth.users from service_role;
select ok(not has_function_privilege('authenticated','app_private.claim_learning_emails(integer)','EXECUTE'),'users cannot call elevated campaign worker');
select ok(not has_function_privilege('anon','app_private.claim_booking_reminder_emails(integer)','EXECUTE'),'anonymous cannot call elevated reminder worker');
select ok(not has_table_privilege('authenticated','app_private.booking_reminder_outbox','SELECT'),'reminder queue is private');
select ok(not has_function_privilege('anon','public.claim_booking_reminder_emails(integer)','EXECUTE'),'anonymous cannot claim reminders');
select ok(not has_function_privilege('authenticated','public.enqueue_account_email_journeys()','EXECUTE'),'users cannot enqueue campaigns');
select is((select relrowsecurity from pg_class where oid='app_private.booking_reminder_preferences'::regclass),true,'customer preferences have RLS');
set local role service_role;
select lives_ok($$select public.claim_booking_reminder_emails(1)$$,'worker claims reminders without direct Auth access');
select lives_ok($$select public.enqueue_account_email_journeys()$$,'worker enqueues journeys without direct Auth access');
select lives_ok($$select public.claim_learning_emails(1)$$,'worker claims tips without direct Auth access');
select lives_ok($$select public.learning_email_still_allowed('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000')$$,'worker rechecks eligibility without direct Auth access');
reset role;
insert into auth.users(id,email,created_at,updated_at,email_confirmed_at,raw_user_meta_data) values
('98000000-0000-4000-8000-000000000001','email-owner@example.test',now(),now(),now(),'{"workloop_email_notice":"workloop-account-emails-2026-09-v1","workloop_email_updates":true}'),
('98000000-0000-4000-8000-000000000002','email-optout@example.test',now(),now(),now(),'{"workloop_email_notice":"workloop-account-emails-2026-09-v1","workloop_email_updates":false}'),
('98000000-0000-4000-8000-000000000003','email-legacy@example.test',now()-interval '60 days',now(),now(),'{}');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('98000000-0000-4000-8000-000000000101','98000000-0000-4000-8000-000000000001',now(),now());
select is((select status from app_private.learning_contacts where email='email-owner@example.test'),'active','new notified signup enrolled automatically');
select is((select status from app_private.learning_contacts where email='email-optout@example.test'),'unsubscribed','signup opt-out honoured');
select is((select count(*)::integer from app_private.learning_contacts where email='email-legacy@example.test'),0,'legacy users not retroactively enrolled');
select is((select count(*)::integer from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id where c.email='email-owner@example.test'),9,'nine onboarding tips scheduled');
select is((select count(*)::integer from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id where c.email='email-optout@example.test'),0,'no marketing queued for opt-out');
update auth.users set email_confirmed_at=now() where id='98000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.learning_email_outbox q join app_private.learning_contacts c on c.id=q.contact_id where c.email='email-owner@example.test'),9,'verification replay does not duplicate');
insert into public.workspaces(id,name) values('99000000-0000-4000-8000-000000000001','Reminder Business');
insert into public.workspace_members(workspace_id,user_id) values('99000000-0000-4000-8000-000000000001','98000000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id) values('99000000-0000-4000-8000-000000000001');
select is((select customer_reminder_minutes from public.workspace_settings where workspace_id='99000000-0000-4000-8000-000000000001'),array[1440,60],'defaults are one day and one hour');
insert into public.contacts(id,workspace_id,name,email) values('99100000-0000-4000-8000-000000000001','99000000-0000-4000-8000-000000000001','Customer','wrong-phone-match@example.test');
insert into public.appointments(id,workspace_id,contact_id,title,start_time,end_time,created_at) values
('99200000-0000-4000-8000-000000000001','99000000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001','Test booking',now()+interval '59 minutes',now()+interval '2 hours',now()-interval '2 days');
insert into app_private.booking_email_recipient values('99200000-0000-4000-8000-000000000001','99000000-0000-4000-8000-000000000001','correct-request@example.test','Request Customer');
select is(public.enqueue_booking_reminder_emails(),1,'one due reminder queued');
select is(public.enqueue_booking_reminder_emails(),0,'repeated cron does not duplicate');
create temp table reminder_claim as select * from public.claim_booking_reminder_emails(5);
select is((select count(*)::integer from reminder_claim),1,'claim acquired');
select is((select recipient_email from reminder_claim),'correct-request@example.test','authoritative request recipient wins phone match');
select is((select reply_email from reminder_claim),'email-owner@example.test','replies go to verified business owner');
select is((select count(*)::integer from public.claim_booking_reminder_emails(5)),0,'active lease prevents duplicate delivery');
select ok((select public.booking_reminder_still_allowed(outbox_id,lease_token) from reminder_claim),'scheduled booking is allowed');
update public.appointments set status='cancelled' where id='99200000-0000-4000-8000-000000000001';
select ok(not (select public.booking_reminder_still_allowed(outbox_id,lease_token) from reminder_claim),'cancelled booking blocked before send');
update public.appointments set status='scheduled',start_time=start_time+interval '1 day' where id='99200000-0000-4000-8000-000000000001';
select ok(not (select public.booking_reminder_still_allowed(outbox_id,lease_token) from reminder_claim),'reschedule blocks old reminder');
update public.appointments set start_time=start_time-interval '1 day' where id='99200000-0000-4000-8000-000000000001';
select public.stop_booking_reminders(unsubscribe_token) from reminder_claim;
select ok(not (select public.booking_reminder_still_allowed(outbox_id,lease_token) from reminder_claim),'recipient stop takes effect on in-flight claim');
select is((select status from public.appointments where id='99200000-0000-4000-8000-000000000001'),'scheduled','unsubscribe does not cancel booking');
select is((select status from app_private.learning_contacts where email='email-owner@example.test'),'active','customer reminder stop does not change owner marketing');
update app_private.learning_email_outbox set due_at=now()-interval '1 minute';
create temp table learning_claim as select * from public.claim_learning_emails(5);
select is((select count(*)::integer from learning_claim),1,'one welcome step per user claimed');
select is((select step from learning_claim),10,'account welcome starts at correct template');
select public.stop_learning_series(unsubscribe_token) from learning_claim;
select ok(not (select public.learning_email_still_allowed(outbox_id,lease_token) from learning_claim),'unsubscribe blocks leased marketing');
select is((select count(*)::integer from public.claim_learning_emails(5)),0,'no marketing after unsubscribe');
-- An automatic signup retry must not reset an unsubscribe.
select app_private.start_account_email_journey('98000000-0000-4000-8000-000000000001',true,'customer_soft_opt_in',now());
select is((select status from app_private.learning_contacts where email='email-owner@example.test'),'unsubscribed','automatic re-enrolment preserves opt-out');
select set_config('request.jwt.claim.sub','98000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"98000000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select lives_ok($$select public.record_account_email_choice(true,'workloop-account-emails-2026-09-v1',now(),'settings')$$,'user can affirmatively restart own emails');
reset role;
update app_private.learning_contacts set last_activity_at=now()-interval '15 days',confirmed_at=now()-interval '40 days',last_sent_at=now()-interval '8 days' where email='email-owner@example.test';
update app_private.learning_email_outbox set status='cancelled' where step between 10 and 18;
select public.enqueue_account_email_journeys();
select is((select count(*)::integer from app_private.learning_email_outbox where step=100 and status='pending'),1,'14-day inactivity queues one prompt');
create temp table inactive_claim as select * from public.claim_learning_emails(5);
select is((select step from inactive_claim),100,'inactivity prompt selected');
set local role authenticated;
select public.touch_workloop_email_activity();
reset role;
select ok(not (select public.learning_email_still_allowed(outbox_id,lease_token) from inactive_claim),'return to app cancels inactivity send');
update app_private.learning_contacts set last_sent_at=now()-interval '8 days' where email='email-owner@example.test';
select public.enqueue_account_email_journeys();
select is((select count(*)::integer from app_private.learning_email_outbox where step>=1000),1,'active user gets one weekly tip');
select public.enqueue_account_email_journeys();
select is((select count(*)::integer from app_private.learning_email_outbox where step>=1000),1,'weekly tip deduplicated');
update app_private.learning_contacts set last_activity_at=now()-interval '80 days',confirmed_at=now()-interval '90 days' where email='email-owner@example.test';
select is((select count(*)::integer from public.claim_learning_emails(5)),0,'long inactive account stops tips');
update auth.users set email='changed@example.test' where id='98000000-0000-4000-8000-000000000001';
update app_private.learning_contacts set last_activity_at=now() where email='email-owner@example.test';
select is((select count(*)::integer from public.claim_learning_emails(5)),0,'old address is not mailed after account email changes');
delete from auth.users where id='98000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.learning_contacts where email='email-owner@example.test'),0,'account deletion removes journey even after email change');
select * from finish();
rollback;
