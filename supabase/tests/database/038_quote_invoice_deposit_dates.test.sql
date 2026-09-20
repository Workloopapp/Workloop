begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(10);
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
values('ee100000-0000-4000-8000-000000000001','authenticated','authenticated','quote-date-owner@example.invalid',now(),now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('ee100000-0000-4000-8000-000000000101','ee100000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id,name) values('ee200000-0000-4000-8000-000000000001','Quote date test');
insert into public.workspace_members(workspace_id,user_id) values('ee200000-0000-4000-8000-000000000001','ee100000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id,timezone,default_payment_terms_days)
values('ee200000-0000-4000-8000-000000000001','Europe/London',7);
create function pg_temp.business_today() returns date language sql as $$select (now() at time zone 'Europe/London')::date$$;
insert into public.business_documents(id,workspace_id,type,status,invoice_number,issue_date,due_date,issued_at,total,subtotal,deposit_type,deposit_value,deposit_amount,deposit_due_date)
select ('ee300000-0000-4000-8000-00000000000'||n)::uuid,'ee200000-0000-4000-8000-000000000001','quote','accepted','QUO-DATE-'||n,pg_temp.business_today()-20,pg_temp.business_today()+30,now()-interval '20 days',100,100,
case when n=4 then 'none' else 'fixed' end,case when n=4 then 0 else 25 end,case when n=4 then 0 else 25 end,
case n when 1 then pg_temp.business_today()-10 when 2 then pg_temp.business_today()+3 when 3 then pg_temp.business_today()+20 else null end
from generate_series(1,4) n;
create function pg_temp.convert_quote(n integer) returns jsonb language sql as $$select public.convert_quote_to_invoice('ee200000-0000-4000-8000-000000000001',('ee300000-0000-4000-8000-00000000000'||n)::uuid)$$;
select set_config('request.jwt.claims','{"sub":"ee100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ee100000-0000-4000-8000-000000000101"}',true);
set local role authenticated;
select ok((pg_temp.convert_quote(1)->>'deposit_due_date')::date=pg_temp.business_today(),'past deposit date becomes new invoice issue date');
select ok((pg_temp.convert_quote(2)->>'deposit_due_date')::date=pg_temp.business_today()+3,'valid proposed deposit date is preserved');
select ok((pg_temp.convert_quote(3)->>'deposit_due_date')::date=pg_temp.business_today()+7,'deposit beyond shorter invoice terms becomes final due date');
select ok(pg_temp.convert_quote(4)->>'deposit_due_date' is null,'no-deposit invoice has no invented deposit due date');
select ok((select deposit_due_date from public.business_documents where id='ee300000-0000-4000-8000-000000000001')=pg_temp.business_today()-10,'issued quote date is unchanged');
select ok((pg_temp.convert_quote(1)->>'deposit_amount')::numeric=25,'deposit amount is preserved');
select ok((pg_temp.convert_quote(1)->>'total')::numeric=100,'conversion preserves invoice total');
select ok((select count(*) from public.business_documents where source_quote_id is not null)=4,'retries create exactly one invoice per quote');
reset role;
update public.business_documents set deposit_due_date=pg_temp.business_today()+5 where source_quote_id='ee300000-0000-4000-8000-000000000001';
set local role authenticated;
select ok((pg_temp.convert_quote(1)->>'deposit_due_date')::date=pg_temp.business_today()+5,'conversion retry preserves reviewed draft date');
select ok((pg_temp.convert_quote(1)->>'status')='draft','conversion does not issue or request payment');
select * from finish();
rollback;
