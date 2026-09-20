begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok((select relrowsecurity from pg_class where oid='app_private.stripe_payment_notification_receipts'::regclass),'receipt decision ledger has RLS');
select ok(not has_table_privilege('anon','app_private.stripe_payment_notification_receipts','SELECT,INSERT,UPDATE,DELETE'),'anonymous clients cannot inspect or change decisions');
select ok(not has_table_privilege('authenticated','app_private.stripe_payment_notification_receipts','SELECT,INSERT,UPDATE,DELETE'),'app users cannot forge or clear durable decisions');
select ok(not has_function_privilege('authenticated','app_private.notify_stripe_payment_received()','EXECUTE'),'app cannot invoke provider notification trigger');
select ok(not has_function_privilege('anon','app_private.guard_stripe_payment_notification()','EXECUTE'),'private duplicate guard is not an anonymous RPC');
select ok(not (select prosecdef from pg_proc where oid='app_private.notify_stripe_payment_received()'::regprocedure),'provider trigger uses existing service-role permissions rather than definer privileges');
select ok((select tgname from pg_trigger where tgrelid='public.payment_transactions'::regclass and tgname='sync_invoice_after_stripe_transaction') < (select tgname from pg_trigger where tgrelid='public.payment_transactions'::regclass and tgname='zz_notify_stripe_payment_received'),'invoice synchronization sorts before owner notification trigger');

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('a2600000-0000-4000-8000-000000000001','authenticated','authenticated','stripe-alert-one@example.test','',now(),now(),now()),
('a2600000-0000-4000-8000-000000000002','authenticated','authenticated','stripe-alert-two@example.test','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
('a2600000-0000-4000-8000-000000000011','a2600000-0000-4000-8000-000000000001',now(),now()),
('a2600000-0000-4000-8000-000000000012','a2600000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values
('b2600000-0000-4000-8000-000000000001','Stripe alert QA one'),
('b2600000-0000-4000-8000-000000000002','Stripe alert QA two');
insert into public.workspace_members(workspace_id,user_id) values
('b2600000-0000-4000-8000-000000000001','a2600000-0000-4000-8000-000000000001'),
('b2600000-0000-4000-8000-000000000002','a2600000-0000-4000-8000-000000000002');
insert into public.workspace_settings(workspace_id,timezone) values
('b2600000-0000-4000-8000-000000000001','Europe/London');
insert into public.notification_preferences(workspace_id,quiet_hours_enabled) values
('b2600000-0000-4000-8000-000000000001',false);
insert into public.workspace_payment_accounts(workspace_id,stripe_account_id,mode) values
('b2600000-0000-4000-8000-000000000001','acct_ReceiptOne','test'),
('b2600000-0000-4000-8000-000000000002','acct_ReceiptTwo','test');
insert into public.push_tokens(id,workspace_id,user_id,auth_session_id,token,platform,apns_environment,last_seen_at) values
('e2600000-0000-4000-8000-000000000001','b2600000-0000-4000-8000-000000000001','a2600000-0000-4000-8000-000000000001','a2600000-0000-4000-8000-000000000011','stripe-fixture-not-an-apns-token-one','ios','sandbox',now()),
('e2600000-0000-4000-8000-000000000002','b2600000-0000-4000-8000-000000000002','a2600000-0000-4000-8000-000000000002','a2600000-0000-4000-8000-000000000012','stripe-fixture-not-an-apns-token-two','ios','sandbox',now());
create function pg_temp.receipt_id(prefix text, n integer) returns uuid language sql as $$
 select (prefix || '2600000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.seed_receipt(n integer, amount bigint default 10000, total numeric default 100, manual numeric default 0, second_workspace boolean default false) returns void language plpgsql as $$
declare w uuid := pg_temp.receipt_id('b',case when second_workspace then 2 else 1 end);
begin
 insert into public.invoices(id,workspace_id,invoice_number,issue_date,total,amount_paid,status)
 values(pg_temp.receipt_id('c',n),w,'PAY-ALERT-'||n,current_date,total,manual,'sent');
 insert into public.payment_transactions(id,workspace_id,invoice_id,stripe_account_id,stripe_payment_intent_id,collection_method,status,amount_minor,idempotency_key)
 values(pg_temp.receipt_id('d',n),w,pg_temp.receipt_id('c',n),case when second_workspace then 'acct_ReceiptTwo' else 'acct_ReceiptOne' end,'pi_Receipt'||n,'payment_link','pending',amount,'stripe-receipt-operation-'||n);
end;
$$;
select pg_temp.seed_receipt(1);
select pg_temp.seed_receipt(2,4000);
select pg_temp.seed_receipt(3);
select pg_temp.seed_receipt(4);
select pg_temp.seed_receipt(5);
select pg_temp.seed_receipt(6);
select pg_temp.seed_receipt(7);
select pg_temp.seed_receipt(8);
select pg_temp.seed_receipt(9);
select pg_temp.seed_receipt(10,10000,100,0,true);
select pg_temp.seed_receipt(11,4000,100,60);
select pg_temp.seed_receipt(12);
select pg_temp.seed_receipt(13);
select pg_temp.seed_receipt(14);
select pg_temp.seed_receipt(15,4000);
select pg_temp.seed_receipt(16,6000);
update public.payment_transactions set invoice_id=pg_temp.receipt_id('c',15) where id=pg_temp.receipt_id('d',16);
select is((select count(*)::integer from app_private.stripe_payment_notification_receipts),0,'pending transactions do not consume the receipt decision');
select is((select count(*)::integer from public.notifications where type='payment_received'),0,'pending transactions do not claim received income');

-- Inspect the invoice at actual notification insertion: reconciliation must
-- already have updated its provider amount, rather than relying on name alone.
create temporary table stripe_notification_order(invoice_id uuid, amount_paid numeric);
create function pg_temp.capture_stripe_notification_order() returns trigger language plpgsql as $$
begin
 if starts_with(coalesce(new.dedupe_key,''),'stripe_payment_received:') then
  insert into stripe_notification_order select id,amount_paid from public.invoices where id=split_part(new.deep_link,'/',3)::uuid;
 end if;
 return new;
end;
$$;
grant insert,select on stripe_notification_order to service_role;
create trigger zzz_capture_stripe_order before insert on public.notifications for each row execute function pg_temp.capture_stripe_notification_order();
set local role service_role;
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt1' where id=pg_temp.receipt_id('d',1);
reset role;
select is((select amount_paid from stripe_notification_order where invoice_id=pg_temp.receipt_id('c',1)),100::numeric,'invoice is already reconciled when its owner alert is inserted');
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1)),1,'successful service-role collection creates one alert');
select is((select deep_link from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1)),'/payments/'||pg_temp.receipt_id('c',1),'owner alert opens its exact invoice');
select is((select body from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1)),'£100.00 received by card.','received amount uses the provider collection rather than total owed');
select is((select count(*)::integer from app_private.push_delivery_outbox),1,'existing pipeline enqueues one push for the matching workspace device');
select is((select push_token_id from app_private.push_delivery_outbox),pg_temp.receipt_id('e',1),'no push goes to another workspace device');
update public.payment_transactions set status='succeeded',receipt_url='https://example.test/receipt',updated_at=now() where id=pg_temp.receipt_id('d',1);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1)),1,'duplicate success and receipt refresh do not create another alert');
select is((select count(*)::integer from app_private.push_delivery_outbox),1,'duplicate success cannot duplicate push outbox rows');

