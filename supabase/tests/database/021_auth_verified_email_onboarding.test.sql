begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(19);

select ok(not has_function_privilege('anon',
  'public.complete_onboarding(text,text,text,jsonb,jsonb,numeric,jsonb)', 'EXECUTE'),
  'anonymous callers cannot create workspaces');
select ok(has_function_privilege('authenticated',
  'public.complete_onboarding(text,text,text,jsonb,jsonb,numeric,jsonb)', 'EXECUTE'),
  'authenticated callers retain the existing onboarding entry point');

insert into auth.users(id, email, email_confirmed_at, phone_confirmed_at,
  created_at, raw_user_meta_data)
values
  ('92100000-0000-4000-8000-000000000001', null, null, now(), now(),
   '{"workloop_email_notice":"workloop-account-emails-2026-09-v1","workloop_email_updates":true}'),
  ('92100000-0000-4000-8000-000000000002', 'unverified-owner@example.com', null, null, now(), '{}'),
  ('92100000-0000-4000-8000-000000000003', '   ', now(), now(), now(), '{}'),
  ('92100000-0000-4000-8000-000000000004', null, null, now(), now(),
   '{"workloop_email_notice":"workloop-account-emails-2026-09-v1","workloop_email_updates":false}');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('92100000-0000-4000-8000-000000000101','92100000-0000-4000-8000-000000000001',now(),now()),
('92100000-0000-4000-8000-000000000102','92100000-0000-4000-8000-000000000002',now(),now()),
('92100000-0000-4000-8000-000000000103','92100000-0000-4000-8000-000000000003',now(),now());

set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
select throws_ok($$select public.complete_onboarding('Verified Test Studio','other',
  'verified-test-studio','[]','{}',0,null)$$, '28000',
  'Your sign-in is no longer active', 'missing identity remains blocked');

select set_config('request.jwt.claims',
  '{"sub":"92100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"92100000-0000-4000-8000-000000000101"}', true);
select throws_ok($$select public.complete_onboarding('Verified Test Studio','other',
  'verified-test-studio','[]','{}',0,null)$$, '42501',
  'Verify your account email before setting up your business',
  'a verified phone alone cannot call onboarding directly');
reset role;
select is((select count(*)::integer from public.workspace_members
  where user_id='92100000-0000-4000-8000-000000000001'),0,
  'rejected onboarding creates no partial workspace membership');
select is((select count(*)::integer from app_private.account_welcome_email_outbox
  where user_id='92100000-0000-4000-8000-000000000001'),0,
  'phone verification does not pretend an email welcome was sent');
select is((select count(*)::integer from app_private.learning_contacts
  where user_id='92100000-0000-4000-8000-000000000001'),0,
  'phone verification alone does not enroll an addressless email journey');

-- This is the same auth.users transition performed when Supabase verifies the
-- phone-first owner's initial email. Exercise the real existing triggers.
update auth.users set email='phone-owner@example.com', email_confirmed_at=now()
  where id='92100000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_welcome_email_outbox
  where user_id='92100000-0000-4000-8000-000000000001'),1,
  'initial email verification queues exactly one real welcome');
select is((select status from app_private.learning_contacts
  where user_id='92100000-0000-4000-8000-000000000001'),'active',
  'phone-first email confirmation honors the recorded signup choice');
select is((select count(*)::integer from app_private.learning_email_outbox o
  join app_private.learning_contacts c on c.id=o.contact_id
  where c.user_id='92100000-0000-4000-8000-000000000001'),9,
  'the existing nine-step account journey is scheduled after verification');

set local role authenticated;
select lives_ok($$select public.complete_onboarding('Verified Test Studio','other',
  'verified-test-studio','[]','{}',0,null)$$,
  'verified email reaches the existing transactional onboarding implementation');
reset role;
select is((select count(*)::integer from public.workspace_members
  where user_id='92100000-0000-4000-8000-000000000001'),1,
  'successful onboarding creates one workspace');
set local role authenticated;
select is(public.complete_onboarding('Verified Test Studio','other',
    'verified-test-studio','[]','{}',0,null),
  (select workspace_id from public.workspace_members
    where user_id='92100000-0000-4000-8000-000000000001'),
  'retry still returns the same existing workspace');
reset role;
update auth.users set email_confirmed_at=now()
  where id='92100000-0000-4000-8000-000000000001';
select is((select count(*)::integer from app_private.account_welcome_email_outbox
  where user_id='92100000-0000-4000-8000-000000000001'),1,
  'later account refresh does not duplicate the welcome');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"92100000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"92100000-0000-4000-8000-000000000102"}', true);
select throws_ok($$select public.complete_onboarding('Unverified Studio','other',
  'unverified-test-studio','[]','{}',0,null)$$, '42501',
  'Verify your account email before setting up your business',
  'merely having an unverified email address is not enough');
select set_config('request.jwt.claims',
  '{"sub":"92100000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1","session_id":"92100000-0000-4000-8000-000000000103"}', true);
select throws_ok($$select public.complete_onboarding('Blank Email Studio','other',
  'blank-email-studio','[]','{}',0,null)$$, '42501',
  'Verify your account email before setting up your business',
  'a timestamp without a usable email is not enough');
reset role;

update auth.users set email='optout-phone-owner@example.com', email_confirmed_at=now()
  where id='92100000-0000-4000-8000-000000000004';
select is((select status from app_private.learning_contacts
  where user_id='92100000-0000-4000-8000-000000000004'),'unsubscribed',
  'a phone-first signup opt-out remains respected after email verification');
select is((select count(*)::integer from app_private.learning_email_outbox o
  join app_private.learning_contacts c on c.id=o.contact_id
  where c.user_id='92100000-0000-4000-8000-000000000004'),0,
  'no tips or marketing sequence is queued for an opted-out phone-first owner');

insert into auth.mfa_factors(id,user_id,factor_type,status,secret)
  values('92200000-0000-4000-8000-000000000001',
    '92100000-0000-4000-8000-000000000001','totp','verified','test-only');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"92100000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"92100000-0000-4000-8000-000000000101"}', true);
select throws_ok($$select public.complete_onboarding('Verified Test Studio','other',
  'verified-test-studio','[]','{}',0,null)$$, '42501',
  'Multi-factor authentication is required',
  'email verification does not weaken the existing MFA requirement');
reset role;

select * from finish();
rollback;
