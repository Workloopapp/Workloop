begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(19);

select ok(not (select prosecdef from pg_proc where oid =
  'app_private.complete_onboarding_implementation(text,text,text,jsonb,jsonb,numeric,jsonb)'::regprocedure),
  'the private onboarding implementation retains SECURITY INVOKER');
select ok(not has_function_privilege('authenticated',
  'app_private.complete_onboarding_implementation(text,text,text,jsonb,jsonb,numeric,jsonb)', 'EXECUTE'),
  'clients cannot bypass the guarded onboarding wrapper');
select ok(not has_function_privilege('anon',
  'public.complete_onboarding(text,text,text,jsonb,jsonb,numeric,jsonb)', 'EXECUTE'),
  'anonymous callers still cannot complete onboarding');

insert into auth.users(id, email, email_confirmed_at, created_at)
values
  ('93200000-0000-4000-8000-000000000001', 'descriptions@example.com', now(), now()),
  ('93200000-0000-4000-8000-000000000002', 'description-rollback@example.com', now(), now());

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('93200000-0000-4000-8000-000000000101','93200000-0000-4000-8000-000000000001',now(),now()),
('93200000-0000-4000-8000-000000000102','93200000-0000-4000-8000-000000000002',now(),now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"93200000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"93200000-0000-4000-8000-000000000101"}', true);
select lives_ok($$select public.complete_onboarding(
  'Description Studio', 'Other', 'description-studio',
  jsonb_build_array(
    jsonb_build_object('name','Multiline','duration_mins',60,'price',45,
      'description', E'\t  First line\n  Second line  \r\n'),
    jsonb_build_object('name','Absent','duration_mins',30,'price',0),
    jsonb_build_object('name','Null','duration_mins',30,'price',0,'description',null),
    jsonb_build_object('name','Empty','duration_mins',30,'price',0,'description',''),
    jsonb_build_object('name','Blank','duration_mins',30,'price',0,'description',E' \n\t\r ')
  ), '{}', 0,
  '{"client_name":"Alex","service_name":"Multiline","start_time":"2030-01-10T10:00:00Z","end_time":"2030-01-10T11:00:00Z"}'
)$$, 'verified onboarding saves optional service descriptions in its transaction');

select is((select description from public.services where name='Multiline'),
  E'First line\n  Second line',
  'outer whitespace is trimmed while meaningful internal line breaks and spaces remain');
select is((select description from public.services where name='Absent'), null::text,
  'older clients may omit the description');
select is((select description from public.services where name='Null'), null::text,
  'explicit JSON null remains SQL null');
select is((select description from public.services where name='Empty'), null::text,
  'an empty optional description becomes null');
select is((select description from public.services where name='Blank'), null::text,
  'whitespace-only descriptions become null');

select is(public.complete_onboarding('Description Studio', 'Other', 'description-studio',
  '[{"name":"Multiline","duration_mins":60,"price":45,"description":"Overwrite attempt"}]',
  '{}',0,null),
  (select workspace_id from public.workspace_members
    where user_id='93200000-0000-4000-8000-000000000001'),
  'a successful onboarding retry returns the original workspace');
select is((select description from public.services where name='Multiline'),
  E'First line\n  Second line',
  'retry preserves the originally committed description');
select is((select count(*)::integer from public.services), 5,
  'retry does not duplicate or replace the original services');
select is((select count(*)::integer from public.appointments), 1,
  'the initial booking remains part of the original atomic onboarding');

select set_config('request.jwt.claims',
  '{"sub":"93200000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"93200000-0000-4000-8000-000000000102"}', true);
select throws_ok($$select public.complete_onboarding(
  'Rollback Description Studio','Other','rollback-description-studio',
  '[{"name":"Would roll back","duration_mins":60,"price":30,"description":"Must not survive"},
    {"name":"Invalid later row","duration_mins":0,"price":10}]', '{}',0,null
)$$, 'P0001', 'A service contains invalid values',
  'a later invalid service still rejects the whole onboarding transaction');
select throws_ok($$select public.complete_onboarding(
  'Rollback Description Studio','Other','rollback-description-studio',
  '[{"name":"Too short","duration_mins":4,"price":10,"description":"Still invalid"}]',
  '{}',0,null
)$$, '23514',
  'new row for relation "services" violates check constraint "services_duration_mins_check"',
  'the existing table constraint still rejects durations below five minutes through onboarding');
reset role;
select is((select count(*)::integer from public.workspace_members
  where user_id='93200000-0000-4000-8000-000000000002'), 0,
  'failed onboarding leaves no workspace membership');
select is((select count(*)::integer from public.services where name='Would roll back'), 0,
  'the earlier service and its description roll back after a later failure');
select is((select count(*)::integer from public.business_profiles
  where handle='rollback-description-studio'), 0,
  'failed onboarding does not reserve the public profile handle');

set local role authenticated;
select is((select count(*)::integer from public.services where name='Multiline'), 0,
  'another authenticated account cannot read the saved service description');
reset role;

select * from finish();
rollback;
