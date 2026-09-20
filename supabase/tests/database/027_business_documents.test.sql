begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok((select relrowsecurity from pg_class where oid='public.business_documents'::regclass),'business documents enforce RLS');
select ok(has_table_privilege('authenticated','public.business_documents','SELECT') and not has_table_privilege('authenticated','public.business_documents','INSERT,UPDATE,DELETE'),'clients can read documents but must use atomic workflows to write');
select ok(not has_table_privilege('anon','public.business_documents','SELECT'),'quotes and business addresses are private');
select ok(not has_table_privilege('authenticated','app_private.business_document_counters','SELECT,INSERT,UPDATE,DELETE'),'clients cannot allocate or reset invoice numbers');
select ok(not has_function_privilege('anon','public.save_business_document(uuid,jsonb,jsonb,uuid,integer)','EXECUTE'),'anonymous callers cannot create documents');
select ok(not (select prosecdef from pg_proc where oid='public.issue_business_document(uuid,uuid,integer)'::regprocedure),'public issue wrapper retains invoker security');

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

select set_config('request.jwt.claims','{"sub":"ea100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ea100000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select is(pg_temp.save_doc('ea500000-0000-4000-8000-000000000001')->>'status','draft','saving a quote creates only a draft');
select is((select count(*) from public.invoices where workspace_id='ea200000-0000-4000-8000-000000000001'),1::bigint,'older apps see exactly the legacy payment while quote remains a draft');
select is((select subtotal from public.business_documents where id='ea500000-0000-4000-8000-000000000001'),40.38::numeric,'server rounds line amounts before summing');
select is((select total from public.business_documents where id='ea500000-0000-4000-8000-000000000001'),48.46::numeric,'server calculates VAT and ignores client totals');
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000001')->>'revision')::integer,1,'retrying draft creation is idempotent');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{"notes":"Edited after lost response"}')$$,'P0001','This draft was already saved. Reopen it before editing.','changed creation retries cannot silently discard unsaved edits');
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{}',1)->>'revision')::integer,2,'a reviewed draft revision is saved');
select is((pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{}',1)->>'revision')::integer,2,'retrying the exact successful update is idempotent');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{"notes":"Different stale edit"}',1)$$,'P0001','This document changed on another device. Refresh before saving','changed update retries cannot overwrite newer content');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{}',99)$$,'P0001','This document changed on another device. Refresh before saving','stale draft writes are rejected');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000002','invoice','{"contact_id":"ea300000-0000-4000-8000-000000000002"}')$$,'P0001','Client was not found in this business','cross-tenant client injection is rejected');
select throws_ok($$select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload(),'[{"description":"Bad","quantity":-1,"unit_price":10}]')$$,'P0001','Use positive quantities and prices with at most two decimal places','negative quantities cannot manufacture a negative invoice');
select throws_ok($$select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload(),'[{"description":"Bad","quantity":1,"unit_price":"NaN"}]')$$,'P0001','Use positive quantities and prices with at most two decimal places','non-finite money values are rejected');
select throws_ok($$select public.save_business_document('ea200000-0000-4000-8000-000000000001',pg_temp.doc_payload(),'[{"description":"Quantity precision","quantity":"1.005","unit_price":100}]')$$,'P0001','Use positive quantities and prices with at most two decimal places','quantity precision matches the editable model and issued PDF');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000002','invoice','{"business_snapshot":{"name":12,"address":"Road"}}')$$,'P0001','Business and client details must be text of up to 2000 characters each','invalid business snapshot cannot be hidden by valid client fields');
select is(pg_temp.issue_doc('ea500000-0000-4000-8000-000000000001')->>'invoice_number','QUO-0001','quote issue allocates its own number');
select is((select count(*) from public.invoices where workspace_id='ea200000-0000-4000-8000-000000000001'),1::bigint,'issued quotes never become money owed in legacy apps');
select throws_ok($$select public.convert_quote_to_invoice('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000001')$$,'P0001','Accept the quote before creating an invoice','conversion requires an accepted quote');
select is(public.set_quote_status('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000001','accepted')->>'status','accepted','owner can record quote acceptance');
update public.workspace_settings set timezone=case when extract(hour from now() at time zone 'UTC')>=12 then 'Pacific/Kiritimati' else 'Etc/GMT+12' end where workspace_id='ea200000-0000-4000-8000-000000000001';
select is(public.convert_quote_to_invoice('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000001')->>'status','draft','accepted quote converts to a reviewable invoice draft');
select is((select issue_date from public.business_documents where source_quote_id='ea500000-0000-4000-8000-000000000001'),(select (now() at time zone timezone)::date from public.workspace_settings where workspace_id='ea200000-0000-4000-8000-000000000001'),'converted invoice starts on the business local date rather than UTC date');
update public.workspace_settings set timezone='Europe/London' where workspace_id='ea200000-0000-4000-8000-000000000001';
select is(public.convert_quote_to_invoice('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000001')->>'id',(select id::text from public.business_documents where source_quote_id='ea500000-0000-4000-8000-000000000001'),'conversion retries return the same invoice');
select is((select count(*) from public.invoices where workspace_id='ea200000-0000-4000-8000-000000000001'),1::bigint,'invoice drafts never enter the existing ledger');
select is(pg_temp.issue_doc((select id from public.business_documents where source_quote_id='ea500000-0000-4000-8000-000000000001'))->>'invoice_number','INV-0002','invoice numbering skips existing invoice numbers');
select is((select count(*) from public.invoices where source_document_id is not null),1::bigint,'issue creates one ordinary ledger invoice');
select is(pg_temp.issue_doc((select id from public.business_documents where source_quote_id='ea500000-0000-4000-8000-000000000001'))->>'invoice_number','INV-0002','issue retry preserves number and identity');
select is((select count(*) from public.invoice_line_items where invoice_id in(select invoice_id from public.business_documents)),2::bigint,'issue snapshots one set of invoice line items');
select throws_ok($$update public.invoices set total=1 where source_document_id is not null$$,'P0001','Issued invoice details cannot be changed','legacy editors cannot overwrite an issued invoice total');
select throws_ok($$update public.invoice_line_items set description='Changed' where invoice_id in(select invoice_id from public.business_documents)$$,'P0001','Issued invoice items cannot be changed','issued line descriptions are immutable');
select throws_ok($$delete from public.invoices where source_document_id is not null$$,'P0001','Issued invoices must be retained; cancel an unpaid invoice instead','issued payment records cannot be deleted through older apps');
select throws_ok($$update public.business_documents set notes='Changed'$$,'42501','permission denied for table business_documents','direct document updates cannot bypass issuance rules');
select throws_ok($$select pg_temp.save_doc('ea500000-0000-4000-8000-000000000001','quote','{}',3)$$,'P0001','Issued documents cannot be edited','issued quote snapshot stays immutable');
select is((public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,'manual-payment-operation-1')->>'amount_paid')::numeric,10.25::numeric,'partial payment records the actual amount');
select is((public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),10.25,'manual-payment-operation-1')->>'amount_paid')::numeric,10.25::numeric,'manual payment retry cannot double count income');
select throws_ok($$select public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),99,'manual-payment-operation-2')$$,'P0001','Payment must not exceed the outstanding balance','manual payment cannot exceed balance');
select throws_ok($$select public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),11,'manual-payment-operation-1')$$,'P0001','Payment key already used for a different amount','reusing a payment key with another amount fails');
select throws_ok($$select public.cancel_business_document('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'))$$,'P0001','An invoice with payments cannot be cancelled','paid value cannot be cancelled away');
select is(public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),38.21,'manual-payment-operation-3')->>'status','paid','final instalment synchronises the document paid state');
select is((select count(*) from public.business_document_receipts),2::bigint,'retry creates no extra receipt timing entry');
select is((select sum(amount) from public.business_document_receipts),48.46::numeric,'receipt deltas reconcile exactly to paid balance');
select throws_ok($$update public.invoices set amount_paid=10.255,status='sent' where source_document_id is not null$$,'P0001','Payment must be within the invoice total and use at most two decimal places','direct balance changes cannot lose fractional pennies in receipt history');
select lives_ok($$update public.invoices set amount_paid=43.46,status='sent' where source_document_id is not null$$,'a corrected or refunded balance remains supported');
select is((select sum(amount) from public.business_document_receipts),43.46::numeric,'negative receipt delta records refunds or manual corrections in the current period');

