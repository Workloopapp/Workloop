begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(12);

-- Exercise the real trigger without customer fixtures or delivery triggers.
create temporary table notification_route_probe
  (like public.notifications including defaults);
create trigger route_notification_probe before insert
  on notification_route_probe for each row
  execute function app_private.route_notification_to_entity();

select lives_ok($$
  insert into notification_route_probe(workspace_id, type, title, body, deep_link)
  values ('82000000-0000-4000-8000-000000000099', 'morning_digest', 'Brief', 'Ready', '/today')
$$, 'morning briefs do not abort the automation transaction');
select is((select deep_link from notification_route_probe where type = 'morning_digest'),
  '/today', 'morning brief retains its destination');
select lives_ok($$
  insert into notification_route_probe(workspace_id, type, title, body, deep_link)
  values ('82000000-0000-4000-8000-000000000099', 'weekly_summary', 'Summary', 'Ready', '/business')
$$, 'general notifications pass through safely');
select is((select deep_link from notification_route_probe where type = 'weekly_summary'),
  '/business', 'general notifications retain their destination');
select is((select prosecdef from pg_proc where oid =
  'public.record_resend_webhook_event(text,text,text,timestamp with time zone)'::regprocedure),
  false, 'receipt ingestion evaluates the service-role guard as the caller');
select ok(not has_function_privilege('anon',
  'public.record_resend_webhook_event(text,text,text,timestamp with time zone)', 'execute'),
  'anonymous callers cannot ingest receipts');
select ok(not has_function_privilege('authenticated',
  'public.record_resend_webhook_event(text,text,text,timestamp with time zone)', 'execute'),
  'app users cannot ingest receipts');

set local role service_role;
select is(public.record_resend_webhook_event('notification-reporting-regression-delivered',
  'regression-provider-message', 'email.delivered', '2026-09-04T12:00:00Z'),
  true, 'verified provider receipt is accepted as service_role');
select is(public.record_resend_webhook_event('notification-reporting-regression-delivered',
  'regression-provider-message', 'email.delivered', '2026-09-04T12:00:00Z'),
  false, 'replayed receipt is idempotent');
select is((select count(*)::integer from reporting.resend_webhook_events
  where svix_id = 'notification-reporting-regression-delivered'), 1,
  'a provider event has one ledger row after replay');
select throws_ok($$select public.record_resend_webhook_event('notification-reporting-regression-invalid',
  'regression-provider-message', 'invalid.event', now())$$, '23514', null,
  'unsupported provider events cannot pollute delivery reporting');
reset role;
select throws_ok($$select public.record_resend_webhook_event('notification-reporting-regression-admin',
  'regression-provider-message', 'email.delivered', now())$$, 'P0001', 'service role required',
  'the existing explicit caller guard remains enforced');

select * from finish();
rollback;
