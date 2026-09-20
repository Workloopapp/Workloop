create schema if not exists reporting;

comment on schema reporting is
  'Private, aggregate-only founder reporting. Not exposed through the Workloop Data API.';

revoke all on schema reporting from public, anon, authenticated;

do $role$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'workloop_reporting_reader'
  ) then
    create role workloop_reporting_reader
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noreplication
      nobypassrls;
  end if;
end
$role$;

create table if not exists reporting.excluded_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 120),
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists reporting.external_daily_metrics (
  metric_date date not null,
  source text not null check (
    source in ('app_store_connect', 'testflight')
  ),
  category text not null check (char_length(category) between 1 and 80),
  metric_name text not null check (char_length(metric_name) between 1 and 120),
  metric_value numeric not null,
  dimension_type text not null default 'all'
    check (char_length(dimension_type) between 1 and 80),
  dimension_value text not null default 'all'
    check (char_length(dimension_value) between 1 and 160),
  collected_at timestamptz not null default clock_timestamp(),
  primary key (
    metric_date,
    source,
    category,
    metric_name,
    dimension_type,
    dimension_value
  ),
  check (metric_date between date '2024-01-01' and date '2100-01-01')
);

create table if not exists reporting.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null check (
    source in ('app_store_connect', 'testflight')
  ),
  status text not null check (
    status in ('succeeded', 'failed', 'not_configured')
  ),
  started_at timestamptz not null,
  completed_at timestamptz not null default clock_timestamp(),
  records_written integer not null default 0 check (records_written >= 0),
  error_code text check (
    error_code is null or char_length(error_code) <= 80
  ),
  error_message text check (
    error_message is null or char_length(error_message) <= 500
  ),
  created_at timestamptz not null default clock_timestamp()
);

alter table reporting.excluded_users enable row level security;
alter table reporting.external_daily_metrics enable row level security;
alter table reporting.ingestion_runs enable row level security;

drop policy if exists reporting_service_role_access
  on reporting.excluded_users;
create policy reporting_service_role_access
  on reporting.excluded_users
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists reporting_service_role_access
  on reporting.external_daily_metrics;
create policy reporting_service_role_access
  on reporting.external_daily_metrics
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists reporting_service_role_access
  on reporting.ingestion_runs;
create policy reporting_service_role_access
  on reporting.ingestion_runs
  for all
  to service_role
  using (true)
  with check (true);

revoke all on table reporting.excluded_users
  from public, anon, authenticated;
revoke all on table reporting.external_daily_metrics
  from public, anon, authenticated;
revoke all on table reporting.ingestion_runs
  from public, anon, authenticated;

grant usage on schema reporting to service_role;
grant select, insert, update, delete
  on table reporting.excluded_users
  to service_role;
grant select, insert, update, delete
  on table reporting.external_daily_metrics
  to service_role;
grant select, insert, update, delete
  on table reporting.ingestion_runs
  to service_role;

with demo_workspaces as (
  select workspace_id
  from public.contacts
  where notes ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.services
  where description ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.tasks
  where title ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.invoices
  where invoice_number ilike 'WC-MOCK-%'
  union
  select workspace_id
  from public.expenses
  where notes ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.booking_requests
  where message ilike '%[Slate demo]%'
)
insert into reporting.excluded_users (user_id, reason)
select distinct wm.user_id, 'demo_seed_workspace'
from public.workspace_members wm
join demo_workspaces dw on dw.workspace_id = wm.workspace_id
on conflict (user_id) do nothing;

create or replace view reporting._included_workspaces
with (security_barrier = true)
as
with demo_workspaces as (
  select workspace_id
  from public.contacts
  where notes ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.services
  where description ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.tasks
  where title ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.invoices
  where invoice_number ilike 'WC-MOCK-%'
  union
  select workspace_id
  from public.expenses
  where notes ilike '%[Slate demo]%'
  union
  select workspace_id
  from public.booking_requests
  where message ilike '%[Slate demo]%'
)
select distinct wm.workspace_id
from public.workspace_members wm
join auth.users u
  on u.id = wm.user_id
 and u.deleted_at is null