-- Manual completion notifications are redundant only when no manual money was
-- added. The existing workflow's dedupe key is deliberately preserved.
insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key)
values(pg_temp.receipt_id('b',1),'payment_received','Payment received','Manual retry','/payments/'||pg_temp.receipt_id('c',1),'workflow:complete_booking:stripe-manual-retry');
select is((select count(*)::integer from public.notifications where dedupe_key='workflow:complete_booking:stripe-manual-retry'),0,'fully card-funded invoice suppresses redundant manual completion alert');
delete from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1);
update public.payment_transactions set status='succeeded' where id=pg_temp.receipt_id('d',1);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',1)),0,'deleting an inbox alert cannot replay its durable receipt decision');
select is((select decision from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',1)),'queued','clearing the inbox retains its receipt decision');

update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt2' where id=pg_temp.receipt_id('d',2);
select is((select body from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',2)),'£40.00 received by card.','partial card receipt reports only money actually collected');
select is((select status from public.invoices where id=pg_temp.receipt_id('c',2)),'sent','part-paid invoice remains owed');
update public.invoices set amount_paid=100,status='paid' where id=pg_temp.receipt_id('c',2);
insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key)
values(pg_temp.receipt_id('b',1),'payment_received','Payment received','Manual balance','/payments/'||pg_temp.receipt_id('c',2),'manual-balance-receipt');
select is((select count(*)::integer from public.notifications where dedupe_key='manual-balance-receipt'),1,'new manual balance after a partial card payment still produces its alert');
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt11' where id=pg_temp.receipt_id('d',11);
insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key)
values(pg_temp.receipt_id('b',1),'payment_received','Payment received','Mixed balance','/payments/'||pg_temp.receipt_id('c',11),'mixed-balance-receipt');
select is((select count(*)::integer from public.notifications where dedupe_key='mixed-balance-receipt'),1,'pre-existing manual money is not mistaken for wholly Stripe-funded payment');
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt15' where id=pg_temp.receipt_id('d',15);
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt16' where id=pg_temp.receipt_id('d',16);
select is((select count(*)::integer from public.notifications where deep_link='/payments/'||pg_temp.receipt_id('c',15)),2,'two legitimate installments each produce one exact-invoice alert');
select is((select amount_paid from public.invoices where id=pg_temp.receipt_id('c',15)),100::numeric,'two receipts reconcile to the invoice total without double counting');
insert into public.appointments(id,workspace_id,title,start_time,end_time,status,price)
values(pg_temp.receipt_id('f',15),pg_temp.receipt_id('b',1),'Card-paid booking',now()+interval '1 day',now()+interval '1 day 1 hour','scheduled',100);
update public.invoices set appointment_id=pg_temp.receipt_id('f',15) where id=pg_temp.receipt_id('c',15);
select set_config('request.jwt.claims','{"sub":"a2600000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"a2600000-0000-4000-8000-000000000011"}',true);
set local role authenticated;
select lives_ok($$select public.complete_booking_workflow(jsonb_build_object('workspace_id','b2600000-0000-4000-8000-000000000001','appointment_id','f2600000-0000-4000-8000-000000000015','linked_payment_id','c2600000-0000-4000-8000-000000000015','payment_mode','linked_paid','idempotency_key','stripe-receipt-complete-booking-15'))$$,'actual booking completion remains successful for an already card-paid invoice');
reset role;
select is((select status from public.appointments where id=pg_temp.receipt_id('f',15)),'completed','duplicate-alert suppression does not roll back booking completion');
select is((select count(*)::integer from public.notifications where dedupe_key='workflow:complete_booking:stripe-receipt-complete-booking-15'),0,'real completion workflow does not add a third paid alert');

update public.notification_preferences set all_notifications=false where workspace_id=pg_temp.receipt_id('b',1);
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt3' where id=pg_temp.receipt_id('d',3);
select is((select decision from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',3)),'preferences_disabled','master preference is checked at collection');
update public.notification_preferences set all_notifications=true where workspace_id=pg_temp.receipt_id('b',1);
update public.payment_transactions set status='succeeded' where id=pg_temp.receipt_id('d',3);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',3)),0,'turning preferences back on cannot replay old receipts');
update public.notification_preferences set payment_received=false where workspace_id=pg_temp.receipt_id('b',1);
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt4' where id=pg_temp.receipt_id('d',4);
select is((select decision from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',4)),'preferences_disabled','payment category preference suppresses both inbox and push');
update public.notification_preferences set payment_received=true where workspace_id=pg_temp.receipt_id('b',1);

update public.payment_transactions set status='refunded',amount_refunded_minor=10000,paid_at=now(),stripe_charge_id='ch_Receipt5' where id=pg_temp.receipt_id('d',5);
update public.payment_transactions set status='disputed',paid_at=now(),stripe_charge_id='ch_Receipt6' where id=pg_temp.receipt_id('d',6);
select is((select count(*)::integer from app_private.stripe_payment_notification_receipts where transaction_id in (pg_temp.receipt_id('d',5),pg_temp.receipt_id('d',6)) and decision='settlement_changed'),2,'refund/dispute arriving before success is consumed without a misleading receipt');
update public.payment_transactions set status='succeeded',amount_refunded_minor=0 where id in (pg_temp.receipt_id('d',5),pg_temp.receipt_id('d',6));
select is((select count(*)::integer from public.notifications where dedupe_key in ('stripe_payment_received:'||pg_temp.receipt_id('d',5),'stripe_payment_received:'||pg_temp.receipt_id('d',6))),0,'out-of-order or dispute-won transitions do not announce old income again');
update public.payment_transactions set status='partially_refunded',amount_refunded_minor=1000 where id=pg_temp.receipt_id('d',11);
update public.payment_transactions set status='refunded',amount_refunded_minor=4000 where id=pg_temp.receipt_id('d',11);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',11)),1,'partial and full refunds do not create new received alerts');

update public.payment_transactions set stripe_account_id='acct_OtherAccount',status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt7' where id=pg_temp.receipt_id('d',7);
select is((select count(*)::integer from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',7)),0,'mismatched merchant cannot reserve or issue an owner receipt');
update public.payment_transactions set status='succeeded' where id=pg_temp.receipt_id('d',8);
select is((select count(*)::integer from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',8)),0,'a bare succeeded label without verified charge metadata is insufficient');
update public.payment_transactions set paid_at=now(),stripe_charge_id='ch_Receipt8' where id=pg_temp.receipt_id('d',8);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',8)),1,'later completed reconciliation can issue the first genuine receipt');
update public.payment_transactions set status='failed' where id=pg_temp.receipt_id('d',9);
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt9' where id=pg_temp.receipt_id('d',9);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',9)),1,'failed attempt does not suppress a later successful payment');
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt10' where id=pg_temp.receipt_id('d',10);
select is((select workspace_id from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',10)),pg_temp.receipt_id('b',2),'missing preference row defaults correctly within its own workspace');
select is((select push_token_id from app_private.push_delivery_outbox where notification_id=(select notification_id from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',10))),pg_temp.receipt_id('e',2),'second workspace receipt queues only its own push device');

-- Delivery failure cannot commit the accounting update while losing the receipt.
create function pg_temp.fail_receipt_insert() returns trigger language plpgsql as $$
begin
 if new.dedupe_key='stripe_payment_received:d2600000-0000-4000-8000-000000000013' then raise exception 'Synthetic notification failure'; end if;
 return new;
end;
$$;
create trigger zzzz_fail_receipt_insert before insert on public.notifications for each row execute function pg_temp.fail_receipt_insert();
select throws_ok($$update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt13' where id=pg_temp.receipt_id('d',13)$$,'P0001','Synthetic notification failure','notification failure returns a retryable atomic reconciliation failure');
select is((select status from public.payment_transactions where id=pg_temp.receipt_id('d',13)),'pending','failed notification insert rolls transaction status back');
select is((select amount_paid from public.invoices where id=pg_temp.receipt_id('c',13)),0::numeric,'failed notification insert rolls invoice accounting back');
select is((select count(*)::integer from app_private.stripe_payment_notification_receipts where transaction_id=pg_temp.receipt_id('d',13)),0,'failed insert cannot consume receipt decision');
drop trigger zzzz_fail_receipt_insert on public.notifications;
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt13' where id=pg_temp.receipt_id('d',13);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',13)),1,'retry after recoverable failure produces one receipt');

select set_config('request.jwt.claims','{"sub":"a2600000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"a2600000-0000-4000-8000-000000000011"}',true);
set local role authenticated;
select throws_ok($$update public.payment_transactions set status='succeeded' where id=pg_temp.receipt_id('d',14)$$,'42501',null,'ordinary app users cannot forge provider success');
select throws_ok($$insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key) values('b2600000-0000-4000-8000-000000000001','payment_received','Forged','Not real','/payments/c2600000-0000-4000-8000-000000000014','stripe_payment_received:d2600000-0000-4000-8000-000000000014')$$,'42501','Provider payment notifications require a reconciled receipt','client cannot occupy a future provider dedupe key');
select throws_ok($$insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key) values('b2600000-0000-4000-8000-000000000001','booking','Forged type','Not real','/bookings','stripe_payment_received:d2600000-0000-4000-8000-000000000014')$$,'42501','Provider payment notifications require a reconciled receipt','changing notification type cannot bypass reserved key protection');
select throws_ok($$update public.notifications set dedupe_key='stripe_payment_received:d2600000-0000-4000-8000-000000000014' where dedupe_key='manual-balance-receipt'$$,'42501','Provider payment notifications require a reconciled receipt','updating an ordinary alert cannot occupy a provider dedupe key');
select throws_ok($$insert into public.notifications(workspace_id,type,title,body,deep_link) values('b2600000-0000-4000-8000-000000000002','payment_received','Foreign','Not real','/payments/c2600000-0000-4000-8000-000000000010')$$,'42501','Workspace access denied','foreign-workspace notification is rejected before private ledger inspection');
select is((select count(*)::integer from public.notifications where workspace_id='b2600000-0000-4000-8000-000000000002'),0,'notification RLS still hides other businesses');
reset role;
select throws_ok($$insert into public.notifications(workspace_id,type,title,body,deep_link,dedupe_key) values('b2600000-0000-4000-8000-000000000001','payment_received','Unreserved','Not real','/payments/c2600000-0000-4000-8000-000000000014','stripe_payment_received:d2600000-0000-4000-8000-000000000014')$$,'42501','Provider payment notifications require a reconciled receipt','even server inserts need the matching durable reservation');
update public.payment_transactions set status='succeeded',paid_at=now(),stripe_charge_id='ch_Receipt14' where id=pg_temp.receipt_id('d',14);
select is((select count(*)::integer from public.notifications where dedupe_key='stripe_payment_received:'||pg_temp.receipt_id('d',14)),1,'rejected forgery cannot prevent a later real receipt');

-- The existing dispatch policy is rechecked after enqueue, not replaced here.
update public.notification_preferences set payment_received=false where workspace_id=pg_temp.receipt_id('b',1);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select count(*)::integer from public.claim_push_deliveries(50) claim join app_private.push_delivery_outbox delivery on delivery.id=claim.delivery_id where delivery.workspace_id=pg_temp.receipt_id('b',1)),0,'turning payment alerts off before delivery prevents queued Stripe pushes');
select ok(not exists(select 1 from app_private.push_delivery_outbox where workspace_id=pg_temp.receipt_id('b',1) and status='pending'),'suppressed pushes use the existing terminal suppression path');
set constraints all immediate;
select * from finish();
rollback;
