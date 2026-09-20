begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(16);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  confirmation_token,
  recovery_token
) values
  (
    '10000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'quality-user-a@example.invalid',
    '',
    now(),
    now(),
    now(),
    '',
    ''
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'quality-user-b@example.invalid',
    '',
    now(),
    now(),
    now(),
    '',
    ''
  );

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('10000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000001',now(),now()),
('20000000-0000-4000-8000-000000000102','20000000-0000-4000-8000-000000000002',now(),now());

insert into public.workspaces (id, name) values
  ('11000000-0000-4000-8000-000000000001', 'Quality Workspace A'),
  ('22000000-0000-4000-8000-000000000002', 'Quality Workspace B');

insert into public.workspace_members (workspace_id, user_id) values
  (
    '11000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '22000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002'
  );

insert into public.contacts (id, workspace_id, name) values
  (
    '11100000-0000-4000-8000-000000000001',
    '11000000-0000-4000-8000-000000000001',
    'User A client'
  ),
  (
    '22200000-0000-4000-8000-000000000002',
    '22000000-0000-4000-8000-000000000002',
    'User B client'
  );

insert into public.workspace_payment_accounts(
  workspace_id,
  stripe_account_id
) values
  (
    '11000000-0000-4000-8000-000000000001',
    'acct_QualityWorkspaceA123'
  ),
  (
    '22000000-0000-4000-8000-000000000002',
    'acct_QualityWorkspaceB123'
  );

create temporary table quality_mutation_results (
  result_name text primary key,
  passed boolean not null
);
grant all on table quality_mutation_results to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000101"}',
  true
);

select is(
  (select count(*)::bigint from public.contacts),
  1::bigint,
  'User A sees only User A contacts'
);
select is(
  (select min(name) from public.contacts),
  'User A client',
  'User A cannot read User B content'
);

select is(
  (select count(*)::bigint from public.workspace_payment_accounts),
  1::bigint,
  'User A sees only User A payment account status'
);

select throws_ok(
  $$
    insert into public.workspace_payment_accounts(
      workspace_id,
      stripe_account_id
    ) values (
      '11000000-0000-4000-8000-000000000001',
      'acct_ForbiddenClientWrite123'
    )
  $$,
  '42501',
  null,
  'authenticated clients cannot write provider account state'
);

with changed as (
  update public.contacts
  set name = 'Cross-account tamper'
  where id = '22200000-0000-4000-8000-000000000002'
  returning id
)
select is(
  (select count(*)::bigint from changed),
  0::bigint,
  'cross-account updates affect no rows'
);

with removed as (
  delete from public.contacts
  where id = '22200000-0000-4000-8000-000000000002'
  returning id
)
select is(
  (select count(*)::bigint from removed),
  0::bigint,
  'cross-account deletes affect no rows'
);

do $$
begin
  begin
    insert into public.contacts (workspace_id, name)
    values (
      '22000000-0000-4000-8000-000000000002',
      'Forbidden foreign insert'
    );
    insert into quality_mutation_results values ('foreign_insert', false);
  exception when insufficient_privilege then
    insert into quality_mutation_results values ('foreign_insert', true);
  end;
end
$$;

select ok(
  (select passed from quality_mutation_results where result_name = 'foreign_insert'),
  'cross-account inserts are rejected'
);

insert into public.contacts (workspace_id, name)
values (
  '11000000-0000-4000-8000-000000000001',
  'User A second client'
);
select is(
  (select count(*)::bigint from public.contacts),
  2::bigint,
  'User A can insert into User A workspace'
);

reset role;
select is(
  (
    select name
    from public.contacts
    where id = '22200000-0000-4000-8000-000000000002'
  ),
  'User B client',
  'blocked cross-account mutations leave User B data unchanged'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"20000000-0000-4000-8000-000000000102"}',
  true
);
select is(
  (select count(*)::bigint from public.contacts),
  1::bigint,
  'User B sees only User B contacts'
);

reset role;
insert into auth.mfa_factors (
  id,
  user_id,
  friendly_name,
  factor_type,
  status,
  created_at,
  updated_at,
  secret
) values (
  '20000000-0000-4000-8000-000000000099',
  '20000000-0000-4000-8000-000000000002',
  'Quality authenticator',
  'totp',
  'verified',
  now(),
  now(),
  'quality-secret'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"20000000-0000-4000-8000-000000000102"}',
  true
);
select is(
  (select count(*)::bigint from public.contacts),
  0::bigint,
  'an opted-in user cannot access data with an AAL1 session'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2","session_id":"20000000-0000-4000-8000-000000000102"}',
  true
);
select is(
  (select count(*)::bigint from public.contacts),
  1::bigint,
  'an opted-in user regains tenant-scoped access with an AAL2 session'
);

reset role;
set local role anon;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000000',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000000","role":"anon"}',
  true
);
select throws_ok(
  'select count(*) from public.contacts',
  '42501',
  null,
  'anonymous callers have no private-table read privilege'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.create_booking_workflow(jsonb)',
    'EXECUTE'
  ),
  'anonymous callers cannot execute booking workflow'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_booking_workflow(jsonb)',
    'EXECUTE'
  ),
  'authenticated callers can execute booking workflow wrapper'
);
select ok(
  (
    select rolbypassrls
    from pg_roles
    where rolname = 'service_role'
  ),
  'service role retains the explicit backend-only RLS boundary'
);

select * from finish();
rollback;
