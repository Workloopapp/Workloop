-- Logos are intentionally public business branding, including during setup.
-- Immutable object names preserve the logo in issued invoice/quote snapshots.
-- Existing workspaces.logo_url stores the current logo; no row shape changes.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('business-logos', 'business-logos', true, 2097152, array['image/png', 'image/jpeg'])
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy business_logos_storage_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'business-logos'
  and public.current_user_meets_mfa_policy()
  and not public.current_account_deletion_pending()
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|jpg)$'
);
-- Public delivery uses the public bucket endpoint. There are deliberately no
-- client UPDATE or DELETE policies: past issued document logos remain stable.
-- Account deletion removes the entire user folder with the service role.

-- Serialize object metadata insertion with auth-user deletion, including
-- onboarding uploads which have no workspace yet. Reject still-valid tokens
-- after the auth row has gone and block writes while deletion is pending.
create or replace function app_private.guard_business_logo_write()
returns trigger language plpgsql security definer set search_path = public
as $$
declare logo_user uuid;
begin
  if new.bucket_id <> 'business-logos' then return new; end if;
  if new.name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|jpg)$' then
    raise exception 'Invalid business logo path' using errcode='42501';
  end if;
  logo_user := split_part(new.name,'/',1)::uuid;
  perform 1 from auth.users where id=logo_user for key share;
  if not found or exists(select 1 from public.account_deletion_requests
    where coalesce(requested_by_user_id,user_id)=logo_user
      and status in ('requested','processing')) then
    raise exception 'Business logo upload unavailable during account deletion' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_business_logo_write() from public,anon,authenticated;
create trigger guard_business_logo_write before insert or update on storage.objects
for each row execute function app_private.guard_business_logo_write();