left join demo_workspaces dw on dw.workspace_id = wm.workspace_id
where dw.workspace_id is null;

create or replace view reporting._included_users
with (security_barrier = true)
as
select distinct wm.user_id
from public.workspace_members wm
join reporting._included_workspaces iw
  on iw.workspace_id = wm.workspace_id
left join reporting.excluded_users eu on eu.user_id = wm.user_id
where eu.user_id is null;

create or replace view reporting._email_outbox_status
with (security_barrier = true)
as
select status, created_at, updated_at, sent_at
from app_private.transactional_email_outbox
union all
select status, created_at, updated_at, sent_at
from app_private.waitlist_email_outbox
union all
select status, created_at, updated_at, sent_at
from app_private.account_welcome_email_outbox
union all
select status, created_at, updated_at, sent_at
from app_private.account_deletion_email_outbox;

create or replace view reporting.internal_daily_metrics
with (security_barrier = true)
as
select
  u.created_at::date as metric_date,
  'supabase'::text as source,
  'acquisition'::text as category,
  'accounts_created'::text as metric_name,
  count(*)::numeric as metric_value,
  'all'::text as dimension_type,
  'all'::text as dimension_value,
  clock_timestamp() as refreshed_at
from auth.users u
left join reporting.excluded_users eu on eu.user_id = u.id
where u.deleted_at is null
  and eu.user_id is null
group by u.created_at::date

union all
select
  coalesce(u.email_confirmed_at, u.phone_confirmed_at)::date,
  'supabase',
  'activation',
  'accounts_confirmed',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from auth.users u
left join reporting.excluded_users eu on eu.user_id = u.id
where coalesce(u.email_confirmed_at, u.phone_confirmed_at) is not null
  and u.deleted_at is null
  and eu.user_id is null
group by coalesce(u.email_confirmed_at, u.phone_confirmed_at)::date

union all
select
  wm.created_at::date,
  'supabase',
  'activation',
  'users_onboarded',
  count(distinct wm.user_id)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.workspace_members wm
join reporting._included_workspaces iw
  on iw.workspace_id = wm.workspace_id
left join reporting.excluded_users eu on eu.user_id = wm.user_id
where eu.user_id is null
group by wm.created_at::date

union all
select
  w.created_at::date,
  'supabase',
  'activation',
  'workspaces_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.workspaces w
join reporting._included_workspaces iw on iw.workspace_id = w.id
group by w.created_at::date

union all
select
  c.created_at::date,
  'supabase',
  'engagement',
  'clients_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.contacts c
join reporting._included_workspaces iw
  on iw.workspace_id = c.workspace_id
group by c.created_at::date

union all
select
  a.created_at::date,
  'supabase',
  'engagement',
  'bookings_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.appointments a
join reporting._included_workspaces iw
  on iw.workspace_id = a.workspace_id
group by a.created_at::date

union all
select
  a.start_time::date,
  'supabase',
  'engagement',
  'completed_bookings_by_service_date',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.appointments a
join reporting._included_workspaces iw
  on iw.workspace_id = a.workspace_id
where a.status = 'completed'
group by a.start_time::date

union all
select
  a.cancelled_at::date,
  'supabase',
  'engagement',
  'bookings_cancelled',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.appointments a
join reporting._included_workspaces iw
  on iw.workspace_id = a.workspace_id
where a.cancelled_at is not null
group by a.cancelled_at::date

union all
select
  br.created_at::date,
  'supabase',
  'acquisition',
  'booking_requests_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.booking_requests br
join reporting._included_workspaces iw
  on iw.workspace_id = br.workspace_id
group by br.created_at::date

union all
select
  t.created_at::date,
  'supabase',
  'engagement',
  'tasks_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.tasks t
join reporting._included_workspaces iw
  on iw.workspace_id = t.workspace_id
group by t.created_at::date

union all
select
  t.completed_at::date,
  'supabase',
  'engagement',
  'tasks_completed',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.tasks t
join reporting._included_workspaces iw
  on iw.workspace_id = t.workspace_id
where t.status = 'done'
  and t.completed_at is not null
group by t.completed_at::date

