-- Route notification taps to the exact workspace-owned record whenever the
-- creating workflow exposes an entity identifier. The user-visible
-- notification remains the source of truth; the existing push outbox reads
-- deep_link at claim time, so this also upgrades APNs delivery without putting
-- private customer data on the lock screen.

create or replace function app_private.route_notification_to_entity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_entity_id uuid;
  v_uuid_pattern constant text :=
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}';
begin
  -- Keep a route already bound to an entity. Its target is still resolved by
  -- workspace-scoped app providers and RLS after the user is authenticated.
  if coalesce(new.deep_link, '') ~
    ('^/(bookings|booking-requests|payments|tasks|notes)/' || v_uuid_pattern || '$')
  then
    return new;
  end if;

  case new.type
    when 'booking_request' then
      if coalesce(new.dedupe_key, '') ~
        ('^booking_request_waiting:' || v_uuid_pattern || '$')
      then
        v_entity_id := split_part(new.dedupe_key, ':', 2)::uuid;
      else
        -- Public booking request creation inserts the request and its
        -- notification in one transaction. xmin identifies that exact row
        -- without matching on customer text or racing another request.
        select request.id
          into v_entity_id
          from public.booking_requests request
         where request.workspace_id = new.workspace_id
           and request.xmin::text = pg_current_xact_id()::text
         order by request.created_at desc, request.id desc
         limit 1;
      end if;
      if v_entity_id is not null and exists (
        select 1 from public.booking_requests request
         where request.id = v_entity_id
           and request.workspace_id = new.workspace_id
      ) then
        new.deep_link := '/booking-requests/' || v_entity_id::text;
      end if;

    when 'invoice_overdue', 'payment_received', 'payment' then
      if coalesce(new.dedupe_key, '') ~
        ('^invoice_overdue:' || v_uuid_pattern || '$')
      then
        v_entity_id := split_part(new.dedupe_key, ':', 2)::uuid;
      else
        select invoice.id
          into v_entity_id
         from public.invoices invoice
         where invoice.workspace_id = new.workspace_id
           and invoice.xmin::text = pg_current_xact_id()::text
         order by invoice.created_at desc, invoice.id desc
         limit 1;
      end if;
      if v_entity_id is not null and exists (
        select 1 from public.invoices invoice
         where invoice.id = v_entity_id
           and invoice.workspace_id = new.workspace_id
      ) then
        new.deep_link := '/payments/' || v_entity_id::text;
      end if;

    when 'new_booking', 'booking', 'no_show' then
      select appointment.id
        into v_entity_id
        from public.appointments appointment
       where appointment.workspace_id = new.workspace_id
         and appointment.xmin::text = pg_current_xact_id()::text
       order by appointment.start_time, appointment.id
       limit 1;
      if v_entity_id is not null then
        new.deep_link := '/bookings/' || v_entity_id::text;
      end if;

    when 'task_due', 'task' then
      if coalesce(new.dedupe_key, '') ~ ('^task_due:' || v_uuid_pattern || '$')
      then
        v_entity_id := split_part(new.dedupe_key, ':', 2)::uuid;
      else
        select task.id
          into v_entity_id
          from public.tasks task
         where task.workspace_id = new.workspace_id
           and task.xmin::text = pg_current_xact_id()::text
         order by task.updated_at desc nulls last, task.created_at desc, task.id desc
         limit 1;
      end if;
      if v_entity_id is not null and exists (
        select 1 from public.tasks task
         where task.id = v_entity_id
           and task.workspace_id = new.workspace_id
      ) then
        new.deep_link := '/tasks/' || v_entity_id::text;
      end if;
    else
      -- General notifications retain their existing destination. A PL/pgSQL
      -- CASE without ELSE raises case_not_found and aborts the automation.
      null;
  end case;

  return new;
end;
$function$;

revoke all on function app_private.route_notification_to_entity()
  from public, anon, authenticated;

drop trigger if exists route_notification_to_entity
  on public.notifications;
create trigger route_notification_to_entity
before insert or update of type, deep_link, dedupe_key
on public.notifications
for each row execute function app_private.route_notification_to_entity();

comment on function app_private.route_notification_to_entity() is
  'Adds tenant-checked entity routes to notification rows before push delivery.';

-- Keep the existing service-role guard, but evaluate it as the caller. Under
-- SECURITY DEFINER current_user was postgres, so every valid webhook failed.
alter function public.record_resend_webhook_event(text, text, text, timestamptz)
  security invoker;

-- Provider acceptance is not proof of delivery. Include delivery receipts and
-- failures while keeping the existing reporting view contract and grants.
create or replace view reporting.source_health
with (security_barrier = true)
as
with outbox as (
  select max(updated_at) as updated_at,
    count(*)::integer as total,
    count(*) filter (where status = 'failed') as failed
  from reporting._email_outbox_status
), receipts as (
  select max(received_at) as received_at,
    count(*) as total,
    count(*) filter (
      where event_type in ('email.bounced', 'email.complained', 'email.failed', 'email.suppressed')
        and occurred_at >= now() - interval '7 days'
    ) as recent_failures,
    count(*) filter (
      where event_type = 'email.delivered'
        and occurred_at >= now() - interval '7 days'
    ) as recent_delivered
  from reporting.resend_webhook_events
)
select 'supabase'::text as source, 'live'::text as status,
  clock_timestamp() as last_updated_at, null::integer as records_written,
  'Live aggregate views'::text as detail
union all
select 'resend',
  case
    when outbox.failed > 0 or receipts.recent_failures > 0 then 'attention'
    when outbox.total = 0 and receipts.total = 0 then 'no_activity'
    when receipts.total = 0 then 'unverified'
    when receipts.recent_delivered = 0 then 'unverified'
    else 'healthy'
  end,
  greatest(outbox.updated_at, receipts.received_at),
  outbox.total,
  case
    when outbox.failed > 0 or receipts.recent_failures > 0
      then format('%s outbox failures; %s provider failures in the last 7 days', outbox.failed, receipts.recent_failures)
    when outbox.total = 0 and receipts.total = 0 then 'No transactional email activity'
    when receipts.total = 0 then 'Provider acceptance recorded; delivery receipts have not been verified'
    when receipts.recent_delivered = 0 then 'Webhook connected; no delivered receipt in the last 7 days'
    else format('%s delivered receipts in the last 7 days; inspect individual receipts for delivery', receipts.recent_delivered)
  end
from outbox cross join receipts
union all
select latest.source, latest.status, latest.completed_at, latest.records_written,
  coalesce(latest.error_message, 'Latest provider import')
from (
  select distinct on (source) source, status, completed_at, records_written, error_message
  from reporting.ingestion_runs
  where source <> 'resend'
  order by source, completed_at desc
) latest;

comment on view reporting.source_health is
  'Aggregate source status. Email provider acceptance and verified delivery are distinct; recent provider failures require attention.';
