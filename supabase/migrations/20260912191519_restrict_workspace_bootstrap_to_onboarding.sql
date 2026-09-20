-- Only the verified atomic onboarding RPC may create a workspace and its first
-- membership. An empty workspace is not evidence that a caller owns it.
drop policy if exists "Users can create their first workspace membership"
  on public.workspace_members;
drop policy if exists "Authenticated users can create workspaces"
  on public.workspaces;
revoke insert on public.workspace_members, public.workspaces from anon, authenticated;
revoke execute on function app_private.workspace_has_no_members(uuid)
  from public, anon, authenticated;

-- A trigger needs no client EXECUTE privilege. Keep the privileged push enqueue
-- implementation callable only through its existing trigger.
revoke all on function app_private.enqueue_notification_push()
  from public, anon, authenticated;