union all
select
  coalesce(i.income_recorded_at, i.created_at)::date,
  'supabase',
  'money',
  'income_recorded_gbp',
  coalesce(sum(i.amount_paid), 0)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.invoices i
join reporting._included_workspaces iw
  on iw.workspace_id = i.workspace_id
where i.amount_paid > 0
group by coalesce(i.income_recorded_at, i.created_at)::date

union all
select
  e.expense_date,
  'supabase',
  'money',
  'expenses_recorded_gbp',
  coalesce(sum(e.amount), 0)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.expenses e
join reporting._included_workspaces iw
  on iw.workspace_id = e.workspace_id
group by e.expense_date

union all
select
  coalesce(pt.paid_at, pt.created_at)::date,
  'stripe',
  'money',
  'stripe_payments_succeeded_gbp',
  coalesce(sum(pt.amount_minor), 0)::numeric / 100,
  'all',
  'all',
  clock_timestamp()
from public.payment_transactions pt
join reporting._included_workspaces iw
  on iw.workspace_id = pt.workspace_id
where pt.status in ('succeeded', 'paid')
group by coalesce(pt.paid_at, pt.created_at)::date

union all
select
  pr.created_at::date,
  'stripe',
  'money',
  'stripe_refunds_gbp',
  coalesce(sum(pr.amount_minor), 0)::numeric / 100,
  'all',
  'all',
  clock_timestamp()
from public.payment_refunds pr
join reporting._included_workspaces iw
  on iw.workspace_id = pr.workspace_id
where pr.status in ('succeeded', 'paid')
group by pr.created_at::date

union all
select
  lw.created_at::date,
  'workloop_website',
  'acquisition',
  'launch_waitlist_signups',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from app_private.launch_waitlist lw
group by lw.created_at::date

union all
select
  eo.sent_at::date,
  'resend',
  'email_health',
  'emails_sent',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from reporting._email_outbox_status eo
where eo.status = 'sent'
  and eo.sent_at is not null
group by eo.sent_at::date

union all
select
  eo.updated_at::date,
  'resend',
  'email_health',
  'emails_failed',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from reporting._email_outbox_status eo
where eo.status = 'failed'
group by eo.updated_at::date

union all
select
  n.created_at::date,
  'supabase',
  'engagement',
  'in_app_notifications_created',
  count(*)::numeric,
  'all',
  'all',
  clock_timestamp()
from public.notifications n
join reporting._included_workspaces iw
  on iw.workspace_id = n.workspace_id
group by n.created_at::date;

create or replace view reporting.daily_metrics
with (security_barrier = true)
as
select
  metric_date,
  source,
  category,
  metric_name,
  metric_value,
  dimension_type,
  dimension_value,
  refreshed_at
from reporting.internal_daily_metrics
union all
select
  metric_date,
  source,
  category,
  metric_name,
  metric_value,
  dimension_type,
  dimension_value,
  collected_at
from reporting.external_daily_metrics;

create or replace view reporting.current_kpis
with (security_barrier = true)
as
select
  'acquisition'::text as category,
  'accounts_total'::text as metric_name,
  count(*)::numeric as metric_value,
  'count'::text as unit,
  clock_timestamp() as as_of
from auth.users u
left join reporting.excluded_users eu on eu.user_id = u.id
where u.deleted_at is null
  and eu.user_id is null

union all
select
  'activation',
  'confirmed_accounts_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from auth.users u
left join reporting.excluded_users eu on eu.user_id = u.id
where u.deleted_at is null
  and coalesce(u.email_confirmed_at, u.phone_confirmed_at) is not null
  and eu.user_id is null

union all
select
  'activation',
  'onboarded_users_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from reporting._included_users

union all
select
  'engagement',
  'users_signed_in_last_30_days',
  count(*)::numeric,
  'count',
  clock_timestamp()
from auth.users u
left join reporting.excluded_users eu on eu.user_id = u.id
where u.deleted_at is null
  and u.last_sign_in_at >= clock_timestamp() - interval '30 days'
  and eu.user_id is null

union all
select
  'activation',
  'workspaces_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from reporting._included_workspaces

union all
select
  'engagement',
  'clients_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.contacts c
