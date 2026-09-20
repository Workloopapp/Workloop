-- Supabase's native Storage completion role does not have application-table
-- grants. Keep its reservation/deletion lookup in an unexposed trigger; do not
-- broaden that role's table grants or remove checks from authenticated writes.
create or replace function app_private.guard_receipt_object_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_workspace uuid;
  caller_role text := coalesce(nullif(current_setting('role',true),'none'),session_user::text);
begin
  if new.bucket_id <> 'expense-receipts' then return new; end if;
  if caller_role not in ('authenticated','service_role','supabase_storage_admin','postgres') then
    raise exception 'Receipt upload unavailable' using errcode='42501';
  end if;
  select workspace_id into target_workspace from public.expense_receipts where object_path=new.name;
  if target_workspace is null then
    raise exception 'Receipt upload unavailable' using errcode='42501';
  end if;
  if caller_role='authenticated' and ((select auth.uid()) is null or
      not app_private.is_workspace_member(target_workspace) or
      not app_private.current_user_meets_mfa_policy()) then
    raise exception 'Receipt upload unavailable' using errcode='42501';
  end if;
  perform 1 from public.workspaces where id=target_workspace for update;
  if not found or exists (select 1 from public.account_deletion_requests
      where workspace_id=target_workspace and status in ('requested','processing')) then
    raise exception 'Receipt upload unavailable during account deletion' using errcode='42501';
  end if;
  if not exists (select 1 from public.expense_receipts where object_path=new.name) then
    raise exception 'Receipt upload unavailable' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_receipt_object_write() from public,anon,authenticated;
