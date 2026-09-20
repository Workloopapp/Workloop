-- Private supporting records. Estimated tax is computed from reviewed inputs,
-- never persisted as an authoritative liability and never sent to HMRC.
create unique index if not exists expenses_workspace_id_id_unique on public.expenses(workspace_id, id);

create table public.expense_receipts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  expense_id uuid not null,
  object_path text not null unique,
  file_name text not null check (length(file_name) between 1 and 200),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  size_bytes integer not null check (size_bytes between 1 and 10485760),
  created_at timestamptz not null default now(),
  foreign key (workspace_id,expense_id) references public.expenses(workspace_id,id) deferrable initially deferred,
  check (object_path ~ ('^' || workspace_id::text || '/' || expense_id::text || '/[a-f0-9]{32}\.(pdf|jpg|png)$'))
);
create index expense_receipts_expense on public.expense_receipts(expense_id);
create index expense_receipts_workspace on public.expense_receipts(workspace_id);

create table public.mileage_entries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  journey_date date not null,
  miles_hundredths integer not null check (miles_hundredths between 1 and 1000000),
  purpose text not null check (length(trim(purpose)) between 1 and 500),
  vehicle text not null check (length(trim(vehicle)) between 1 and 80 and vehicle = lower(trim(vehicle))),
  vehicle_type text not null check (vehicle_type in ('car_van','motorcycle')),
  created_at timestamptz not null default now()
);
create index mileage_entries_workspace_date on public.mileage_entries(workspace_id,journey_date,id);

create table public.workspace_tax_estimates (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  tax_year text not null check (tax_year = '2026/27'),
  rules_version text not null check (rules_version = 'uk-ewni-2026-27-v1'),
  jurisdiction text not null check (jurisdiction in ('england','wales','northern_ireland')),
  turnover_minor bigint not null check (turnover_minor between 0 and 99999999999),
  non_vehicle_expenses_minor bigint not null check (non_vehicle_expenses_minor between 0 and 99999999999),
  actual_vehicle_expenses_minor bigint not null check (actual_vehicle_expenses_minor between 0 and 99999999999),
  paid_to_hmrc_minor bigint not null check (paid_to_hmrc_minor between 0 and 99999999999),
  reserve_minor bigint not null check (reserve_minor between 0 and 99999999999),
  vehicle_method text not null check (vehicle_method in ('actual','mileage')),
  updated_at timestamptz not null default now(),
  unique(workspace_id,tax_year)
);

do $$ declare table_name text; begin
  foreach table_name in array array['expense_receipts','mileage_entries','workspace_tax_estimates'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated, service_role', table_name);
    execute format('create policy workspace_member on public.%I for all to authenticated using (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy()) with check (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy())', table_name);
  end loop;
end $$;
-- Receipt metadata is immutable: replacing a file means adding a new receipt.
revoke update on public.expense_receipts from authenticated;
create policy receipt_creation_not_during_account_deletion on public.expense_receipts
as restrictive for insert to authenticated
with check (not public.current_account_deletion_pending());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('expense-receipts','expense-receipts',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- The existing metadata row joins the full path to its authorised expense.
-- Metadata is reserved first, and failed uploads remain findable for cleanup.
create policy expense_receipts_storage_read on storage.objects for select to authenticated
using (bucket_id = 'expense-receipts' and exists (
  select 1 from public.expense_receipts receipt where receipt.object_path = name
));
create policy expense_receipts_storage_insert on storage.objects for insert to authenticated
with check (bucket_id = 'expense-receipts' and not public.current_account_deletion_pending() and exists (
  select 1 from public.expense_receipts receipt where receipt.object_path = name
));
-- Storage checks INSERT during upload preflight before final object metadata
-- exists. MIME and byte limits belong on the bucket, not metadata->>'size' RLS.
create policy expense_receipts_storage_delete on storage.objects for delete to authenticated
using (bucket_id = 'expense-receipts' and exists (
  select 1 from public.expense_receipts receipt where receipt.object_path = name
));

-- Storage performs upload completion with its privileged DB connection after
-- the bytes have streamed. Recheck receipt existence and deletion state there
-- as well as at authenticated preflight, so an upload started before account
-- deletion cannot create an inaccessible object after its expense disappeared.
-- Storage's failed-completion path removes the uploaded object version.
create function app_private.guard_receipt_object_write()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare target_workspace uuid;
begin
  if new.bucket_id <> 'expense-receipts' then return new; end if;
  select workspace_id into target_workspace from public.expense_receipts where object_path = new.name;
  if target_workspace is null then
    raise exception 'Receipt upload unavailable' using errcode='42501';
  end if;
  -- Serialize upload completion with workspace removal and its dependent FK
  -- inserts. The existing deletion request remains visible until completion.
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
create trigger guard_receipt_object_write before insert or update on storage.objects
for each row execute function app_private.guard_receipt_object_write();
