begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(20);
select ok(has_function_privilege('service_role','public.reserve_stripe_collection(uuid,uuid,uuid,text,text,bigint,text)','EXECUTE'), 'only server can reserve a card collection');
select ok(not has_function_privilege('authenticated','public.reserve_stripe_collection(uuid,uuid,uuid,text,text,bigint,text)','EXECUTE') and not has_function_privilege('anon','public.reserve_stripe_collection(uuid,uuid,uuid,text,text,bigint,text)','EXECUTE'), 'clients cannot bypass authenticated Edge security');
select ok((select relrowsecurity from pg_class where oid='app_private.stripe_collection_reservations'::regclass), 'private reservations retain RLS');
select ok(not has_table_privilege('authenticated','app_private.stripe_collection_reservations','INSERT,UPDATE,DELETE'), 'clients cannot forge or release a collection');
insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, confirmation_token, recovery_token)
values('d1000000-0000-4000-8000-000000000001','authenticated','authenticated','stripe-reservation@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('d1000000-0000-4000-8000-000000000101','d1000000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id,name) values('d2000000-0000-4000-8000-000000000001','Stripe reservation test');
insert into public.workspace_members(workspace_id,user_id) values('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
insert into public.invoices(id,workspace_id,invoice_number,issue_date,total,amount_paid,status) values('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','PAY-RESERVE-1',current_date,100,0,'sent');
create function pg_temp.reserve_test(key text, method text default 'payment_link', amount bigint default 3000, actor uuid default 'd1000000-0000-4000-8000-000000000001') returns jsonb language sql as $$
 select public.reserve_stripe_collection('d2000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001',actor,key,method,amount,'');
$$;
select throws_ok($$select pg_temp.reserve_test('below-provider-minimum','payment_link',10)$$,'P0001','Card payments must be at least GBP 0.30. Record this payment manually','sub-minimum card amounts are rejected before reserving or calling Stripe');
select is(pg_temp.reserve_test('first-device-operation')->>'idempotencyKey','first-device-operation','first device reserves a provider key');
select is(pg_temp.reserve_test('second-device-operation')->>'idempotencyKey','first-device-operation','another device reuses the active key rather than creating another charge');
update app_private.stripe_collection_reservations set created_at=now()-interval '24 hours';
select throws_ok($$select pg_temp.reserve_test('late-retry-operation')$$,'P0001','A previous payment attempt needs review in Stripe before retrying','unknown provider attempts fail closed before Stripe forgets their idempotency key');
update app_private.stripe_collection_reservations set created_at=now();
select throws_ok($$select pg_temp.reserve_test('different-method-operation','tap_to_pay')$$,'P0001','A payment is already in progress. Continue the existing payment or wait for it to close','cannot collect the same invoice by two methods');
select throws_ok($$select pg_temp.reserve_test('different-amount-operation','payment_link',5000)$$,'P0001','A payment is already in progress. Continue the existing payment or wait for it to close','a retry cannot silently change the charge amount');
select throws_ok($$select pg_temp.reserve_test('different-user-operation','payment_link',3000,'d1000000-0000-4000-8000-000000000099')$$,'P0001','Workspace access denied','other users cannot reserve a tenant invoice');
insert into public.payment_transactions(id,workspace_id,invoice_id,stripe_account_id,stripe_checkout_session_id,collection_method,status,amount_minor,idempotency_key)
values('d4000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','acct_ReservationTest','cs_ReservationFirst','payment_link','cancelled',3000,'first-device-operation');
select isnt(pg_temp.reserve_test('first-device-operation')->>'idempotencyKey','first-device-operation','provider-confirmed expiry can safely replace a cached request key');
insert into public.payment_transactions(workspace_id,invoice_id,stripe_account_id,stripe_payment_intent_id,collection_method,status,amount_minor,idempotency_key)
select workspace_id,invoice_id,'acct_ReservationTest','pi_ReservationPaid','payment_link','succeeded',amount_minor,idempotency_key from app_private.stripe_collection_reservations where invoice_id='d3000000-0000-4000-8000-000000000001';
select is((select amount_paid from public.invoices where id='d3000000-0000-4000-8000-000000000001'),30::numeric,'a completed partial charge is recorded atomically');
select is((pg_temp.reserve_test('next-partial-operation','payment_link',null)->>'amountMinor')::bigint,7000::bigint,'later collection reserves only the remaining balance');
select is((select count(*) from app_private.stripe_collection_reservations where invoice_id='d3000000-0000-4000-8000-000000000001'),1::bigint,'there is one durable reservation per invoice');
select throws_ok($$select pg_temp.reserve_test('excessive-operation','payment_link',7001)$$,'P0001','Amount must not exceed the outstanding balance','provider collection cannot exceed remaining money due');
select set_config('request.jwt.claims','{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"d1000000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select throws_ok($$update public.invoices set amount_paid=100 where id='d3000000-0000-4000-8000-000000000001'$$,'P0001','A card payment is in progress. Wait for it to finish or close it in Stripe before changing the balance','manual marking paid cannot leave a payable shared link behind');
select throws_ok($$update public.invoices set status='cancelled' where id='d3000000-0000-4000-8000-000000000001'$$,'P0001','A card payment is in progress. Wait for it to finish or close it in Stripe before changing the balance','manual cancellation must close the provider collection first');
reset role;
set local role service_role;
select lives_ok($$update public.invoices set amount_paid=31 where id='d3000000-0000-4000-8000-000000000001'$$,'trusted provider reconciliation can update an active invoice');
reset role;
update public.invoices set status='cancelled' where id='d3000000-0000-4000-8000-000000000001';
select throws_ok($$select pg_temp.reserve_test('cancelled-invoice-operation')$$,'P0001','This record cannot accept a card payment','cancelled records cannot start card collection');
select * from finish();
rollback;
