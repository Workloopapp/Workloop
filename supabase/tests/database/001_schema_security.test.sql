begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(54);

select has_table('public', table_name, table_name || ' exists')
from unnest(array[
  'workspaces',
  'workspace_members',
  'workspace_settings',
  'contacts',
  'services',
  'service_add_ons',
  'appointments',
  'appointment_items',
  'invoices',
  'invoice_line_items',
  'tasks',
  'business_profiles',
  'booking_requests',
  'booking_request_items',
  'notifications',
  'notification_preferences',
  'push_tokens',
  'calendar_sync_accounts',
  'account_deletion_requests',
  'task_checklist_items',
  'expenses',
  'account_deletion_audit',
  'notes',
  'workspace_payment_accounts',
  'payment_transactions',
  'payment_refunds'
]) as expected(table_name);

select is(
  (
    select count(*)::bigint
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'workspaces',
        'workspace_members',
        'workspace_settings',
        'contacts',
        'services',
        'service_add_ons',
        'appointments',
        'appointment_items',
        'invoices',
        'invoice_line_items',
        'tasks',
        'business_profiles',
        'booking_requests',
        'booking_request_items',
        'notifications',
        'notification_preferences',
        'push_tokens',
        'calendar_sync_accounts',
        'account_deletion_requests',
        'task_checklist_items',
        'expenses',
        'account_deletion_audit',
        'notes',
        'workspace_payment_accounts',
        'payment_transactions',
        'payment_refunds'
      ])
      and not relation.relrowsecurity
  ),
  0::bigint,
  'every public Workloop data table has RLS enabled'
);

select is(
  (
    select count(*)::bigint
    from information_schema.table_privileges
    where table_schema = 'public'
      and lower(grantee) in ('anon', 'public')
      and table_name = any(array[
        'workspaces',
        'workspace_members',
        'workspace_settings',
        'contacts',
        'services',
        'service_add_ons',
        'appointments',
        'appointment_items',
        'invoices',
        'invoice_line_items',
        'tasks',
        'business_profiles',
        'booking_requests',
        'booking_request_items',
        'notifications',
        'notification_preferences',
        'push_tokens',
        'calendar_sync_accounts',
        'account_deletion_requests',
        'task_checklist_items',
        'expenses',
        'account_deletion_audit',
        'notes',
        'workspace_payment_accounts',
        'payment_transactions',
        'payment_refunds'
      ])
  ),
  0::bigint,
  'anonymous clients have no direct table privileges'
);

select is(
  (
    select count(*)::bigint
    from information_schema.table_privileges
    where table_schema = 'app_private'
      and lower(grantee) in ('anon', 'authenticated', 'public')
  ),
  0::bigint,
  'client roles have no private-table privileges'
);

select is(
  (
    select count(*)::bigint
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'workspaces',
        'workspace_members',
        'contacts',
        'services',
        'service_add_ons',
        'appointments',
        'appointment_items',
        'invoices',
        'invoice_line_items',
        'tasks',
        'business_profiles',
        'booking_requests',
        'booking_request_items',
        'notifications',
        'task_checklist_items',
        'expenses',
        'notes',
        'workspace_payment_accounts',
        'payment_transactions',
        'payment_refunds'
      ])
      and not exists (
        select 1
        from pg_constraint constraint_row
        where constraint_row.conrelid = relation.oid
          and constraint_row.contype = 'p'
      )
  ),
  0::bigint,
  'every row-identity table has a primary key'
);

select ok(
  to_regprocedure('public.create_booking_workflow(jsonb)') is not null,
  'authenticated booking workflow wrapper exists'
);
select ok(
  to_regprocedure('public.complete_booking_workflow(jsonb)') is not null,
  'authenticated completion workflow wrapper exists'
);
select ok(
  to_regprocedure('public.create_task_workflow(jsonb)') is not null,
  'authenticated task workflow wrapper exists'
);
select ok(
  to_regprocedure('app_private.create_booking_workflow(jsonb)') is not null,
  'private booking implementation exists'
);
select ok(
  to_regprocedure('app_private.complete_booking_workflow(jsonb)') is not null,
  'private completion implementation exists'
);
select ok(
  to_regprocedure(
    'public.claim_stripe_webhook_event(text,text,text,boolean,jsonb)'
  ) is not null,
  'service-only Stripe webhook claim function exists'
);
select ok(
  to_regprocedure(
    'public.finish_stripe_webhook_event(text,text,text)'
  ) is not null,
  'service-only Stripe webhook completion function exists'
);

select ok(
  to_regprocedure('app_private.current_user_meets_mfa_policy()') is not null,
  'opt-in MFA enforcement helper exists'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and policyname = 'Verified MFA users require AAL2'
      and permissive = 'RESTRICTIVE'
      and roles @> array['authenticated'::name]
  ),
  25::bigint,
  'every authenticated application table has the restrictive MFA policy'
);

