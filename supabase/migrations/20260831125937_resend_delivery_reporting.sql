alter table reporting.external_daily_metrics
  drop constraint if exists external_daily_metrics_source_check;

alter table reporting.external_daily_metrics
  add constraint external_daily_metrics_source_check
  check (source in ('app_store_connect', 'testflight', 'resend'));

alter table reporting.ingestion_runs
  drop constraint if exists ingestion_runs_source_check;

alter table reporting.ingestion_runs
  add constraint ingestion_runs_source_check
  check (source in ('app_store_connect', 'testflight', 'resend'));

create table if not exists reporting.resend_webhook_events (
  svix_id text primary key
    check (char_length(svix_id) between 1 and 160),
  provider_message_id text not null
    check (char_length(provider_message_id) between 1 and 160),
  event_type text not null check (
    event_type in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.failed',
      'email.opened',
      'email.clicked',
      'email.bounced',
      'email.complained',
      'email.scheduled',
      'email.suppressed'
    )
  ),
  occurred_at timestamptz not null,
  received_at timestamptz not null default clock_timestamp()
);

alter table reporting.resend_webhook_events enable row level security;

drop policy if exists reporting_service_role_access
  on reporting.resend_webhook_events;
create policy reporting_service_role_access
  on reporting.resend_webhook_events
  for all
  to service_role
  using (true)
  with check (true);

revoke all on table reporting.resend_webhook_events
  from public, anon, authenticated;

grant select, insert, update, delete
  on table reporting.resend_webhook_events
  to service_role;

create or replace function public.record_resend_webhook_event(
  p_svix_id text,
  p_provider_message_id text,
  p_event_type text,
  p_occurred_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_rows integer := 0;
begin
  if current_user <> 'service_role' then
    raise exception 'service role required';
  end if;

  insert into reporting.resend_webhook_events (
    svix_id,
    provider_message_id,
    event_type,
    occurred_at
  ) values (
    p_svix_id,
    p_provider_message_id,
    p_event_type,
    p_occurred_at
  )
  on conflict (svix_id) do nothing;

  get diagnostics inserted_rows = row_count;

  if inserted_rows = 1 then
    insert into reporting.external_daily_metrics (
      metric_date,
      source,
      category,
      metric_name,
      metric_value,
      dimension_type,
      dimension_value,
      collected_at
    ) values (
      p_occurred_at::date,
      'resend',
      'email_health',
      replace(p_event_type, '.', '_'),
      1,
      'all',
      'all',
      clock_timestamp()
    )
    on conflict (
      metric_date,
      source,
      category,
      metric_name,
      dimension_type,
      dimension_value
    ) do update set
      metric_value = reporting.external_daily_metrics.metric_value + 1,
      collected_at = excluded.collected_at;
  end if;

  return inserted_rows = 1;
end
$function$;

revoke all on function public.record_resend_webhook_event(
  text,
  text,
  text,
  timestamptz
) from public, anon, authenticated;

grant execute on function public.record_resend_webhook_event(
  text,
  text,
  text,
  timestamptz
) to service_role;

comment on table reporting.resend_webhook_events is
  'Minimal idempotency ledger for verified Resend delivery events. Recipient, subject, and body data are deliberately not stored.';

comment on function public.record_resend_webhook_event(
  text,
  text,
  text,
  timestamptz
) is
  'Service-role-only ingestion boundary for verified Resend webhook metadata and aggregate daily metrics.';