reset role;
select public.reserve_stripe_collection('ea200000-0000-4000-8000-000000000001',(select invoice_id from public.business_documents where type='invoice'),'ea100000-0000-4000-8000-000000000001','pending-document-stripe-link','payment_link',500,'');
set local role authenticated;
select throws_ok($$select public.record_document_payment('ea200000-0000-4000-8000-000000000001',(select id from public.business_documents where type='invoice'),5,'manual-payment-during-stripe')$$,'P0001','A card payment is in progress. Wait for it to finish or close it in Stripe before changing the balance','RPC manual payment observes the existing active Stripe reservation guard');
reset role;
delete from app_private.stripe_collection_reservations where workspace_id='ea200000-0000-4000-8000-000000000001';
set local role authenticated;

select is(pg_temp.save_doc('ea500000-0000-4000-8000-000000000003','invoice','{"business_snapshot":{"name":"Business","address":"Road"}}')->>'status','draft','incomplete VAT information may be saved for later');
select throws_ok($$select pg_temp.issue_doc('ea500000-0000-4000-8000-000000000003')$$,'P0001','Add your VAT registration number before charging VAT','VAT invoice cannot issue without a VAT number');
select is(pg_temp.save_doc('ea500000-0000-4000-8000-000000000003','invoice','{"tax_rate":0}',1)->>'status','draft','zero VAT supports unregistered owners');
select is(pg_temp.issue_doc('ea500000-0000-4000-8000-000000000003')->>'invoice_number','INV-0003','failed issue consumed neither number nor ledger invoice');
reset role;
select public.reserve_stripe_collection('ea200000-0000-4000-8000-000000000001',(select invoice_id from public.business_documents where id='ea500000-0000-4000-8000-000000000003'),'ea100000-0000-4000-8000-000000000001','unpaid-document-stripe-link','payment_link',null,'');
set local role authenticated;
select throws_ok($$select public.cancel_business_document('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000003')$$,'P0001','A card payment is in progress. Wait for it to finish or close it in Stripe before changing the balance','an unpaid invoice cannot cancel while its payment link is active');
reset role;
delete from app_private.stripe_collection_reservations where workspace_id='ea200000-0000-4000-8000-000000000001';
insert into public.appointments(id,workspace_id,title,start_time,end_time,status)
values('ea600000-0000-4000-8000-000000000001','ea200000-0000-4000-8000-000000000001','Already billed booking',now()+interval '1 day',now()+interval '1 day 1 hour','scheduled');
insert into public.invoices(workspace_id,appointment_id,invoice_number,issue_date,total,subtotal,status,amount_paid)
values('ea200000-0000-4000-8000-000000000001','ea600000-0000-4000-8000-000000000001','PAY-EXISTING',current_date,40,40,'sent',0);
set local role authenticated;
select pg_temp.save_doc('ea500000-0000-4000-8000-000000000005','invoice','{"appointment_id":"ea600000-0000-4000-8000-000000000001"}');
select throws_ok($$select pg_temp.issue_doc('ea500000-0000-4000-8000-000000000005')$$,'P0001','This booking already has a payment record. Use the existing payment to avoid charging twice','booking linkage cannot create a second debt alongside a legacy payment');
select is(public.cancel_business_document('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000003')->>'status','cancelled','unpaid issued invoice can be cancelled without deletion');
select is((select count(*) from public.invoices where source_document_id='ea500000-0000-4000-8000-000000000003'),1::bigint,'cancelled invoices retain their original number and record');
select is(pg_temp.save_doc('ea500000-0000-4000-8000-000000000004','invoice')->>'status','draft','standalone invoice draft is supported');
select is(public.delete_business_document('ea200000-0000-4000-8000-000000000001','ea500000-0000-4000-8000-000000000004')->>'deleted','true','unused drafts can be deleted');
select lives_ok($$update public.invoices set total=60,subtotal=60 where id='ea400000-0000-4000-8000-000000000001'$$,'legacy payment editing still works');
select lives_ok($$delete from public.contacts where id='ea300000-0000-4000-8000-000000000001'$$,'client deletion can clear relationship IDs');
select is((select client_snapshot->>'name' from public.business_documents where id='ea500000-0000-4000-8000-000000000001'),'Original client','issued client details survive contact deletion');
reset role;
select set_config('request.jwt.claims','{"sub":"ea100000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"ea100000-0000-4000-8000-000000000102"}',true);
set local role authenticated;
select is((select count(*) from public.business_documents),0::bigint,'other businesses cannot see document addresses or prices');
select throws_ok($$select pg_temp.issue_doc('ea500000-0000-4000-8000-000000000001')$$,'42501','Workspace access denied','other businesses cannot mutate a document through its UUID');
reset role;
select lives_ok($$delete from public.workspaces where id='ea200000-0000-4000-8000-000000000001'$$,'workspace deletion still cascades document records and the linked invoice ledger');
select * from finish();
rollback;