select ok(
  has_function_privilege(
    'authenticated',
    'app_private.current_user_meets_mfa_policy()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'app_private.current_user_meets_mfa_policy()',
    'EXECUTE'
  ),
  'only authenticated clients can call the current-user MFA helper'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app_private.assign_invoice_number()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.clear_inactive_task_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_task_completion_timestamp()',
    'EXECUTE'
  ),
  'trigger-only functions are not callable client RPCs'
);

select is(
  (
    select count(*)::bigint
    from information_schema.table_privileges
    where table_schema = 'app_private'
      and lower(grantee) in ('anon', 'authenticated', 'public')
      and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  0::bigint,
  'private workflow state is outside the Data API roles'
);

select is(
  (
    select count(*)::bigint
    from pg_constraint constraint_row
    join pg_class relation on relation.oid = constraint_row.conrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'appointments',
        'invoices',
        'tasks',
        'notes',
        'booking_requests',
        'invoice_line_items',
        'task_checklist_items'
      )
      and constraint_row.contype = 'f'
      and constraint_row.conname like '%workspace_%_fk'
  ),
  12::bigint,
  'tenant-aware relationship foreign keys are present'
);

select is(
  (
    select count(*)::bigint
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relname = any(array[
        'payment_counters',
        'workflow_idempotency',
        'stripe_webhook_events'
      ])
      and not relation.relrowsecurity
  ),
  0::bigint,
  'private payment and workflow ledgers have defence-in-depth RLS'
);

select is(
  (
    select count(*)::bigint
    from information_schema.table_privileges
    where table_schema = 'app_private'
      and table_name = any(array[
        'payment_counters',
        'workflow_idempotency',
        'stripe_webhook_events'
      ])
      and lower(grantee) in ('anon', 'authenticated', 'public')
      and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  0::bigint,
  'client roles have no private ledger DML grants'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname = 'app_private'
      and policyname = any(array[
        'payment_counters_deny_client_access',
        'workflow_idempotency_deny_client_access',
        'stripe_webhook_events_deny_client_access'
      ])
      and cmd = 'ALL'
      and roles @> array['anon'::name, 'authenticated'::name]
      and qual = 'false'
      and with_check = 'false'
  ),
  3::bigint,
  'private ledgers explicitly deny all client-role access'
);

select ok(
  has_table_privilege(
    'service_role',
    'app_private.payment_counters',
    'SELECT'
  )
  and has_table_privilege(
    'service_role',
    'app_private.payment_counters',
    'INSERT'
  )
  and has_table_privilege(
    'service_role',
    'app_private.payment_counters',
    'UPDATE'
  )
  and has_table_privilege(
    'service_role',
    'app_private.stripe_webhook_events',
    'SELECT'
  )
  and has_table_privilege(
    'service_role',
    'app_private.stripe_webhook_events',
    'INSERT'
  )
  and has_table_privilege(
    'service_role',
    'app_private.stripe_webhook_events',
    'UPDATE'
  ),
  'service role retains the private ledger grants used by Edge Functions'
);

select ok(
  public.claim_stripe_webhook_event(
    'evt_retry_contract',
    'acct_contract',
    'payment_intent.succeeded',
    false,
    '{"id":"evt_retry_contract"}'::jsonb
  ),
  'a new Stripe event is claimed'
);

select isnt(
  public.claim_stripe_webhook_event(
    'evt_retry_contract',
    'acct_contract',
    'payment_intent.succeeded',
    false,
    '{"id":"evt_retry_contract"}'::jsonb
  ),
  true,
  'a concurrently processing Stripe event is not double-claimed'
);

select lives_ok(
  $$select public.finish_stripe_webhook_event(
    'evt_retry_contract', 'failed', 'contract failure'
  )$$,
  'a failed Stripe attempt is recorded'
);

select ok(
  public.claim_stripe_webhook_event(
    'evt_retry_contract',
    'acct_contract',
    'payment_intent.succeeded',
    false,
    '{"id":"evt_retry_contract"}'::jsonb
  ),
  'a failed Stripe event can be reclaimed for retry'
);

select is(
  (
    select attempt_count
    from app_private.stripe_webhook_events
    where stripe_event_id = 'evt_retry_contract'
  ),
  2,
  'Stripe webhook attempts are counted'
);

select lives_ok(
  $$select public.finish_stripe_webhook_event(
    'evt_retry_contract', 'processed', null
  )$$,
  'a retried Stripe event can finish successfully'
);

select isnt(
  public.claim_stripe_webhook_event(
    'evt_retry_contract',
    'acct_contract',
    'payment_intent.succeeded',
    false,
    '{"id":"evt_retry_contract"}'::jsonb
  ),
  true,
  'a processed Stripe event remains deduplicated'
);

select * from finish();
rollback;
