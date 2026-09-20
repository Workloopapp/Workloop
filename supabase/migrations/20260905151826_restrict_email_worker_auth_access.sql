-- Hosted service_role has no direct auth.users table access. Keep that boundary:
-- put only these bounded worker operations behind private definer functions,
-- with service-only invoker RPCs. Do not grant general access to auth records.

alter function public.claim_booking_reminder_emails(integer) set schema app_private;
alter function app_private.claim_booking_reminder_emails(integer) security definer;
revoke all on function app_private.claim_booking_reminder_emails(integer) from public,anon,authenticated;
grant execute on function app_private.claim_booking_reminder_emails(integer) to service_role;
create function public.claim_booking_reminder_emails(p_limit integer default 5) returns table(outbox_id uuid,lease_token uuid,recipient_email text,unsubscribe_token uuid,reply_email text,payload jsonb)
language sql security invoker set search_path='' as $$
  select * from app_private.claim_booking_reminder_emails(p_limit);
$$;
revoke all on function public.claim_booking_reminder_emails(integer) from public,anon,authenticated;
grant execute on function public.claim_booking_reminder_emails(integer) to service_role;

alter function public.enqueue_account_email_journeys() set schema app_private;
alter function app_private.enqueue_account_email_journeys() security definer;
revoke all on function app_private.enqueue_account_email_journeys() from public,anon,authenticated;
grant execute on function app_private.enqueue_account_email_journeys() to service_role;
create function public.enqueue_account_email_journeys() returns integer
language sql security invoker set search_path='' as $$
  select app_private.enqueue_account_email_journeys();
$$;
revoke all on function public.enqueue_account_email_journeys() from public,anon,authenticated;
grant execute on function public.enqueue_account_email_journeys() to service_role;

alter function public.claim_learning_emails(integer) set schema app_private;
alter function app_private.claim_learning_emails(integer) security definer;
revoke all on function app_private.claim_learning_emails(integer) from public,anon,authenticated;
grant execute on function app_private.claim_learning_emails(integer) to service_role;
create function public.claim_learning_emails(p_limit integer default 5) returns table(outbox_id uuid,contact_id uuid,step integer,email text,stage text,confirm_token uuid,unsubscribe_token uuid,lease_token uuid)
language sql security invoker set search_path='' as $$
  select * from app_private.claim_learning_emails(p_limit);
$$;
revoke all on function public.claim_learning_emails(integer) from public,anon,authenticated;
grant execute on function public.claim_learning_emails(integer) to service_role;

alter function public.learning_email_still_allowed(uuid,uuid) set schema app_private;
alter function app_private.learning_email_still_allowed(uuid,uuid) security definer;
revoke all on function app_private.learning_email_still_allowed(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.learning_email_still_allowed(uuid,uuid) to service_role;
create function public.learning_email_still_allowed(p_outbox_id uuid,p_lease_token uuid) returns boolean
language sql security invoker set search_path='' as $$
  select app_private.learning_email_still_allowed(p_outbox_id,p_lease_token);
$$;
revoke all on function public.learning_email_still_allowed(uuid,uuid) from public,anon,authenticated;
grant execute on function public.learning_email_still_allowed(uuid,uuid) to service_role;