join reporting._included_workspaces iw
  on iw.workspace_id = c.workspace_id

union all
select
  'engagement',
  'bookings_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.appointments a
join reporting._included_workspaces iw
  on iw.workspace_id = a.workspace_id

union all
select
  'engagement',
  'completed_bookings_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.appointments a
join reporting._included_workspaces iw
  on iw.workspace_id = a.workspace_id
where a.status = 'completed'

union all
select
  'operations',
  'pending_booking_requests',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.booking_requests br
join reporting._included_workspaces iw
  on iw.workspace_id = br.workspace_id
where br.status = 'pending'

union all
select
  'operations',
  'open_tasks',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.tasks t
join reporting._included_workspaces iw
  on iw.workspace_id = t.workspace_id
where t.status = 'open'

union all
select
  'money',
  'income_recorded_total_gbp',
  coalesce(sum(i.amount_paid), 0)::numeric,
  'gbp',
  clock_timestamp()
from public.invoices i
join reporting._included_workspaces iw
  on iw.workspace_id = i.workspace_id

union all
select
  'money',
  'outstanding_balance_gbp',
  coalesce(sum(greatest(i.total - i.amount_paid, 0)), 0)::numeric,
  'gbp',
  clock_timestamp()
from public.invoices i
join reporting._included_workspaces iw
  on iw.workspace_id = i.workspace_id

union all
select
  'money',
  'expenses_total_gbp',
  coalesce(sum(e.amount), 0)::numeric,
  'gbp',
  clock_timestamp()
from public.expenses e
join reporting._included_workspaces iw
  on iw.workspace_id = e.workspace_id

union all
select
  'acquisition',
  'launch_waitlist_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from app_private.launch_waitlist

union all
select
  'notifications',
  'registered_push_devices',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.push_tokens pt
join reporting._included_workspaces iw
  on iw.workspace_id = pt.workspace_id

union all
select
  'payments',
  'payment_enabled_workspaces',
  count(*)::numeric,
  'count',
  clock_timestamp()
from public.workspace_payment_accounts wpa
join reporting._included_workspaces iw
  on iw.workspace_id = wpa.workspace_id
where wpa.charges_enabled
  and wpa.payouts_enabled

union all
select
  'email_health',
  'emails_sent_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from reporting._email_outbox_status
where status = 'sent'

union all
select
  'email_health',
  'emails_failed_total',
  count(*)::numeric,
  'count',
  clock_timestamp()
from reporting._email_outbox_status
where status = 'failed'

union all
select
  'reliability',
  'active_operational_alerts',
  count(*)::numeric,
  'count',
  clock_timestamp()
from app_private.operational_alerts
where status = 'open';

create or replace view reporting.source_health
with (security_barrier = true)
as
select
  'supabase'::text as source,
  'live'::text as status,
  clock_timestamp() as last_updated_at,
  null::integer as records_written,
  'Live aggregate views'::text as detail

union all
select
  'resend',
  case
    when max(updated_at) is null then 'no_activity'
    when count(*) filter (where status = 'failed') > 0 then 'attention'
    else 'healthy'
  end,
  max(updated_at),
  count(*)::integer,
  case
    when count(*) filter (where status = 'failed') > 0
      then 'One or more transactional emails have failed'
    else 'Transactional outbox delivery state'
  end
from reporting._email_outbox_status

union all
select
  latest.source,
  latest.status,
  latest.completed_at,
  latest.records_written,
  coalesce(latest.error_message, 'Latest provider import')
from (
  select distinct on (source)
    source,
    status,
    completed_at,
    records_written,
    error_message
  from reporting.ingestion_runs
  order by source, completed_at desc
) latest;

