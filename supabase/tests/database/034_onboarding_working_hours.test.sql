begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(11);
insert into auth.users(id, email, email_confirmed_at, created_at)
values ('93400000-0000-4000-8000-000000000001','hours-audit@example.com',now(),now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('93400000-0000-4000-8000-000000000101','93400000-0000-4000-8000-000000000001',now(),now());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"93400000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"93400000-0000-4000-8000-000000000101"}', true);
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"open":"09:00","close":"08:00"}}',0,null)$$,
  '22023','Mon: closing time must be after opening time.','reversed legacy hours cannot complete');
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Monday":{"enabled":true,"blocks":[{"start":"09:00","end":"09:00"}]}}',0,null)$$,
  '22023','Monday: closing time must be after opening time.','zero duration cannot complete');
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"open":"25:00","close":"17:00"}}',0,null)$$,
  '22023','Mon: use valid times such as 09:00.','invalid clock times cannot complete');
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"close":"17:00"}}',0,null)$$,
  '22023','Mon: use valid times such as 09:00.','missing active range endpoint cannot complete');
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"blocks":[]}}',0,null)$$,
  '22023','Mon: add at least one working block.','empty active blocks cannot complete');
select throws_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"blocks":[{"start":"12:00","end":"17:00"},{"start":"09:00","end":"13:00"}]}}',0,null)$$,
  '22023','Mon: working blocks must not overlap.','unordered overlapping blocks cannot complete');
select is((select count(*)::integer from public.workspace_members
  where user_id='93400000-0000-4000-8000-000000000001'),0,
  'invalid hours leave no membership');
select is((select count(*)::integer from public.business_profiles where handle='hours-audit'),0,
  'invalid hours do not reserve a handle');
select lives_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"blocks":[{"start":"12:00","end":"17:00"},{"start":"09:00","end":"12:00"}]},"Sun":{"enabled":false,"open":"bad","close":"bad"}}',0,null)$$,
  'touching unordered ranges and closed drafts are accepted');
select is((select working_hours #>> '{Mon,blocks,0,start}' from public.workspace_settings),
  '12:00','valid draft is persisted without reordering or silent changes');
select lives_ok($$select public.complete_onboarding('Hours Studio','Other','hours-audit',
  '[]','{"Mon":{"enabled":true,"open":"09:00","close":"08:00"}}',0,null)$$,
  'a retry of successful onboarding returns its existing workspace without rewriting hours');
reset role;
select * from finish();
rollback;
