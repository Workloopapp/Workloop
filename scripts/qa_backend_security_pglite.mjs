// Disposable PostgreSQL compatibility harness, never a live-project runner.
// Uses actual core schema, live-derived RLS, and actual onboarding implementation.
// Auth is a minimal explicit fixture; this does not replace full Supabase replay.
import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const packageRoot = process.env.WORKLOOP_PGLITE_PATH;
if (!packageRoot) throw new Error('Set WORKLOOP_PGLITE_PATH to the installed @electric-sql/pglite directory');
const { PGlite } = await import(pathToFileURL(`${packageRoot}/dist/index.js`));
const { pgtap } = await import(pathToFileURL(`${packageRoot}/dist/pgtap/index.js`));
const db = new PGlite({ extensions: { pgtap } });
const read = path => fs.readFile(path, 'utf8');
try {
  await db.exec(await read('supabase/tests/fixtures/subscription_bootstrap.sql'));
  await db.exec("alter table auth.users add column banned_until timestamptz;");
  await db.exec(await read('supabase/migrations/20260530000000_core_schema_baseline.sql'));
  await db.exec(await read('supabase/migrations/20260530103326_slate_v1_schema_contract.sql'));
  await db.exec(await read('supabase/migrations/20260603195342_account_deletion_workflow.sql'));
  await db.exec(`alter table public.account_deletion_requests alter column workspace_id drop not null;
    alter table public.account_deletion_requests drop constraint account_deletion_requests_workspace_id_fkey;
    alter table public.account_deletion_requests add foreign key(workspace_id) references public.workspaces(id) on delete set null;`);
  await db.exec(`create function app_private.is_workspace_member(target_workspace_id uuid) returns boolean language sql security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.workspace_members where workspace_id=target_workspace_id and user_id=auth.uid())$$;
    create function app_private.workspace_has_no_members(target_workspace_id uuid) returns boolean language sql security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from public.workspace_members where workspace_id=target_workspace_id)$$;`);
  await db.exec(`create function public.current_account_deletion_pending() returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.account_deletion_requests where requested_by_user_id=auth.uid() and status in ('requested','processing'))$$;
    create function app_private.enqueue_notification_push() returns trigger language plpgsql as $$begin return new; end$$;
    grant select,insert,update,delete on all tables in schema public to authenticated,service_role;`);
  await db.exec(await read('supabase/tests/fixtures/security_boundary_policies.sql'));
  await db.exec(await read('supabase/migrations/20260912103515_validate_onboarding_working_hours.sql'));
  await db.exec(await read('supabase/migrations/20260905184601_require_verified_email_for_workspace_setup.sql'));
  await db.exec(await read('supabase/migrations/20260902172040_require_public_workspace_member.sql'));
  await db.exec(await read('supabase/migrations/20260912191519_restrict_workspace_bootstrap_to_onboarding.sql'));
  if (process.argv.includes('--sessions')) await db.exec(await read('supabase/migrations/20260912193144_account_deletion_and_active_session_boundaries.sql'));
  const tests = ['supabase/tests/database/042_workspace_bootstrap_security.test.sql'];
  if (process.argv.includes('--sessions')) tests.push('supabase/tests/database/043_account_deletion_sessions.test.sql','supabase/tests/database/044_public_active_owner.test.sql');
  for (const test of tests) {
    const result = await db.exec(await read(test));
    const lines = result.flatMap(r=>r.rows??[]).flatMap(Object.values).map(String).filter(s=>/^(ok |not ok |1\.\.|#)/m.test(s));
    console.log(test, '\n'+lines.join('\n'));
    if (lines.some(s=>/^not ok/m.test(s))) process.exitCode=1;
  }
} catch (error) { console.error(error.message,error.detail??'',error.where??''); process.exitCode=1; }
await db.close();
