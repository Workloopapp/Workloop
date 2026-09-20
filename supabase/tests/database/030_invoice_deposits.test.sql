begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token)
values('ea100000-0000-4000-8000-000000000001','authenticated','authenticated','document-owner@example.invalid','',now(),now(),now(),'',''),
('ea100000-0000-4000-8000-000000000002','authenticated','authenticated','document-other@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('ea100000-0000-4000-8000-000000000101','ea100000-0000-4000-8000-000000000001',now(),now()),
('ea100000-0000-4000-8000-000000000102','ea100000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values('ea200000-0000-4000-8000-000000000001','Invoice business'),('ea200000-0000-4000-8000-000000000002','Other business');
insert into public.workspace_members(workspace_id,user_id) values('ea200000-0000-4000-8000-000000000001','ea100000-0000-4000-8000-000000000001'),('ea200000-0000-4000-8000-000000000002','ea100000-0000-4000-8000-000000000002');
insert into public.contacts(id,workspace_id,name,address) values('ea300000-0000-4000-8000-000000000001','ea200000-0000-4000-8000-000000000001','Original client','1 Client Street'),('ea300000-0000-4000-8000-000000000002','ea200000-0000-4000-8000-000000000002','Other client','Private address');
insert into public.workspace_settings(workspace_id,invoice_prefix) values('ea200000-0000-4000-8000-000000000001','INV');
insert into public.invoices(id,workspace_id,invoice_number,issue_date,total,subtotal,status,amount_paid)
values('ea400000-0000-4000-8000-000000000001','ea200000-0000-4000-8000-000000000001','INV-0001',current_date,50,50,'sent',0);

create function pg_temp.doc_payload(doc_type text default 'quote') returns jsonb language sql as $$ select jsonb_build_object(
  'type',doc_type,'contact_id','ea300000-0000-4000-8000-000000000001','issue_date',current_date,'due_date',current_date+7,'service_date',current_date,
  'business_snapshot',jsonb_build_object('name','Original business','legal_name','Original Owner','email','owner@example.invalid','address','2 Business Road','vat_number','GB123456789'),
  'client_snapshot',jsonb_build_object('name','Original client','address','1 Client Street'),'tax_rate',20,
  'total',1,'notes','Agreed scope','payment_instructions','Bank transfer, reference the invoice number'); $$;
create function pg_temp.doc_items() returns jsonb language sql as $$ select '[{"description":"Work","quantity":"1.5","unit_price":"20.25","line_total":1},{"description":"Materials","quantity":2,"unit_price":5}]'::jsonb; $$;
create function pg_temp.save_doc(doc_id uuid,doc_type text default 'quote',extra jsonb default '{}',rev integer default null) returns jsonb language sql as $$
  select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload(doc_type)||extra,pg_temp.doc_items(),doc_id,rev); $$;
create function pg_temp.issue_doc(doc_id uuid) returns jsonb language sql as $$ select public.issue_business_document('ea200000-0000-4000-8000-000000000001',doc_id); $$;

select ok(not has_function_privilege('anon','public.record_document_refund(uuid,uuid,numeric,date,text)','EXECUTE'),'refund RPC is not anonymous');
select ok(not has_function_privilege('anon','public.record_document_payment_received(uuid,uuid,numeric,date,text)','EXECUTE'),'dated payment RPC is not anonymous');
select ok(not has_table_privilege('authenticated','app_private.business_document_manual_payments','INSERT,UPDATE'),'receipt date context cannot be forged by clients');
select set_config('request.jwt.claims','{"sub":"ea100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ea100000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000010','quote',jsonb_build_object('deposit_type','percentage','deposit_value','50','deposit_amount',1,'deposit_due_date',current_date))->>'deposit_amount')::numeric,24.23::numeric,'percentage deposit uses server VAT-inclusive total and penny rounding');
select is((select count(*) from public.invoices),1::bigint,'requesting a deposit on a quote creates no cash or debt');
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000010','quote')->>'revision')::integer,1,'older creation retry preserves the saved deposit');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000010','quote','{"deposit_type":"fixed","deposit_value":20}')$$,'P0001','This draft was already saved. Reopen it before editing.','changed deposit creation retry fails instead of silently discarding it');
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000010','quote','{}',1)->>'deposit_amount')::numeric,24.23::numeric,'older editor updates preserve deposit terms');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000011','invoice','{"deposit_type":"percentage","deposit_value":100.01}')$$,'P0001','Deposit must be positive and no more than the invoice total','percentage cannot exceed100');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000011','invoice','{"deposit_type":"fixed","deposit_value":49}')$$,'P0001','Deposit must be positive and no more than the invoice total','fixed deposit cannot exceed full price');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000011','invoice','{"deposit_type":"fixed","deposit_value":"NaN"}')$$,'P0001','Use a deposit amount or percentage with at most two decimal places','non-finite deposit rejected');
select is(pg_temp.issue_doc('ea500000-0000-4000-8000-000000000010')->>'status','sent','quote with proposed deposit issues without a payment');
select public.set_quote_status('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000010','accepted');
select is((public.convert_quote_to_invoice('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000010')->>'deposit_amount')::numeric,24.23::numeric,'quote conversion preserves requested deposit');
select pg_temp.issue_doc((select id from public.business_documents where source_quote_id='ea500000-0000-4000-8000-000000000010'));
select is((select deposit_amount from public.invoices where source_document_id is not null),24.23::numeric,'issuance copies deposit terms onto the same payment row');
select is((select total from public.invoices where source_document_id is not null),48.46::numeric,'deposit never reduces or increases full invoice value');
select is((select count(*) from public.business_document_receipts),0::bigint,'requesting deposit is not receipt income');
select throws_ok($$update public.invoices set deposit_amount=5 where source_document_id is not null$$,'P0001','Issued invoice details cannot be changed','issued deposit requirement immutable');
select is((public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,current_date-1,'deposit-receive-operation-1')->>'amount_paid')::numeric,10.25::numeric,'dated partial deposit uses existing invoice balance');
select is((select (received_at at time zone 'Europe/London')::date from public.business_document_receipts),current_date-1,'receipt appears on actual supplied date');
select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,current_date-1,'deposit-receive-operation-1');
select is((select count(*) from public.business_document_receipts),1::bigint,'same receipt retry has one cash event');
update public.workspace_settings set timezone='Pacific/Kiritimati' where workspace_id='ea200000-0000-4000-8000-000000000001';
select lives_ok($$select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,current_date-1,'deposit-receive-operation-1')$$,'same civil receipt date retries after business timezone changes');
update public.workspace_settings set timezone='Europe/London' where workspace_id='ea200000-0000-4000-8000-000000000001';
select throws_ok($$select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,current_date,'deposit-receive-operation-1')$$,'P0001','Payment key already used for a different date','same key cannot relabel a historical date');
select throws_ok($$select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),5,current_date+1,'deposit-receive-future-1')$$,'P0001','Choose the actual received or refunded date, not a future date','future cash cannot be recorded');
select is((public.record_document_refund('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),2.25,current_date,'deposit-refund-operation-1')->>'amount_paid')::numeric,8::numeric,'manual refund reduces collected deposit');
select public.record_document_refund('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),2.25,current_date,'deposit-refund-operation-1');
select is((select count(*) from public.business_document_receipts),2::bigint,'refund retry has one negative cash event');
select is((select sum(amount) from public.business_document_receipts),8::numeric,'signed receipt history equals remaining collected cash');
select is((select (received_at at time zone 'Europe/London')::date from public.business_document_receipts where amount<0),current_date,'refund retains its own date');
select throws_ok($$select public.record_document_refund('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),9,current_date,'deposit-refund-too-large-1')$$,'P0001','Refund must not exceed money received manually. Refund card payments through Stripe','manual refund capped to actual manual receipts');
reset role;
select is((select count(*) from app_private.business_document_manual_payments where not receipt_recorded),0::bigint,'every private reservation was consumed atomically');
update public.invoices set amount_paid=13,stripe_amount_paid=5 where source_document_id is not null;
set local role authenticated;
select throws_ok($$select public.record_document_refund('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),9,current_date,'deposit-refund-stripe-1')$$,'P0001','Refund must not exceed money received manually. Refund card payments through Stripe','manual refund cannot impersonate a Stripe refund');
select is((public.record_document_refund('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),8,current_date,'deposit-refund-all-manual')->>'amount_paid')::numeric,5::numeric,'full manual refund leaves card collection intact');
update public.workspace_settings set timezone='Pacific/Kiritimati' where workspace_id='ea200000-0000-4000-8000-000000000001';
select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),1,(now() at time zone 'Pacific/Kiritimati')::date,'deposit-dateline-retry');
update public.workspace_settings set timezone='Etc/GMT+12' where workspace_id='ea200000-0000-4000-8000-000000000001';
select lives_ok($$select public.record_document_payment_received('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),1,(now() at time zone 'Pacific/Kiritimati')::date,'deposit-dateline-retry')$$,'validated receipt retry survives a timezone change across the date line');
update public.workspace_settings set timezone='Europe/London' where workspace_id='ea200000-0000-4000-8000-000000000001';
reset role;
insert into public.appointments(id,workspace_id,contact_id,title,start_time,end_time,status,price)
values('ea600000-0000-4000-8000-000000000010','ea200000-0000-4000-8000-000000000001','ea300000-0000-4000-8000-000000000001','Unpaid booking',now()+interval '2 days',now()+interval '2 days 1 hour','scheduled',60);
insert into public.invoices(id,workspace_id,contact_id,appointment_id,invoice_number,issue_date,total,subtotal,status,amount_paid)
values('ea400000-0000-4000-8000-000000000010','ea200000-0000-4000-8000-000000000001','ea300000-0000-4000-8000-000000000001','ea600000-0000-4000-8000-000000000010','PAY-BOOKING-10',current_date,60,60,'sent',0);
set local role authenticated;
select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload('invoice')||jsonb_build_object('appointment_id','ea600000-0000-4000-8000-000000000010','deposit_type','fixed','deposit_value',20,'deposit_due_date',current_date,'prices_include_vat',true),'[{"description":"Agreed booking","quantity":1,"unit_price":60}]','ea500000-0000-4000-8000-000000000012');
select is(pg_temp.issue_doc('ea500000-0000-4000-8000-000000000012')->>'invoice_id','ea400000-0000-4000-8000-000000000010','unpaid booking payment is adopted without replacement');
select is((select invoice_number from public.business_documents where id='ea500000-0000-4000-8000-000000000012'),'PAY-BOOKING-10','adoption preserves existing unique reference');
select is((select count(*) from public.invoices where appointment_id='ea600000-0000-4000-8000-000000000010'),1::bigint,'booking still has exactly one debt');
select is((select count(*) from public.invoice_line_items where invoice_id='ea400000-0000-4000-8000-000000000010'),1::bigint,'adopted gross-price payment receives reviewed document items');
select is(pg_temp.issue_doc('ea500000-0000-4000-8000-000000000012')->>'invoice_id','ea400000-0000-4000-8000-000000000010','repeated adoption returns same issued invoice');
-- Gross prices retain the agreed charge, including pennies that cannot be
-- represented as a two-decimal net unit price.
select is((public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload('quote')||jsonb_build_object('deposit_due_date',current_date)||'{"prices_include_vat":true,"deposit_type":"percentage","deposit_value":50}', '[{"description":"Agreed visit","quantity":1,"unit_price":60}]','ea500000-0000-4000-8000-000000000020')->>'total')::numeric,60::numeric,'gross VAT never adds tax to agreed booking price');
select is((select subtotal from public.business_documents where id='ea500000-0000-4000-8000-000000000020'),50::numeric,'gross sixty pounds has fifty pounds net');
select is((select tax_amount from public.business_documents where id='ea500000-0000-4000-8000-000000000020'),10::numeric,'twenty percent VAT extracted from gross using one sixth');
select is((select deposit_amount from public.business_documents where id='ea500000-0000-4000-8000-000000000020'),30::numeric,'deposit percentage applies to agreed gross price');
select is((public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload('quote')||jsonb_build_object('deposit_due_date',current_date)||'{"prices_include_vat":true,"deposit_type":"percentage","deposit_value":50}', '[{"description":"Agreed visit","quantity":1,"unit_price":60}]','ea500000-0000-4000-8000-000000000020')->>'revision')::integer,1,'gross saved draft retry is idempotent');
select pg_temp.issue_doc('ea500000-0000-4000-8000-000000000020');
select public.set_quote_status('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000020','accepted');
select is((public.convert_quote_to_invoice('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000020')->>'prices_include_vat')::boolean,true,'converted quote preserves gross pricing');
select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload('invoice')||'{"prices_include_vat":true}', '[{"description":"Penny item","quantity":1,"unit_price":0.03}]','ea500000-0000-4000-8000-000000000021');
select is((select jsonb_build_array(subtotal,tax_amount,total) from public.business_documents where id='ea500000-0000-4000-8000-000000000021'),'[0.02,0.01,0.03]'::jsonb,'half penny VAT rounds up while preserving three pence total');
select pg_temp.issue_doc('ea500000-0000-4000-8000-000000000021');
select is((select jsonb_build_array(l.unit_price,l.line_total) from public.invoice_line_items l join public.invoices i on i.id=l.invoice_id where i.source_document_id='ea500000-0000-4000-8000-000000000021'),'[0.025,0.02]'::jsonb,'payment item records precise net unit and rounded net line amounts');
select throws_ok($$update public.business_documents set prices_include_vat=false where id='ea500000-0000-4000-8000-000000000021'$$,'42501',null,'issued gross pricing cannot be edited directly');
select is((public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload('invoice')||'{"prices_include_vat":true,"tax_rate":5}', '[{"description":"One","quantity":3,"unit_price":0.07},{"description":"Two","quantity":1,"unit_price":0.05}]','ea500000-0000-4000-8000-000000000022')->>'total')::numeric,0.26::numeric,'reduced-rate multiple lines keep their summed gross total');
select is((select jsonb_build_array(subtotal,tax_amount) from public.business_documents where id='ea500000-0000-4000-8000-000000000022'),'[0.25,0.01]'::jsonb,'reduced-rate tax rounds per line and reconciles');
reset role;
select set_config('request.jwt.claims','{"sub":"ea100000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"ea100000-0000-4000-8000-000000000102"}',true);
set local role authenticated;
select throws_ok($$select public.record_document_refund('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000012',1,current_date,'cross-tenant-refund-1')$$,'42501','Workspace access denied','refund tenant identity rechecked');
reset role;
select lives_ok($$delete from public.workspaces where id='ea200000-0000-4000-8000-000000000001'$$,'deposit terms and dated receipt reservations preserve account cascade');
select * from finish();
rollback;
