begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(20);

select has_table('app_private', 'operational_alerts', 'operational alerts are private');
select is(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app_private' and c.relname = 'operational_alerts'),
  true,
  'operational alerts have RLS'
);
select ok(not has_table_privilege('anon', 'app_private.operational_alerts', 'SELECT'), 'anon cannot read alerts');
select ok(not has_table_privilege('authenticated', 'app_private.operational_alerts', 'SELECT'), 'users cannot read alerts');
select has_function('public', 'current_account_deletion_pending', array[]::text[], 'deletion-state RPC exists');
select ok(not has_function_privilege('anon', 'public.current_account_deletion_pending()', 'EXECUTE'), 'anon cannot inspect deletion state');
select ok(has_function_privilege('authenticated', 'public.current_account_deletion_pending()', 'EXECUTE'), 'signed-in user can inspect own deletion state');
select has_function('public', 'run_workloop_automations', array[]::text[], 'automation RPC exists');
select ok(not has_function_privilege('authenticated', 'public.run_workloop_automations()', 'EXECUTE'), 'users cannot run privileged automations');
select ok(has_function_privilege('service_role', 'public.run_workloop_automations()', 'EXECUTE'), 'worker can run automations');
select has_function('app_private', 'run_business_automations', array['timestamp with time zone'], 'private automation implementation exists');
select has_function('public', 'claim_operational_alerts', array['integer'], 'alert claim RPC exists');
select ok(not has_function_privilege('authenticated', 'public.claim_operational_alerts(integer)', 'EXECUTE'), 'users cannot claim alerts');
select ok(has_function_privilege('service_role', 'public.claim_operational_alerts(integer)', 'EXECUTE'), 'worker can claim alerts');

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,created_at, updated_at)
values ('81000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'automation@example.com','',now(),now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('81000000-0000-4000-8000-000000000101','81000000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id, name)
values ('82000000-0000-4000-8000-000000000001', 'Automation Studio');
insert into public.workspace_members(workspace_id, user_id)
values ('82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id, timezone)
values ('82000000-0000-4000-8000-000000000001', 'UTC');
insert into public.notification_preferences(workspace_id, all_notifications, booking_request, invoice_overdue, morning_digest)
values ('82000000-0000-4000-8000-000000000001', true, true, true, true);
insert into public.account_deletion_requests(
  id, workspace_id, user_id, requested_by_user_id, email, status
) values (
  '83000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  'automation@example.com',
  'requested'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"81000000-0000-4000-8000-000000000101"}',true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(public.current_account_deletion_pending(), true, 'owner sees deletion in progress');
reset role;

insert into public.booking_requests(
  id, workspace_id, name, phone, email, status, created_at
) values (
  '84000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  'Amina',
  '07123456789',
  'amina@example.com',
  'pending',
  '2026-08-16 00:00:00+00'
);
insert into public.invoices(
  id, workspace_id, invoice_number, type, status, issue_date, due_date, total, amount_paid
) values (
  '85000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  'PAY-AUTO-1',
  'invoice',
  'sent',
  '2026-08-01',
  '2026-08-10',
  120,
  20
);
insert into public.appointments(
  id, workspace_id, title, start_time, end_time, status
) values (
  '86000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  'Automation booking',
  '2026-08-16 10:00:00+00',
  '2026-08-16 11:00:00+00',
  'scheduled'
);
insert into public.tasks(id, workspace_id, title, status)
values ('87000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 'Follow up', 'open');
insert into public.push_tokens(id, workspace_id, user_id, token, platform, last_seen_at)
values ('88000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'stale-token', 'ios', '2026-01-01 00:00:00+00');

select app_private.run_business_automations('2026-08-16 07:15:00+00');
select is((select count(*)::integer from public.notifications where type = 'booking_request'), 1, 'waiting request creates one notification');
select is((select count(*)::integer from public.notifications where type = 'invoice_overdue'), 1, 'overdue payment creates one notification');
select is((select count(*)::integer from public.notifications where type = 'morning_digest'), 1, 'local morning creates one brief');

select app_private.run_business_automations('2026-08-16 07:30:00+00');
select is((select count(*)::integer from public.notifications), 3, 'automation rerun is idempotent');
select is((select count(*)::integer from public.push_tokens), 0, 'stale device tokens are removed');

select * from finish();
rollback;