create or replace function public.ingest_reporting_metrics(
  p_source text,
  p_metrics jsonb,
  p_started_at timestamptz default clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  item jsonb;
  written integer := 0;
  v_metric_date date;
  v_category text;
  v_metric_name text;
  v_metric_value numeric;
  v_dimension_type text;
  v_dimension_value text;
begin
  if p_source not in ('app_store_connect', 'testflight') then
    raise exception 'unsupported reporting source';
  end if;

  if jsonb_typeof(p_metrics) <> 'array' then
    raise exception 'metrics payload must be an array';
  end if;

  if jsonb_array_length(p_metrics) > 1000 then
    raise exception 'metrics payload exceeds 1000 rows';
  end if;

  for item in
    select value from jsonb_array_elements(p_metrics)
  loop
    v_metric_date := (item ->> 'metric_date')::date;
    v_category := btrim(item ->> 'category');
    v_metric_name := btrim(item ->> 'metric_name');
    v_metric_value := (item ->> 'metric_value')::numeric;
    v_dimension_type := coalesce(
      nullif(btrim(item ->> 'dimension_type'), ''),
      'all'
    );
    v_dimension_value := coalesce(
      nullif(btrim(item ->> 'dimension_value'), ''),
      'all'
    );

    if v_metric_date not between date '2024-01-01' and date '2100-01-01'
       or char_length(v_category) not between 1 and 80
       or char_length(v_metric_name) not between 1 and 120
       or char_length(v_dimension_type) not between 1 and 80
       or char_length(v_dimension_value) not between 1 and 160 then
      raise exception 'invalid reporting metric';
    end if;

    insert into reporting.external_daily_metrics (
      metric_date,
      source,
      category,
      metric_name,
      metric_value,
      dimension_type,
      dimension_value,
      collected_at
    )
    values (
      v_metric_date,
      p_source,
      v_category,
      v_metric_name,
      v_metric_value,
      v_dimension_type,
      v_dimension_value,
      clock_timestamp()
    )
    on conflict (
      metric_date,
      source,
      category,
      metric_name,
      dimension_type,
      dimension_value
    )
    do update set
      metric_value = excluded.metric_value,
      collected_at = excluded.collected_at;

    written := written + 1;
  end loop;

  insert into reporting.ingestion_runs (
    source,
    status,
    started_at,
    completed_at,
    records_written
  )
  values (
    p_source,
    'succeeded',
    p_started_at,
    clock_timestamp(),
    written
  );

  return written;
end
$function$;

create or replace function public.record_reporting_ingestion_run(
  p_source text,
  p_status text,
  p_started_at timestamptz,
  p_records_written integer default 0,
  p_error_code text default null,
  p_error_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  run_id uuid;
begin
  if p_source not in ('app_store_connect', 'testflight')
     or p_status not in ('succeeded', 'failed', 'not_configured') then
    raise exception 'invalid reporting ingestion state';
  end if;

  insert into reporting.ingestion_runs (
    source,
    status,
    started_at,
    completed_at,
    records_written,
    error_code,
    error_message
  )
  values (
    p_source,
    p_status,
    p_started_at,
    clock_timestamp(),
    greatest(coalesce(p_records_written, 0), 0),
    left(nullif(p_error_code, ''), 80),
    left(nullif(p_error_message, ''), 500)
  )
  returning id into run_id;

  return run_id;
end
$function$;

revoke all on function public.ingest_reporting_metrics(
  text,
  jsonb,
  timestamptz
) from public, anon, authenticated;

revoke all on function public.record_reporting_ingestion_run(
  text,
  text,
  timestamptz,
  integer,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.ingest_reporting_metrics(
  text,
  jsonb,
  timestamptz
) to service_role;

grant execute on function public.record_reporting_ingestion_run(
  text,
  text,
  timestamptz,
  integer,
  text,
  text
) to service_role;

revoke all on all tables in schema reporting
  from public, anon, authenticated;

grant usage on schema reporting to workloop_reporting_reader;
grant select on table reporting.daily_metrics
  to workloop_reporting_reader;
grant select on table reporting.current_kpis
  to workloop_reporting_reader;
grant select on table reporting.source_health
  to workloop_reporting_reader;

comment on view reporting.daily_metrics is
  'Aggregate-only daily metrics for the private Workloop founder dashboard.';

comment on view reporting.current_kpis is
  'Current aggregate KPIs excluding explicit demo-seed and ownerless workspaces.';

comment on role workloop_reporting_reader is
  'NOLOGIN least-privilege role inherited by the private Looker Studio database login.';

