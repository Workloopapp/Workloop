begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(25);

select has_table('app_private', 'account_deletion_email_outbox', 'deletion email outbox exists');
select has_column('app_private', 'account_deletion_email_outbox', 'request_id', 'outbox links deletion request');
select has_column('app_private', 'account_deletion_email_outbox', 'event', 'outbox records email purpose');
select has_column('app_private', 'account_deletion_email_outbox', 'delivery_expires_at', 'delivery window is bounded');
select has_index('app_private', 'account_deletion_email_outbox', 'account_deletion_email_outbox_due_idx', 'due delivery has an index');
select has_function('public', 'claim_account_deletion_emails', array['integer'], 'claim RPC exists');
select has_function('public', 'finish_account_deletion_email', array['uuid','uuid','boolean','text','text'], 'finish RPC exists');
select has_function('app_private', 'enqueue_account_deletion_email', array[]::text[], 'state trigger function exists');
select has_trigger('public', 'account_deletion_requests', 'enqueue_account_deletion_email_after_insert', 'new requests are covered');
select has_trigger('public', 'account_deletion_requests', 'enqueue_account_deletion_email_after_status_change', 'completion is covered');
select is((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app_private' and c.relname = 'account_deletion_email_outbox'), true, 'outbox has RLS');
select ok(not has_table_privilege('anon', 'app_private.account_deletion_email_outbox', 'SELECT'), 'anon cannot read deletion email data');
select ok(not has_table_privilege('authenticated', 'app_private.account_deletion_email_outbox', 'SELECT'), 'users cannot read deletion email data');
select ok(not has_function_privilege('anon', 'public.claim_account_deletion_emails(integer)', 'EXECUTE'), 'anon cannot claim email');
select ok(has_function_privilege('service_role', 'public.claim_account_deletion_emails(integer)', 'EXECUTE'), 'service role can claim email');
select is(
  (select p.prosecdef from pg_proc p where p.oid = 'public.claim_account_deletion_emails(integer)'::regprocedure),
  false,
  'claim RPC preserves the service role as current_user'
);
select is(
  (select p.prosecdef from pg_proc p where p.oid = 'public.finish_account_deletion_email(uuid,uuid,boolean,text,text)'::regprocedure),
  false,
  'finish RPC preserves the service role as current_user'
);

insert into public.workspaces(id, name) values (
  '72000000-0000-4000-8000-000000000001',
  'Deletion Email Studio'
);
insert into public.account_deletion_requests(
  id, workspace_id, user_id, requested_by_user_id, email, status
) values (
  '73000000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'owner@example.com',
  'requested'
);
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 1, 'recorded request queues one email');
select is((select event from app_private.account_deletion_email_outbox), 'deletion_requested', 'request email has correct purpose');

update public.account_deletion_requests set notes = 'Owner refreshed details' where id = '73000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 1, 'non-state update does not duplicate email');

update public.account_deletion_requests set status = 'processing' where id = '73000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 1, 'processing does not claim completion');

update public.account_deletion_requests set status = 'completed', completed_at = now() where id = '73000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 2, 'completion queues a second email');
select is((select count(*)::integer from app_private.account_deletion_email_outbox where event = 'account_deleted'), 1, 'completion email has correct purpose');

update public.account_deletion_requests set status = 'completed' where id = '73000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 2, 'completion retry cannot duplicate email');

delete from public.account_deletion_requests where id = '73000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_deletion_email_outbox), 0, 'request deletion cascades private email data');

select * from finish();
rollback;
