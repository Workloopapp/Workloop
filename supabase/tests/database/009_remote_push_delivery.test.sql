begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(35);

select has_table('app_private', 'push_delivery_outbox', 'push outbox is private');
select has_column('public', 'push_tokens', 'disabled_at', 'tokens can be disabled safely');
select is(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app_private' and c.relname = 'push_delivery_outbox'),
  true,
  'push outbox has RLS'
);
select ok(not has_table_privilege('anon', 'app_private.push_delivery_outbox', 'SELECT'), 'anon cannot read push outbox');
select ok(not has_table_privilege('authenticated', 'app_private.push_delivery_outbox', 'SELECT'), 'users cannot read push outbox');
select has_function('public', 'register_push_token', array['uuid','text','text','text'], 'registration RPC exists');
select has_function('public', 'unregister_push_token', array['text'], 'unregister RPC exists');
select has_function('public', 'claim_push_deliveries', array['integer'], 'claim RPC exists');
select has_function('public', 'finish_push_delivery', array['uuid','uuid','text','text','text','boolean'], 'finish RPC exists');
select has_function('app_private', 'route_notification_to_entity', array[]::text[], 'notification route trigger exists');
select ok(not has_function_privilege('anon', 'public.register_push_token(uuid,text,text,text)', 'EXECUTE'), 'anon cannot register tokens');
select ok(has_function_privilege('authenticated', 'public.register_push_token(uuid,text,text,text)', 'EXECUTE'), 'signed-in user can register a token');
select ok(not has_table_privilege('authenticated', 'public.push_tokens', 'INSERT'), 'users cannot bypass token registration');
select ok(not has_table_privilege('authenticated', 'public.push_tokens', 'UPDATE'), 'users cannot reassign tokens directly');
select ok(not has_table_privilege('authenticated', 'public.push_tokens', 'DELETE'), 'users cannot delete tokens directly');
select ok(not has_function_privilege('authenticated', 'public.claim_push_deliveries(integer)', 'EXECUTE'), 'users cannot claim push work');
select ok(has_function_privilege('service_role', 'public.claim_push_deliveries(integer)', 'EXECUTE'), 'worker can claim push work');
select ok(has_function_privilege('service_role', 'public.finish_push_delivery(uuid,uuid,text,text,text,boolean)', 'EXECUTE'), 'worker can finish push work');
select ok(not has_function_privilege('anon', 'app_private.route_notification_to_entity()', 'EXECUTE'), 'anon cannot execute the route trigger function');
select ok(not has_function_privilege('authenticated', 'app_private.route_notification_to_entity()', 'EXECUTE'), 'users cannot execute the route trigger function');

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,created_at, updated_at)
values ('91000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push@example.com','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values ('91000000-0000-4000-8000-000000000011','91000000-0000-4000-8000-000000000001',now(),now());
insert into public.workspaces(id, name)
values ('92000000-0000-4000-8000-000000000001', 'Push Studio');
insert into public.workspace_members(workspace_id, user_id)
values ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001');
insert into public.workspace_settings(workspace_id, timezone)
values ('92000000-0000-4000-8000-000000000001', 'Europe/London');
insert into public.notification_preferences(workspace_id, quiet_hours_enabled)
values ('92000000-0000-4000-8000-000000000001', false);
insert into public.business_profiles(workspace_id, handle, booking_mode)
values (
  '92000000-0000-4000-8000-000000000001',
  'push-studio',
  'manual'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"91000000-0000-4000-8000-000000000011"}', true);
select lives_ok(
  $$select public.register_push_token(
    '92000000-0000-4000-8000-000000000001',
    'fcm-token-12345678901234567890',
    'ios',
    '6'
  )$$,
  'member can register a device token'
);
reset role;

select is((select count(*)::integer from public.push_tokens), 1, 'one device token is registered');
select is((select app_build from public.push_tokens), '6', 'installed build is recorded');

insert into public.notifications(workspace_id, type, title, body, deep_link)
values (
  '92000000-0000-4000-8000-000000000001',
  'booking_request',
  'Private booking title',
  'Private booking detail',
  '/booking-requests'
);
select is((select count(*)::integer from app_private.push_delivery_outbox), 1, 'notification queues one delivery per active device');

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table claimed_push_delivery as
select * from public.claim_push_deliveries(10);
reset role;

select is((select count(*)::integer from claimed_push_delivery), 1, 'worker claims queued delivery');
select is((select deep_link from claimed_push_delivery), '/booking-requests', 'claimed delivery preserves a safe route');

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select ok(
  public.finish_push_delivery(
    (select delivery_id from claimed_push_delivery),
    (select delivery_lease_token from claimed_push_delivery),
    'sent',
    'projects/workloop/messages/1',
    null,
    false
  ),
  'worker can finish the claimed delivery'
);
reset role;

select is((select status from app_private.push_delivery_outbox), 'sent', 'delivery is durably marked sent');

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table created_public_request as
select * from public.create_public_booking_request_v2(
  '92000000-0000-4000-8000-000000000001',
  'Push customer',
  '07123456789',
  'push@example.test',
  null,
  'Tomorrow at 10:00',
  null,
  repeat('a', 64),
  '93000000-0000-4000-8000-000000000001'
);
reset role;

select is(
  (select outcome from created_public_request),
  'created',
  'public booking workflow creates a new request'
);
select is(
  (
    select notification.deep_link
      from public.notifications notification
     where notification.type = 'booking_request'
       and notification.deep_link like '/booking-requests/%'
     order by notification.created_at desc
     limit 1
  ),
  '/booking-requests/' ||
    (select booking_request_id::text from created_public_request),
  'new public request notification targets the exact request'
);
select is(
  (
    select count(*)::integer
      from app_private.push_delivery_outbox delivery
      join public.notifications notification
        on notification.id = delivery.notification_id
     where notification.deep_link = '/booking-requests/' ||
       (select booking_request_id::text from created_public_request)
       and delivery.status = 'pending'
  ),
  1,
  'new public request queues an eligible push delivery'
);
select is(
  (
    select notification.body
      from public.notifications notification
     where notification.deep_link = '/booking-requests/' ||
       (select booking_request_id::text from created_public_request)
  ),
  'Push customer requested a booking.',
  'in-app notification retains useful detail while APNs copy is redacted'
);

update public.notification_preferences
set booking_request = false
where workspace_id = '92000000-0000-4000-8000-000000000001';
insert into public.notifications(workspace_id, type, title, body, deep_link)
values (
  '92000000-0000-4000-8000-000000000001',
  'booking_request',
  'Muted title',
  'Muted detail',
  '/booking-requests'
);
select is((select count(*)::integer from app_private.push_delivery_outbox), 2, 'disabled preference does not queue another push');

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"91000000-0000-4000-8000-000000000011"}', true);
select ok(public.unregister_push_token('fcm-token-12345678901234567890'), 'owner can unregister current device');
reset role;
select is((select count(*)::integer from public.push_tokens), 0, 'unregister removes the device token');

select * from finish();
rollback;
