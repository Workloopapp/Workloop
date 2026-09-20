-- Keep the delivery address only while the bounded deletion-email workflow
-- needs it. Afterwards retain the non-identifying audit hash, not the owner's
-- email, Auth UUID or free-form operational notes.

create or replace function app_private.minimise_completed_deletion_data(
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requests_scrubbed integer := 0;
  v_audits_scrubbed integer := 0;
  v_outbox_rows_removed integer := 0;
begin
  update public.account_deletion_requests request
     set email = '',
         user_id = null,
         requested_by_user_id = null,
         notes = 'Deletion completed.'
   where request.status = 'completed'
     and (
       request.email <> ''
       or request.user_id is not null
       or request.requested_by_user_id is not null
     )
     and not exists (
       select 1
         from app_private.account_deletion_email_outbox email
        where email.request_id = request.id
          and email.status in ('pending', 'processing')
     );
  get diagnostics v_requests_scrubbed = row_count;

  update public.account_deletion_audit audit
     set user_id = null,
         notes = case
           when audit.workspace_deleted and audit.auth_user_deleted
             then 'Deletion completed.'
           else left(audit.notes, 200)
         end
   where audit.user_id is not null
     and audit.completed_at < p_now - interval '1 day';
  get diagnostics v_audits_scrubbed = row_count;

  delete from app_private.account_deletion_email_outbox
   where status in ('sent', 'failed')
     and updated_at < p_now - interval '30 days';
  get diagnostics v_outbox_rows_removed = row_count;

  return jsonb_build_object(
    'requests_scrubbed', v_requests_scrubbed,
    'audits_scrubbed', v_audits_scrubbed,
    'outbox_rows_removed', v_outbox_rows_removed
  );
end;
$$;

revoke all on function app_private.minimise_completed_deletion_data(timestamptz)
  from public, anon, authenticated;
grant execute on function app_private.minimise_completed_deletion_data(timestamptz)
  to service_role;

create or replace function public.refresh_account_deletion_email_alerts()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  update app_private.operational_alerts
     set status = 'resolved', resolved_at = clock_timestamp()
   where status = 'open' and category = 'account_deletion_email';

  if exists (
    select 1 from app_private.account_deletion_email_outbox
     where status = 'failed'
  ) then
    perform app_private.raise_operational_alert(
      'account_deletion_email:failed',
      'account_deletion_email',
      'critical',
      'One or more account deletion emails reached terminal failure.'
    );
  end if;
  if exists (
    select 1 from app_private.account_deletion_email_outbox
     where status in ('pending', 'processing')
       and created_at < clock_timestamp() - interval '5 minutes'
  ) then
    perform app_private.raise_operational_alert(
      'account_deletion_email:delayed',
      'account_deletion_email',
      'warning',
      'Account deletion email delivery is more than five minutes behind.'
    );
  end if;

  select count(*)::integer into v_count
    from app_private.operational_alerts
   where status = 'open' and category = 'account_deletion_email';
  return v_count;
end;
$$;

revoke all on function public.refresh_account_deletion_email_alerts()
  from public, anon, authenticated;
grant execute on function public.refresh_account_deletion_email_alerts()
  to service_role;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job
     where jobname = 'workloop-minimise-completed-deletions'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$$;

select cron.schedule(
  'workloop-minimise-completed-deletions',
  '43 * * * *',
  'select app_private.minimise_completed_deletion_data();'
);
