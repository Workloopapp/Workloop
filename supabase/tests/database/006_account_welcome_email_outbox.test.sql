begin;
select plan(18);

select has_table('app_private', 'account_welcome_email_outbox', 'account welcome outbox exists');
select has_column('app_private', 'account_welcome_email_outbox', 'user_id', 'outbox links auth user');
select has_column('app_private', 'account_welcome_email_outbox', 'recipient_email', 'outbox stores recipient');
select has_column('app_private', 'account_welcome_email_outbox', 'delivery_expires_at', 'delivery window is bounded');
select has_function('public', 'claim_account_welcome_emails', array['integer'], 'claim RPC exists');
select has_function('public', 'finish_account_welcome_email', array['uuid','uuid','boolean','text','text'], 'finish RPC exists');
select has_function('app_private', 'enqueue_account_welcome_email', array[]::text[], 'verification trigger function exists');
select has_trigger('auth', 'users', 'enqueue_account_welcome_email_after_insert', 'confirmed provider signups are covered');
select has_trigger('auth', 'users', 'enqueue_account_welcome_email_after_verification', 'email verification is covered');
select is((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app_private' and c.relname = 'account_welcome_email_outbox'), true, 'outbox has RLS');
select table_privs_are('app_private', 'account_welcome_email_outbox', 'anon', array[]::text[], 'anon has no outbox access');
select table_privs_are('app_private', 'account_welcome_email_outbox', 'authenticated', array[]::text[], 'authenticated has no outbox access');
select function_privs_are('public', 'claim_account_welcome_emails', array['integer'], 'anon', array[]::text[], 'anon cannot claim email');
select function_privs_are('public', 'finish_account_welcome_email', array['uuid','uuid','boolean','text','text'], 'authenticated', array[]::text[], 'users cannot finish email');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@example.com', '', null, now(), now());
select is((select count(*)::integer from app_private.account_welcome_email_outbox), 0, 'unverified signup does not queue welcome');

update auth.users set email_confirmed_at = now() where id = '10000000-0000-0000-0000-000000000001';
select is((select count(*)::integer from app_private.account_welcome_email_outbox), 1, 'first verification queues one welcome');

update auth.users set email_confirmed_at = now() where id = '10000000-0000-0000-0000-000000000001';
select is((select count(*)::integer from app_private.account_welcome_email_outbox), 1, 'later updates do not duplicate welcome');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'provider@example.com', '', now(), now(), now());
select is((select count(*)::integer from app_private.account_welcome_email_outbox), 2, 'already-confirmed provider signup queues welcome');

select * from finish();
rollback;
