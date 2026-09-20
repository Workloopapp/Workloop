-- Slate V1 RLS policy contract.
-- Review before applying to production; policies assume auth.uid() maps to workspace_members.user_id.

create schema if not exists app_private;

revoke all on schema app_private from public;
grant usage on schema app_private to authenticated, service_role;

create or replace function app_private.is_workspace_member(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.workspace_members
      where workspace_id = target_workspace_id
        and user_id = (select auth.uid())
    );
$$;

revoke execute on function app_private.is_workspace_member(uuid) from public;
revoke execute on function app_private.is_workspace_member(uuid) from anon;
grant execute on function app_private.is_workspace_member(uuid) to authenticated;
grant execute on function app_private.is_workspace_member(uuid) to service_role;

create or replace function app_private.workspace_has_no_members(
  target_workspace_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select auth.uid()) is not null
    and not exists (
      select 1
      from public.workspace_members
      where workspace_id = target_workspace_id
    );
$$;

revoke execute on function app_private.workspace_has_no_members(uuid) from public;
revoke execute on function app_private.workspace_has_no_members(uuid) from anon;
grant execute on function app_private.workspace_has_no_members(uuid) to authenticated;
grant execute on function app_private.workspace_has_no_members(uuid) to service_role;

alter table if exists workspaces enable row level security;
alter table if exists workspace_members enable row level security;
alter table if exists workspace_settings enable row level security;
alter table if exists contacts enable row level security;
alter table if exists services enable row level security;
alter table if exists service_add_ons enable row level security;
alter table if exists appointments enable row level security;
alter table if exists appointment_items enable row level security;
alter table if exists invoices enable row level security;
alter table if exists notes enable row level security;
alter table if exists invoice_line_items enable row level security;
alter table if exists expenses enable row level security;
alter table if exists tasks enable row level security;
alter table if exists task_checklist_items enable row level security;
alter table if exists business_profiles enable row level security;
alter table if exists booking_requests enable row level security;
alter table if exists booking_request_items enable row level security;
alter table if exists notifications enable row level security;
alter table if exists notification_preferences enable row level security;
alter table if exists push_tokens enable row level security;
alter table if exists calendar_sync_accounts enable row level security;
alter table if exists account_deletion_requests enable row level security;
alter table if exists account_deletion_audit enable row level security;

drop policy if exists "Members can read workspaces" on workspaces;
create policy "Members can read workspaces"
on workspaces for select
to authenticated
using (app_private.is_workspace_member(id));

drop policy if exists "Members can update workspaces" on workspaces;
create policy "Members can update workspaces"
on workspaces for update
to authenticated
using (app_private.is_workspace_member(id))
with check (app_private.is_workspace_member(id));

drop policy if exists "Authenticated users can create workspaces" on workspaces;
create policy "Authenticated users can create workspaces"
on workspaces for insert
to authenticated
with check ((select auth.uid()) is not null);

drop policy if exists "Members can read workspace members" on workspace_members;
drop policy if exists "Users can read their own workspace membership" on workspace_members;
create policy "Users can read their own workspace membership"
on workspace_members for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Users can create their first workspace membership" on workspace_members;
create policy "Users can create their first workspace membership"
on workspace_members for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and (
    app_private.is_workspace_member(workspace_id)
    or app_private.workspace_has_no_members(workspace_id)
  )
);

drop policy if exists "Members can manage workspace settings" on workspace_settings;
create policy "Members can manage workspace settings"
on workspace_settings for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage contacts" on contacts;
create policy "Members can manage contacts"
on contacts for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage services" on services;
create policy "Members can manage services"
on services for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Public can read visible services" on services;
-- Public service reads are served by the get-public-profile Edge Function.

