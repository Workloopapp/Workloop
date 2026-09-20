-- Supabase Auth stores email as varchar(255); the worker RPC contract uses text.
create or replace function app_private.claim_booking_reminder_emails(p_limit integer default 5)
returns table(outbox_id uuid,lease_token uuid,recipient_email text,unsubscribe_token uuid,reply_email text,payload jsonb)
language plpgsql security definer set search_path='' as $$
begin
  perform public.enqueue_booking_reminder_emails();
  update app_private.booking_reminder_outbox set status='cancelled',last_error='reminder_window_expired',lease_token=null,lease_expires_at=null
    where status in ('pending','processing') and expires_at<=now();
  return query with candidates as (
    select q.id from app_private.booking_reminder_outbox q
    join public.appointments a on a.id=q.appointment_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join app_private.booking_reminder_preferences p on p.id=q.preference_id
    where q.due_at<=now() and q.expires_at>now() and q.attempt_count<4
      and (q.status='pending' or (q.status='processing' and q.lease_expires_at<now()))
      and a.status='scheduled' and a.start_time=q.start_time and q.minutes_before=any(s.customer_reminder_minutes)
      and p.stopped_at is null and p.suppressed_at is null
    order by q.due_at,q.id for update of q skip locked limit greatest(1,least(p_limit,20))
  ), claimed as (
    update app_private.booking_reminder_outbox q set status='processing',attempt_count=q.attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+interval '2 minutes'
    where q.id in(select id from candidates) returning q.*
  ) select q.id,q.lease_token,p.email,p.unsubscribe_token,
      (select u.email::text from public.workspace_members m join auth.users u on u.id=m.user_id
        where m.workspace_id=a.workspace_id and u.email_confirmed_at is not null order by m.user_id limit 1),
      jsonb_build_object('business_name',w.name,'customer_name',coalesce(r.customer_name,c.name),'booking_title',a.title,
        'start_time',a.start_time,'end_time',a.end_time,'timezone',s.timezone,'location',a.location,'minutes_before',q.minutes_before)
    from claimed q join public.appointments a on a.id=q.appointment_id
    join public.workspaces w on w.id=a.workspace_id
    join public.workspace_settings s on s.workspace_id=a.workspace_id
    join public.contacts c on c.id=a.contact_id and c.workspace_id=a.workspace_id
    left join app_private.booking_email_recipient r on r.appointment_id=a.id and r.workspace_id=a.workspace_id
    join app_private.booking_reminder_preferences p on p.id=q.preference_id;
end; $$;
