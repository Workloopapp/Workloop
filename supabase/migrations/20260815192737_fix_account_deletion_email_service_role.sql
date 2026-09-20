-- These RPCs deliberately verify current_user. Under SECURITY DEFINER that
-- value is the function owner, so even a genuine service_role caller was
-- rejected. Run with the caller's privileges instead: service_role already
-- has the narrow table grants it needs, while client roles have neither table
-- access nor EXECUTE permission on these functions.

alter function public.claim_account_deletion_emails(integer)
  security invoker;

alter function public.finish_account_deletion_email(
  uuid, uuid, boolean, text, text
) security invoker;

comment on function public.claim_account_deletion_emails(integer) is
  'Service-role-only account deletion email claim using caller privileges.';

comment on function public.finish_account_deletion_email(
  uuid, uuid, boolean, text, text
) is
  'Service-role-only account deletion email completion using caller privileges.';