drop policy if exists "Members can manage service add-ons" on service_add_ons;
create policy "Members can manage service add-ons"
on service_add_ons for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage appointments" on appointments;
create policy "Members can manage appointments"
on appointments for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can read appointment items" on appointment_items;
create policy "Members can read appointment items"
on appointment_items for select
to authenticated
using (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage invoices" on invoices;
create policy "Members can manage invoices"
on invoices for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage notes" on notes;
create policy "Members can manage notes"
on notes for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage invoice line items" on invoice_line_items;
create policy "Members can manage invoice line items"
on invoice_line_items for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage expenses" on expenses;
create policy "Members can manage expenses"
on expenses for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage tasks" on tasks;
create policy "Members can manage tasks"
on tasks for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage task checklist items" on task_checklist_items;
create policy "Members can manage task checklist items"
on task_checklist_items for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage business profiles" on business_profiles;
create policy "Members can manage business profiles"
on business_profiles for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Public can read business profiles" on business_profiles;
-- Public profile reads are served by the get-public-profile Edge Function.

drop policy if exists "Members can manage booking requests" on booking_requests;
create policy "Members can manage booking requests"
on booking_requests for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Public can create booking requests" on booking_requests;
-- Public booking requests are created by the create-booking-request Edge Function.

drop policy if exists "Members can read booking request items" on booking_request_items;
create policy "Members can read booking request items"
on booking_request_items for select
to authenticated
using (app_private.is_workspace_member(workspace_id));

drop policy if exists "Verified MFA users require AAL2" on service_add_ons;
create policy "Verified MFA users require AAL2"
on service_add_ons as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

drop policy if exists "Verified MFA users require AAL2" on booking_request_items;
create policy "Verified MFA users require AAL2"
on booking_request_items as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

drop policy if exists "Verified MFA users require AAL2" on appointment_items;
create policy "Verified MFA users require AAL2"
on appointment_items as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

drop policy if exists "Members can manage notifications" on notifications;
create policy "Members can manage notifications"
on notifications for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage notification preferences" on notification_preferences;
create policy "Members can manage notification preferences"
on notification_preferences for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage push tokens" on push_tokens;
create policy "Members can manage push tokens"
on push_tokens for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can manage calendar sync accounts" on calendar_sync_accounts;
create policy "Members can manage calendar sync accounts"
on calendar_sync_accounts for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can create deletion requests" on account_deletion_requests;
create policy "Members can create deletion requests"
on account_deletion_requests for insert
to authenticated
with check (app_private.is_workspace_member(workspace_id));

drop policy if exists "Members can read deletion requests" on account_deletion_requests;
create policy "Members can read deletion requests"
on account_deletion_requests for select
to authenticated
using (app_private.is_workspace_member(workspace_id));

drop policy if exists "No client access to account deletion audit" on account_deletion_audit;
create policy "No client access to account deletion audit"
on account_deletion_audit for all
to anon, authenticated
using (false)
with check (false);

-- 2026-09-08 finite recurring series: the invoker RPC retains appointment RLS
-- and delegates transactional creation/MFA to create_booking_workflow.
-- Only authenticated workspace members can create/replay their own series.
revoke all on function public.create_recurring_booking_workflow(jsonb) from public, anon;
grant execute on function public.create_recurring_booking_workflow(jsonb) to authenticated;

-- 2026-09-08 recovery uses an unexposed, read-only definer helper for the
-- deliberately private idempotency table. It explicitly checks the current
-- user, workspace membership and MFA; results are scoped to user + series key.
revoke all on function app_private.recurring_booking_result(uuid,text) from public, anon;
grant execute on function app_private.recurring_booking_result(uuid,text) to authenticated;

-- 2026-09-08 invoice deposits/dated manual receipts: authenticated invoker
-- wrappers retain the private writer's explicit auth.uid(), membership and
-- MFA checks. No direct document/receipt writes or private timing-context
-- privileges are granted. Existing managed-invoice guards remain mandatory.
revoke all on function public.record_document_payment_received(uuid,uuid,numeric,date,text),
  public.record_document_refund(uuid,uuid,numeric,date,text) from public, anon;
grant execute on function public.record_document_payment_received(uuid,uuid,numeric,date,text),
  public.record_document_refund(uuid,uuid,numeric,date,text) to authenticated;

-- 2026-09-08 annual mileage forecasts add bounded input columns to the existing
-- workspace_tax_estimates row. They use its unchanged workspace membership/MFA
-- select/insert/update/delete policies; no public access or new RPC is added.

-- Public business branding assets (migration 20260912105848).
-- storage.objects INSERT for authenticated is restricted to business-logos
-- and a first folder equal to auth.uid(); object names must be UUID paths.
-- No client UPDATE/DELETE permits rewriting issued document branding.
-- Account deletion removes all logo files with server-side service role.

-- Private record attachments (migration 20260912113740): authenticated
-- SELECT/INSERT/DELETE requires workspace membership plus MFA policy. There
-- is no client UPDATE. INSERT is blocked during account deletion. Storage
-- SELECT/INSERT/DELETE joins the exact object path to visible metadata; files
-- are not public. Privileged upload completion rechecks the reservation and
-- account-deletion state. Metadata cannot be removed while file bytes remain.
-- Storage completion triggers use unexposed definer functions because the
-- native supabase_storage_admin role has no application-table privileges.
-- They validate the original DB role, and authenticated calls additionally
-- require auth.uid(), workspace membership and MFA. EXECUTE is revoked from
-- public/anon/authenticated. Receipt completion uses the same boundary after
-- migration 20260912113752_receipt_storage_completion_role.sql.
