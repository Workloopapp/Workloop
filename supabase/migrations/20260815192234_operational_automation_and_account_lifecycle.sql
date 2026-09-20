-- Close the stale-session hole around account deletion and centralise the
-- idempotent, database-owned business/retention automations. External provider
-- work (Auth deletion, Stripe offboarding and alert email delivery) remains in
-- the protected scheduled Edge worker.

create or replace function public.current_account_deletion_pending()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.account_deletion_requests request
     where request.requested_by_user_id = (select auth.uid())
       and request.status in ('requested', 'processing')
  );
$$;

revoke all on function public.current_account_deletion_pending()
  from public, anon;
grant execute on function public.current_account_deletion_pending()
  to authenticated, service_role;

create or replace function public.complete_onboarding(
  business_name text,
  industry_name text,
  profile_handle text,
  service_rows jsonb,
  working_hours_value jsonb,
  revenue_target_value numeric,
  first_booking_value jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not exists (
       select 1 from auth.users where id = (select auth.uid())
     ) then
    raise exception 'Your sign-in is no longer active'
      using errcode = '28000';
  end if;

  if public.current_account_deletion_pending() then
    raise exception 'Account deletion is already in progress'
      using errcode = '42501';
  end if;

  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'Multi-factor authentication is required'
      using errcode = '42501';
  end if;

  return app_private.complete_onboarding_implementation(
    business_name,
    industry_name,
    profile_handle,
    service_rows,
    working_hours_value,
    revenue_target_value,
    first_booking_value
  );
end;
$$;

revoke all on function public.complete_onboarding(
  text, text, text, jsonb, jsonb, numeric, jsonb
) from public, anon;
grant execute on function public.complete_onboarding(
  text, text, text, jsonb, jsonb, numeric, jsonb
) to authenticated;

create table app_private.operational_alerts (
  id uuid primary key default gen_random_uuid(),
  alert_key text not null unique,
  category text not null,
  severity text not null check (severity in ('warning', 'critical')),
  message text not null check (char_length(message) between 1 and 500),
  status text not null default 'open' check (status in ('open', 'resolved')),
  first_seen_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  last_notified_at timestamptz,
  resolved_at timestamptz
);

create index operational_alerts_delivery_idx
  on app_private.operational_alerts(severity, first_seen_at)
  where status = 'open';

alter table app_private.operational_alerts enable row level security;
revoke all on table app_private.operational_alerts
  from public, anon, authenticated;
grant select, insert, update on table app_private.operational_alerts
  to service_role;

create or replace function app_private.raise_operational_alert(
  p_alert_key text,
  p_category text,
  p_severity text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into app_private.operational_alerts(
    alert_key, category, severity, message
  ) values (
    left(btrim(p_alert_key), 200),
    left(btrim(p_category), 80),
    p_severity,
    left(btrim(p_message), 500)
  )
  on conflict (alert_key) do update
    set category = excluded.category,
        severity = excluded.severity,
        message = excluded.message,
        status = 'open',
        last_seen_at = clock_timestamp(),
        last_notified_at = case
          when app_private.operational_alerts.status = 'resolved' then null
          else app_private.operational_alerts.last_notified_at
        end,
        resolved_at = null;
end;
$$;

revoke all on function app_private.raise_operational_alert(text, text, text, text)
  from public, anon, authenticated;
grant execute on function app_private.raise_operational_alert(text, text, text, text)
  to service_role;

create or replace function app_private.refresh_operational_alerts(
  p_now timestamptz default clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request record;
  v_count integer;
begin
  update app_private.operational_alerts
     set status = 'resolved', resolved_at = p_now
   where status = 'open'
     and category in ('account_deletion', 'transactional_email');

  for v_request in
    select request.id, request.status, request.requested_at,
           request.processing_started_at
      from public.account_deletion_requests request
     where (
       request.status = 'requested'
       and request.requested_at < p_now - interval '5 minutes'
     ) or (
       request.status = 'processing'
       and request.processing_started_at < p_now - interval '10 minutes'
     )
  loop
    perform app_private.raise_operational_alert(
      'account_deletion:' || v_request.id::text,
      'account_deletion',
      'critical',
      'An account deletion request is not completing within its expected window.'
    );
  end loop;

  if exists (
    select 1 from app_private.transactional_email_outbox
     where status = 'failed'
  ) then
    perform app_private.raise_operational_alert(
      'transactional_email:booking:failed',
      'transactional_email',
      'critical',
      'One or more booking confirmation emails reached terminal failure.'
    );
  end if;
  if exists (
    select 1 from app_private.waitlist_email_outbox
     where status = 'failed'
  ) then
    perform app_private.raise_operational_alert(
      'transactional_email:waitlist:failed',
      'transactional_email',
      'critical',
      'One or more waitlist welcome emails reached terminal failure.'
    );
  end if;
  if exists (
    select 1 from app_private.account_welcome_email_outbox
     where status = 'failed'
  ) then
    perform app_private.raise_operational_alert(
      'transactional_email:account:failed',
      'transactional_email',
      'critical',
      'One or more account welcome emails reached terminal failure.'
    );
  end if;

  if exists (
    select 1 from app_private.transactional_email_outbox
     where status in ('pending', 'processing')
       and created_at < p_now - interval '5 minutes'
  ) or exists (
    select 1 from app_private.waitlist_email_outbox
     where status in ('pending', 'processing')
       and created_at < p_now - interval '5 minutes'
  ) or exists (
    select 1 from app_private.account_welcome_email_outbox
     where status in ('pending', 'processing')
       and created_at < p_now - interval '5 minutes'
  ) then
    perform app_private.raise_operational_alert(
      'transactional_email:delivery_delayed',
      'transactional_email',
      'warning',
      'Transactional email delivery is more than five minutes behind.'
    );
  end if;

  select count(*)::integer into v_count
    from app_private.operational_alerts
   where status = 'open';
  return v_count;
end;
$$;

revoke all on function app_private.refresh_operational_alerts(timestamptz)
  from public, anon, authenticated;
grant execute on function app_private.refresh_operational_alerts(timestamptz)
  to service_role;

create or replace function public.claim_operational_alerts(
  p_limit integer default 20
)
returns table(
  alert_id uuid,
  alert_key text,
  category text,
  severity text,
  message text,
  first_seen_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  return query
  with candidates as (
    select alert.id
      from app_private.operational_alerts alert
     where alert.status = 'open'
       and (
         alert.last_notified_at is null
         or alert.last_notified_at < clock_timestamp() - interval '6 hours'
       )
     order by
       case when alert.severity = 'critical' then 0 else 1 end,
       alert.first_seen_at
     for update skip locked
     limit least(greatest(coalesce(p_limit, 20), 1), 100)
  ), claimed as (
    update app_private.operational_alerts alert
       set last_notified_at = clock_timestamp()
      from candidates
     where alert.id = candidates.id
    returning alert.*
  )
  select claimed.id, claimed.alert_key, claimed.category, claimed.severity,
         claimed.message, claimed.first_seen_at
    from claimed;
end;
$$;

revoke all on function public.claim_operational_alerts(integer)
  from public, anon, authenticated;
grant execute on function public.claim_operational_alerts(integer)
  to service_role;

create or replace function public.finish_operational_alert_delivery(
  p_alert_id uuid,
  p_sent boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if not coalesce(p_sent, false) then
    update app_private.operational_alerts
       set last_notified_at = null
     where id = p_alert_id and status = 'open';
  end if;
end;
$$;

revoke all on function public.finish_operational_alert_delivery(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.finish_operational_alert_delivery(uuid, boolean)
  to service_role;

create or replace function app_private.run_business_automations(
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_requests integer := 0;
  v_overdue_payments integer := 0;
  v_morning_briefs integer := 0;
  v_notifications_removed integer := 0;
  v_tokens_removed integer := 0;
  v_webhook_payloads_scrubbed integer := 0;
  v_open_alerts integer := 0;
begin
  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select request.workspace_id,
         'booking_request',
         'Booking request waiting',
         request.name || ' has been waiting for your reply.',
         '/booking-requests',
         'booking_request_waiting:' || request.id::text
    from public.booking_requests request
    left join public.notification_preferences preference
      on preference.workspace_id = request.workspace_id
   where request.status = 'pending'
     and request.created_at <= p_now - interval '4 hours'
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.booking_request, true)
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_booking_requests = row_count;

  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select invoice.workspace_id,
         'invoice_overdue',
         'Payment overdue',
         'A payment of £' ||
           trim(to_char(greatest(invoice.total - coalesce(invoice.amount_paid, 0), 0),
             'FM999999990.00')) || ' needs attention.',
         '/payments',
         'invoice_overdue:' || invoice.id::text
    from public.invoices invoice
    left join public.notification_preferences preference
      on preference.workspace_id = invoice.workspace_id
    left join public.workspace_settings settings
      on settings.workspace_id = invoice.workspace_id
   where invoice.type = 'invoice'
     and invoice.status in ('sent', 'overdue')
     and invoice.due_date is not null
     and invoice.due_date < (p_now at time zone coalesce(settings.timezone, 'UTC'))::date
     and invoice.total > coalesce(invoice.amount_paid, 0)
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.invoice_overdue, true)
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_overdue_payments = row_count;

  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select workspace.id,
         'morning_digest',
         'Your morning brief',
         format(
           '%s booking%s today · %s open task%s · %s payment%s to collect.',
           counts.booking_count,
           case when counts.booking_count = 1 then '' else 's' end,
           counts.task_count,
           case when counts.task_count = 1 then '' else 's' end,
           counts.payment_count,
           case when counts.payment_count = 1 then '' else 's' end
         ),
         '/home',
         'morning_digest:' || counts.local_date::text
    from public.workspaces workspace
    left join public.workspace_settings settings
      on settings.workspace_id = workspace.id
    left join public.notification_preferences preference
      on preference.workspace_id = workspace.id
    cross join lateral (
      select
        (p_now at time zone coalesce(settings.timezone, 'UTC'))::date as local_date,
        extract(hour from p_now at time zone coalesce(settings.timezone, 'UTC'))::integer as local_hour,
        (select count(*) from public.appointments appointment
          where appointment.workspace_id = workspace.id
            and appointment.status = 'scheduled'
            and (appointment.start_time at time zone coalesce(settings.timezone, 'UTC'))::date =
              (p_now at time zone coalesce(settings.timezone, 'UTC'))::date) as booking_count,
        (select count(*) from public.tasks task
          where task.workspace_id = workspace.id and task.status = 'open') as task_count,
        (select count(*) from public.invoices invoice
          where invoice.workspace_id = workspace.id
            and invoice.type = 'invoice'
            and invoice.status in ('sent', 'overdue')
            and invoice.total > coalesce(invoice.amount_paid, 0)) as payment_count
    ) counts
   where counts.local_hour = 7
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.morning_digest, true)
     and not (
       coalesce(preference.quiet_sundays, false)
       and extract(isodow from counts.local_date) = 7
     )
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_morning_briefs = row_count;

  delete from public.notifications
   where (read and created_at < p_now - interval '90 days')
      or created_at < p_now - interval '1 year';
  get diagnostics v_notifications_removed = row_count;

  delete from public.push_tokens
   where last_seen_at < p_now - interval '90 days';
  get diagnostics v_tokens_removed = row_count;

  delete from app_private.edge_rate_limit_events
   where created_at < p_now - interval '1 day';

  v_webhook_payloads_scrubbed :=
    app_private.scrub_expired_stripe_webhook_payloads();
  v_open_alerts := app_private.refresh_operational_alerts(p_now);

  return jsonb_build_object(
    'booking_request_notifications', v_booking_requests,
    'overdue_payment_notifications', v_overdue_payments,
    'morning_briefs', v_morning_briefs,
    'notifications_removed', v_notifications_removed,
    'push_tokens_removed', v_tokens_removed,
    'webhook_payloads_scrubbed', v_webhook_payloads_scrubbed,
    'open_operational_alerts', v_open_alerts
  );
end;
$$;

revoke all on function app_private.run_business_automations(timestamptz)
  from public, anon, authenticated;
grant execute on function app_private.run_business_automations(timestamptz)
  to service_role;

create or replace function public.run_workloop_automations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  return app_private.run_business_automations(clock_timestamp());
end;
$$;

revoke all on function public.run_workloop_automations()
  from public, anon, authenticated;
grant execute on function public.run_workloop_automations()
  to service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job
     where jobname = 'workloop-operational-automations'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$$;

select cron.schedule(
  'workloop-operational-automations',
  '*/15 * * * *',
  'select app_private.run_business_automations();'
);
