-- Private booking, note and client files share one metadata/access lifecycle.
-- Composite FKs reject links to another workspace. Target deletion waits for
-- Storage cleanup; workspace deletion cascades after its existing Edge worker
-- removes all bytes. No public URLs or new client security-definer RPCs.
create unique index if not exists appointments_workspace_id_id_uidx
  on public.appointments(workspace_id,id);
create unique index if not exists notes_workspace_id_id_uidx
  on public.notes(workspace_id,id);
create unique index if not exists contacts_workspace_id_id_uidx
  on public.contacts(workspace_id,id);

create table public.record_attachments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  appointment_id uuid,
  note_id uuid,
  contact_id uuid,
  object_path text not null unique,
  file_name text not null check (length(trim(file_name)) between 1 and 200
    and file_name !~ '[[:cntrl:]/\\]'),
  mime_type text not null check (mime_type in
    ('application/pdf','image/jpeg','image/png','image/webp','text/plain')),
  size_bytes integer not null check (size_bytes between 1 and 10485760),
  content_hash text not null check (content_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint record_attachment_one_target check
    (num_nonnulls(appointment_id,note_id,contact_id)=1),
  foreign key (workspace_id,appointment_id)
    references public.appointments(workspace_id,id) deferrable initially deferred,
  foreign key (workspace_id,note_id)
    references public.notes(workspace_id,id) deferrable initially deferred,
  foreign key (workspace_id,contact_id)
    references public.contacts(workspace_id,id) deferrable initially deferred,
  check (object_path = workspace_id::text || '/' ||
    coalesce(appointment_id,note_id,contact_id)::text || '/' || id::text || '.' ||
    case mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg'
      when 'image/png' then 'png' when 'image/webp' then 'webp'
      when 'text/plain' then 'txt' end)
);
create index record_attachments_booking on public.record_attachments(workspace_id,appointment_id,created_at,id);
create index record_attachments_note on public.record_attachments(workspace_id,note_id,created_at,id);
create index record_attachments_contact on public.record_attachments(workspace_id,contact_id,created_at,id);
alter table public.record_attachments enable row level security;
revoke all on public.record_attachments from anon, authenticated;
grant select,insert,delete on public.record_attachments to authenticated;
grant select,insert,update,delete on public.record_attachments to service_role;
create policy record_attachment_member on public.record_attachments for all to authenticated
using (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy())
with check (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy());
create policy record_attachment_no_deletion_upload on public.record_attachments
as restrictive for insert to authenticated
with check (not public.current_account_deletion_pending());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('record-attachments','record-attachments',false,10485760,
  array['application/pdf','image/jpeg','image/png','image/webp','text/plain'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create policy record_attachments_storage_read on storage.objects for select to authenticated
using (bucket_id='record-attachments' and exists (
  select 1 from public.record_attachments attachment where attachment.object_path=name));
create policy record_attachments_storage_insert on storage.objects for insert to authenticated
with check (bucket_id='record-attachments' and not public.current_account_deletion_pending() and exists (
  select 1 from public.record_attachments attachment where attachment.object_path=name));
create policy record_attachments_storage_delete on storage.objects for delete to authenticated
using (bucket_id='record-attachments' and exists (
  select 1 from public.record_attachments attachment where attachment.object_path=name));
-- Uploads are immutable; duplicate retry downloads and verifies the existing
-- object. There is deliberately no authenticated UPDATE/upsert policy.

create function app_private.guard_record_attachment_object_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_workspace uuid;
  caller_role text := coalesce(nullif(current_setting('role',true),'none'),session_user::text);
begin
  if new.bucket_id <> 'record-attachments' then return new; end if;
  -- Storage's native completion role has no access to application tables.
  -- Keep the privileged lookup inside an unexposed trigger instead of granting
  -- that role broad application-table privileges or bypass-RLS policies.
  if caller_role not in ('authenticated','service_role','supabase_storage_admin','postgres') then
    raise exception 'Attachment upload unavailable' using errcode='42501';
  end if;
  select workspace_id into target_workspace from public.record_attachments where object_path=new.name;
  if target_workspace is null then
    raise exception 'Attachment upload unavailable' using errcode='42501';
  end if;
  if caller_role='authenticated' and ((select auth.uid()) is null or
      not app_private.is_workspace_member(target_workspace) or
      not app_private.current_user_meets_mfa_policy()) then
    raise exception 'Attachment upload unavailable' using errcode='42501';
  end if;
  -- This also serializes privileged Storage upload completion with metadata
  -- removal. The subject may be absent on the Storage service connection.
  perform 1 from public.workspaces where id=target_workspace for update;
  if not found or exists (select 1 from public.account_deletion_requests
      where workspace_id=target_workspace and status in ('requested','processing')) then
    raise exception 'Attachment upload unavailable during account deletion' using errcode='42501';
  end if;
  if not exists (select 1 from public.record_attachments where object_path=new.name) then
    raise exception 'Attachment upload unavailable' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_record_attachment_object_write() from public,anon,authenticated;
create trigger guard_record_attachment_object_write before insert or update on storage.objects
for each row execute function app_private.guard_record_attachment_object_write();

create function app_private.guard_record_attachment_metadata_delete()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  perform 1 from public.workspaces where id=old.workspace_id for update;
  if exists (select 1 from storage.objects
      where bucket_id='record-attachments' and name=old.object_path) then
    raise exception 'Remove the attachment file before deleting its record' using errcode='23503';
  end if;
  return old;
end;
$$;
revoke all on function app_private.guard_record_attachment_metadata_delete() from public,anon,authenticated;
create trigger guard_record_attachment_metadata_delete before delete on public.record_attachments
for each row execute function app_private.guard_record_attachment_metadata_delete();
