-- Workloop V1 schema contract
-- This file documents the database shape the Flutter app expects.
-- Treat it as the source for future Supabase migrations before adding V1 features.

-- Existing core tables used by the current app:
-- workspaces(id, name, industry, created_at)
-- workspace_members(id, workspace_id, user_id, created_at)
-- V1 owner invariant: destructive account deletion requires exactly one
-- workspace_members row and it must belong to the requesting user.
-- workspace_settings(workspace_id, working_hours jsonb, revenue_target numeric)
-- contacts(id, workspace_id, name, phone, email, address, notes, important_notes, status, preferred_contact_method, source, birthday, tags, last_activity_at, created_at)
-- services(id, workspace_id, name, duration_mins, price, description, show_on_profile, active, created_at)
-- service_add_ons(id, workspace_id, service_id, name, description, duration_mins, price, active, position, created_at, updated_at)
-- appointments(id, workspace_id, contact_id, service_id, title, start_time, end_time, price, status, notes, created_at)
-- appointment_items(id, workspace_id, appointment_id, item_kind, source_service_id, source_add_on_id, name, duration_mins, price, position, created_at)
-- invoices(id, workspace_id, contact_id, invoice_number, type, status, issue_date, due_date, subtotal, tax_rate, tax_amount, discount_value, total, amount_paid, notes, created_at)
-- expenses(id, workspace_id, amount, category, expense_date, notes, created_at, updated_at)
-- tasks(id, workspace_id, contact_id, appointment_id, title, priority, due_date, status, reminder_timing, completed_at, created_at, updated_at)
-- notes(id, workspace_id, contact_id, appointment_id, task_id, title, body, category, tags, pinned, archived, created_at, updated_at)
-- record_attachments(id, workspace_id, appointment_id, note_id, contact_id,
--   object_path, file_name, mime_type, size_bytes, content_hash, created_at)
-- Exactly one attachment target; composite workspace/target FKs prevent
-- cross-tenant links and block target deletion until private bytes are removed.
-- JPEG/PNG/WebP/PDF/UTF-8 text files are <=10 MiB. Metadata and paths are
-- immutable, stored in the private record-attachments bucket. See migration
-- 20260912113740_private_record_attachments.sql for the complete contract.
-- business_profiles(id, workspace_id, handle, created_at)

-- V1 extension fields.
create index if not exists workspace_members_user_id_idx
  on workspace_members(user_id);

alter table if exists business_profiles
  add column if not exists bio text,
  add column if not exists cover_photo_url text,
  add column if not exists gallery_image_urls jsonb not null default '[]'::jsonb,
  add column if not exists review_quotes jsonb not null default '[]'::jsonb,
  add column if not exists reviews_enabled boolean not null default false,
  add column if not exists gallery_enabled boolean not null default false,
  add column if not exists pay_now_enabled boolean not null default false,
  add column if not exists booking_mode text not null default 'manual',
  add column if not exists notice_text text,
  add column if not exists notice_start timestamptz,
  add column if not exists notice_end timestamptz;

alter table if exists services
  add column if not exists description text,
  add column if not exists show_on_profile boolean not null default true,
  add column if not exists active boolean not null default true;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'services_duration_mins_check'
       and conrelid = 'public.services'::regclass
  ) then
    alter table public.services
      add constraint services_duration_mins_check
      check (duration_mins between 5 and 1440);
  end if;
end $$;

create unique index if not exists services_workspace_id_id_uidx
  on services(workspace_id, id);

create table if not exists service_add_ons (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  service_id uuid not null,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  description text check (description is null or char_length(description) <= 500),
  duration_mins integer not null default 0 check (duration_mins between 0 and 1440),
  price numeric(12, 2) not null default 0 check (price between 0 and 1000000),
  active boolean not null default true,
  position integer not null default 0 check (position between 0 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_add_ons_workspace_service_fk
    foreign key (workspace_id, service_id)
    references services(workspace_id, id)
    on delete cascade
);
create unique index if not exists service_add_ons_workspace_id_id_uidx
  on service_add_ons(workspace_id, id);
create index if not exists service_add_ons_service_position_idx
  on service_add_ons(workspace_id, service_id, active, position, id);

alter table if exists contacts
  add column if not exists address text,
  add column if not exists tags text[],
  add column if not exists last_activity_at timestamptz,
  add column if not exists preferred_contact_method text not null default 'phone',
  add column if not exists source text,
  add column if not exists birthday date,
  add column if not exists important_notes text;

create index if not exists contacts_workspace_status_idx
  on contacts(workspace_id, status);
create index if not exists contacts_workspace_last_activity_idx
  on contacts(workspace_id, last_activity_at desc);
create index if not exists services_workspace_id_idx
  on services(workspace_id);

alter table if exists appointments
  add column if not exists location text,
  add column if not exists recurrence_rule text,
  add column if not exists recurrence_timezone text,
  add column if not exists recurrence_parent_id uuid;

create index if not exists appointments_workspace_id_idx
  on appointments(workspace_id);
create index if not exists appointments_contact_id_idx
  on appointments(contact_id);
create index if not exists appointments_service_id_idx
  on appointments(service_id);
create index if not exists appointments_workspace_schedule_lookup_idx
  on appointments(workspace_id, start_time, end_time)
  where status not in ('cancelled', 'no_show');

alter table if exists workspace_settings
  add column if not exists min_booking_notice_hours integer not null default 2,
  add column if not exists max_booking_window_weeks integer not null default 12,
  add column if not exists calendar_sync_enabled boolean not null default false;

alter table if exists tasks
  add column if not exists reminder_timing text not null default 'none',
  add column if not exists appointment_id uuid references appointments(id) on delete set null,
  add column if not exists completed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists tasks_workspace_id_idx
  on tasks(workspace_id);
create index if not exists tasks_contact_id_idx
  on tasks(contact_id);
create index if not exists tasks_appointment_id_idx
  on tasks(appointment_id);

create index if not exists invoices_workspace_id_idx
  on invoices(workspace_id);
create index if not exists invoices_contact_id_idx
  on invoices(contact_id);
create index if not exists invoices_appointment_id_idx
  on invoices(appointment_id);
create index if not exists invoice_line_items_invoice_id_idx
  on invoice_line_items(invoice_id);
create index if not exists invoice_line_items_workspace_id_idx
  on invoice_line_items(workspace_id);

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  amount numeric not null check (amount >= 0),
  category text not null default 'Other',
  expense_date date not null default current_date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists expenses_workspace_date_idx
  on expenses(workspace_id, expense_date desc);

create table if not exists task_checklist_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  task_id uuid not null references tasks(id) on delete cascade,
  title text not null,
  completed boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_checklist_items_workspace_id_idx
  on task_checklist_items(workspace_id);
create index if not exists task_checklist_items_task_id_position_idx
  on task_checklist_items(task_id, position);

create table if not exists notes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  contact_id uuid references contacts(id) on delete set null,
  appointment_id uuid references appointments(id) on delete set null,
  task_id uuid references tasks(id) on delete set null,
  title text not null default 'Untitled note',
  body text not null default '',
  category text not null default 'general'
    check (category in ('general', 'client', 'booking', 'money', 'idea')),
  tags text[] not null default '{}',
  pinned boolean not null default false,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notes_workspace_updated_idx
  on notes(workspace_id, archived, pinned desc, updated_at desc);
create index if not exists notes_workspace_category_idx
  on notes(workspace_id, category, updated_at desc);
create index if not exists notes_contact_id_idx
  on notes(contact_id);
create index if not exists notes_appointment_id_idx
  on notes(appointment_id);
create index if not exists notes_task_id_idx
  on notes(task_id);
create index if not exists notes_tags_idx
  on notes using gin(tags);

create table if not exists booking_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  name text not null,
  phone text not null,
  email text,
  phone_normalized text
    generated always as (regexp_replace(phone, '[^0-9]', '', 'g')) stored,
  service_id uuid references services(id) on delete set null,
  preferred_time_text text,
  requested_for timestamptz,
  requested_timezone text,
  message text,
  status text not null default 'pending',
  source_hash text,
  request_token uuid,
  created_at timestamptz not null default now()
);

create unique index if not exists booking_requests_workspace_id_id_uidx
  on booking_requests(workspace_id, id);
create unique index if not exists appointments_workspace_id_id_uidx
  on appointments(workspace_id, id);

create table if not exists booking_request_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  booking_request_id uuid not null,
  item_kind text not null check (item_kind in ('base', 'service', 'add_on')),
  source_service_id uuid,
  source_add_on_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  duration_mins integer not null check (duration_mins between 0 and 1440),
  price numeric(12, 2) not null check (price between 0 and 1000000),
  position integer not null check (position between 0 and 1000),
  created_at timestamptz not null default now(),
  constraint booking_request_items_workspace_request_fk
    foreign key (workspace_id, booking_request_id)
    references booking_requests(workspace_id, id)
    on delete cascade,
  constraint booking_request_items_workspace_service_fk
    foreign key (workspace_id, source_service_id)
    references services(workspace_id, id)
    on delete set null (source_service_id),
  constraint booking_request_items_workspace_add_on_fk
    foreign key (workspace_id, source_add_on_id)
    references service_add_ons(workspace_id, id)
    on delete set null (source_add_on_id),
  unique (booking_request_id, position)
);
create unique index if not exists booking_request_items_one_base_uidx
  on booking_request_items(booking_request_id) where item_kind = 'base';
create unique index if not exists booking_request_items_source_add_on_uidx
  on booking_request_items(booking_request_id, source_add_on_id)
  where source_add_on_id is not null;
create index if not exists booking_request_items_workspace_request_idx
  on booking_request_items(workspace_id, booking_request_id, position);

create table if not exists appointment_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  appointment_id uuid not null,
  item_kind text not null check (item_kind in ('base', 'service', 'add_on')),
  source_service_id uuid,
  source_add_on_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  duration_mins integer not null check (duration_mins between 0 and 1440),
  price numeric(12, 2) not null check (price between 0 and 1000000),
  position integer not null check (position between 0 and 1000),
  created_at timestamptz not null default now(),
  constraint appointment_items_workspace_appointment_fk
    foreign key (workspace_id, appointment_id)
    references appointments(workspace_id, id)
    on delete cascade,
  constraint appointment_items_workspace_service_fk
    foreign key (workspace_id, source_service_id)
    references services(workspace_id, id)
    on delete set null (source_service_id),
  constraint appointment_items_workspace_add_on_fk
    foreign key (workspace_id, source_add_on_id)
    references service_add_ons(workspace_id, id)
    on delete set null (source_add_on_id),
  unique (appointment_id, position)
);
create unique index if not exists appointment_items_one_base_uidx
  on appointment_items(appointment_id) where item_kind = 'base';
create unique index if not exists appointment_items_source_add_on_uidx
  on appointment_items(appointment_id, source_add_on_id)
  where source_add_on_id is not null;
create index if not exists appointment_items_workspace_appointment_idx
  on appointment_items(workspace_id, appointment_id, position);

alter table if exists booking_requests
  add column if not exists preferred_time_text text,
  add column if not exists requested_for timestamptz,
  add column if not exists requested_timezone text,
  add column if not exists email text,
  add column if not exists phone_normalized text
    generated always as (regexp_replace(phone, '[^0-9]', '', 'g')) stored,
  add column if not exists source_hash text,
  add column if not exists request_token uuid;

-- Email is nullable only for legacy requests. New public submissions use the
-- service-role-only v2 RPC, which requires and normalizes it.
-- app_private.require_booking_request_workspace_member() runs before insert
-- so a stale service-role public endpoint cannot write into a workspace after
-- its final member has gone. Public profile Edge handlers also check this
-- boundary before returning or accepting profile data.

create table if not exists app_private.transactional_email_outbox (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  booking_request_id uuid not null references booking_requests(id) on delete cascade,
  event text not null,
  recipient_email text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  delivery_expires_at timestamptz not null default (now() + interval '24 hours'),
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(event, booking_request_id)
);
create index if not exists booking_requests_workspace_id_idx
  on booking_requests(workspace_id);
create index if not exists booking_requests_service_id_idx
  on booking_requests(service_id);
create unique index if not exists
  booking_requests_workspace_request_token_idx
  on booking_requests(workspace_id, request_token)
  where request_token is not null;

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  deep_link text,
  dedupe_key text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table if exists notifications
  add column if not exists dedupe_key text;
create index if not exists notifications_workspace_id_idx
  on notifications(workspace_id);
create unique index if not exists notifications_workspace_dedupe_uidx
  on notifications(workspace_id, dedupe_key);

-- Notification routing contract:
-- app_private.route_notification_to_entity() runs before a notification is
-- inserted or its routing fields change. When a workspace-owned booking,
-- booking request, invoice/payment, task or note identifier is available, the
-- stored deep_link uses the corresponding UUID route. The trigger never
-- infers an entity across workspace boundaries. The Flutter route resolver
-- independently allowlists these paths and resolves their records through
-- authenticated, workspace-scoped providers/RLS.

create table if not exists notification_preferences (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null unique references workspaces(id) on delete cascade,
  all_notifications boolean not null default true,
  payment_received boolean not null default true,
  new_booking boolean not null default true,
  booking_request boolean not null default true,
  no_show boolean not null default true,
  invoice_overdue boolean not null default true,
  lead_followup boolean not null default true,
  appointment_reminder_15 boolean not null default false,
  task_due_morning boolean not null default false,
  morning_digest boolean not null default true,
  weekly_summary boolean not null default true,
  quiet_hours_enabled boolean not null default true,
  quiet_sundays boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists push_tokens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  user_id uuid not null,
  -- Validated registering session; legacy NULL bindings must re-register.
  -- No Auth foreign key or guessed session backfill. Delivery rechecks Auth.
  auth_session_id uuid,
  token text not null unique,
  platform text not null,
  app_build text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz
);
create index if not exists push_tokens_workspace_id_idx
  on push_tokens(workspace_id);

create table if not exists app_private.push_delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references notifications(id) on delete cascade,
  push_token_id uuid not null references push_tokens(id) on delete cascade,
  workspace_id uuid not null references workspaces(id) on delete cascade,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(notification_id, push_token_id)
);
alter table app_private.push_delivery_outbox enable row level security;
create index if not exists push_delivery_outbox_push_token_idx
  on app_private.push_delivery_outbox(push_token_id);
create index if not exists push_delivery_outbox_workspace_idx
  on app_private.push_delivery_outbox(workspace_id);

create table if not exists calendar_sync_accounts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  provider text not null,
  provider_account_id text not null,
  sync_enabled boolean not null default true,
  last_synced_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists calendar_sync_accounts_workspace_id_idx
  on calendar_sync_accounts(workspace_id);

create table if not exists account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid references workspaces(id) on delete set null,
  user_id uuid,
  email text not null,
  status text not null default 'requested',
  requested_at timestamptz not null default now(),
  requested_by_user_id uuid,
  processing_started_at timestamptz,
  completed_at timestamptz,
  completed_by text,
  completion_mode text,
  notes text
);
create index if not exists account_deletion_requests_workspace_id_idx
  on account_deletion_requests(workspace_id);

-- RLS expectation:
-- Every workspace-owned table must enforce access through workspace_members.
-- Membership helper functions live in app_private, not public, so they are not
-- exposed as REST/RPC endpoints.
-- Public profile reads should go through a trusted Edge Function.
-- Public booking-request writes should go through a trusted Edge Function.
-- Account deletion should be completed by a trusted server/edge-function path with service-role permissions.
-- See supabase/rls_policies.sql for the concrete V1 policy contract.

alter table if exists account_deletion_requests
  add column if not exists requested_by_user_id uuid,
  add column if not exists processing_started_at timestamptz,
  add column if not exists completed_by text,
  add column if not exists completion_mode text;

create unique index if not exists account_deletion_requests_open_user_idx
  on account_deletion_requests(workspace_id, requested_by_user_id)
  where status in ('requested', 'processing')
    and requested_by_user_id is not null;

create table if not exists account_deletion_audit (
  id uuid primary key default gen_random_uuid(),
  request_id uuid,
  workspace_id uuid,
  user_id uuid,
  email_hash text,
  requested_at timestamptz,
  completed_at timestamptz not null default now(),
  completed_by text not null,
  completion_mode text not null,
  workspace_deleted boolean not null default false,
  auth_user_deleted boolean not null default false,
  notes text
);
alter table if exists account_deletion_audit enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'account_deletion_requests_status_check'
      and conrelid = 'public.account_deletion_requests'::regclass
  ) then
    alter table public.account_deletion_requests
      add constraint account_deletion_requests_status_check
      check (status in ('requested', 'processing', 'completed', 'rejected', 'canceled'))
      not valid;
  end if;
end $$;

create index if not exists booking_requests_source_hash_created_idx
  on booking_requests(workspace_id, source_hash, created_at desc);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'booking_requests_normalized_phone_check'
      and conrelid = 'public.booking_requests'::regclass
  ) then
    alter table public.booking_requests
      add constraint booking_requests_normalized_phone_check
      check (char_length(phone_normalized) between 7 and 32)
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'booking_requests_status_check'
      and conrelid = 'public.booking_requests'::regclass
  ) then
    alter table public.booking_requests
      add constraint booking_requests_status_check
      check (status in ('pending', 'contacted', 'confirmed', 'declined'))
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'booking_requests_public_text_bounds_check'
      and conrelid = 'public.booking_requests'::regclass
  ) then
    alter table public.booking_requests
      add constraint booking_requests_public_text_bounds_check
      check (
        char_length(btrim(name)) between 1 and 80
        and char_length(btrim(phone)) between 7 and 32
        and (preferred_time_text is null or char_length(preferred_time_text) <= 160)
        and (message is null or char_length(message) <= 1000)
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'business_profiles_handle_format_check'
      and conrelid = 'public.business_profiles'::regclass
  ) then
    alter table public.business_profiles
      add constraint business_profiles_handle_format_check
      check (
        handle is null
        or handle = ''
        or handle ~ '^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$'
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'business_profiles_booking_mode_check'
      and conrelid = 'public.business_profiles'::regclass
  ) then
    alter table public.business_profiles
      add constraint business_profiles_booking_mode_check
      check (booking_mode in ('manual', 'closed'))
      not valid;
  end if;
end $$;

create unique index if not exists business_profiles_handle_unique_idx
  on public.business_profiles(lower(handle))
  where handle is not null and handle <> '';

create schema if not exists app_private;

create table if not exists app_private.edge_rate_limit_events (
  id bigint generated always as identity primary key,
  scope text not null check (
    scope in (
      'booking_source',
      'booking_phone',
      'booking_availability',
      'places_autocomplete',
      'places_details',
      'waitlist_email'
    )
  ),
  resource_key text not null default '',
  subject_key text not null,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists edge_rate_limit_subject_window_idx
  on app_private.edge_rate_limit_events(
    scope,
    resource_key,
    subject_key,
    created_at desc
  );
create index if not exists edge_rate_limit_created_at_idx
  on app_private.edge_rate_limit_events(created_at);

alter table app_private.edge_rate_limit_events enable row level security;
revoke all on table app_private.edge_rate_limit_events
  from public, anon, authenticated;
grant select, insert, delete on table app_private.edge_rate_limit_events
  to service_role;
drop policy if exists edge_rate_limit_events_deny_clients
  on app_private.edge_rate_limit_events;
create policy edge_rate_limit_events_deny_clients
  on app_private.edge_rate_limit_events
  for all
  to anon, authenticated
  using (false)
  with check (false);
revoke all on sequence app_private.edge_rate_limit_events_id_seq
  from public, anon, authenticated;
grant usage, select on sequence app_private.edge_rate_limit_events_id_seq
  to service_role;

create table if not exists app_private.launch_waitlist (
  id bigint generated always as identity primary key,
  email text not null unique,
  source text not null default 'website',
  status text not null default 'active'
    check (status in ('active', 'invited', 'unsubscribed')),
  consent_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint launch_waitlist_email_check check (
    email = lower(btrim(email))
    and char_length(email) between 3 and 254
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint launch_waitlist_source_check check (
    source ~ '^[a-z0-9_-]{1,40}$'
  )
);

create index if not exists launch_waitlist_status_created_idx
  on app_private.launch_waitlist(status, created_at desc);

alter table app_private.launch_waitlist enable row level security;
revoke all on table app_private.launch_waitlist
  from public, anon, authenticated;
grant select, insert, update on table app_private.launch_waitlist
  to service_role;
revoke all on sequence app_private.launch_waitlist_id_seq
  from public, anon, authenticated;
grant usage, select on sequence app_private.launch_waitlist_id_seq
  to service_role;

create table if not exists app_private.waitlist_email_outbox (
  id uuid primary key default gen_random_uuid(),
  waitlist_id bigint not null references app_private.launch_waitlist(id)
    on delete cascade,
  event text not null default 'launch_waitlist_joined'
    check (event = 'launch_waitlist_joined'),
  recipient_email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default clock_timestamp(),
  lease_token uuid,
  lease_expires_at timestamptz,
  delivery_expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique (event, waitlist_id)
);
alter table app_private.waitlist_email_outbox enable row level security;
revoke all on table app_private.waitlist_email_outbox
  from public, anon, authenticated;
grant select, insert, update on table app_private.waitlist_email_outbox
  to service_role;

create table if not exists app_private.account_welcome_email_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event text not null default 'account_email_verified'
    check (event = 'account_email_verified'),
  recipient_email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default clock_timestamp(),
  lease_token uuid,
  lease_expires_at timestamptz,
  delivery_expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique (event, user_id)
);
alter table app_private.account_welcome_email_outbox enable row level security;
revoke all on table app_private.account_welcome_email_outbox
  from public, anon, authenticated;
grant select, insert, update on table app_private.account_welcome_email_outbox
  to service_role;

create table if not exists app_private.account_deletion_email_outbox (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.account_deletion_requests(id)
    on delete cascade,
  event text not null
    check (event in ('deletion_requested', 'account_deleted')),
  recipient_email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default clock_timestamp(),
  lease_token uuid,
  lease_expires_at timestamptz,
  delivery_expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique (event, request_id)
);
alter table app_private.account_deletion_email_outbox enable row level security;
revoke all on table app_private.account_deletion_email_outbox
  from public, anon, authenticated;
grant select, insert, update on table app_private.account_deletion_email_outbox
  to service_role;

create table if not exists app_private.operational_alerts (
  id uuid primary key default gen_random_uuid(),
  alert_key text not null unique,
  category text not null,
  severity text not null check (severity in ('warning', 'critical')),
  message text not null check (char_length(message) between 1 and 500),
  status text not null default 'open'
    check (status in ('open', 'resolved')),
  first_seen_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  last_notified_at timestamptz,
  resolved_at timestamptz
);
alter table app_private.operational_alerts enable row level security;
revoke all on table app_private.operational_alerts
  from public, anon, authenticated;
grant select, insert, update on table app_private.operational_alerts
  to service_role;

create table if not exists app_private.payment_counters (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  next_number bigint not null default 1 check (next_number > 0)
);

create table if not exists app_private.workflow_idempotency (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null,
  operation text not null,
  idempotency_key text not null,
  result jsonb,
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id, operation, idempotency_key)
);

revoke all on table app_private.workflow_idempotency
  from public, anon, authenticated;
create index if not exists workflow_idempotency_created_at_idx
  on app_private.workflow_idempotency(created_at);

-- RPC contracts expected by the launch clients:
--
-- Edge-only launch list intake and delivery:
-- public.join_launch_waitlist(text, text, text) returns text
-- public.claim_waitlist_welcome_emails(integer) returns table (...)
-- public.finish_waitlist_welcome_email(uuid, uuid, boolean, text, text)
-- The join is transactional with a unique private outbox record. Claims use a
-- short lease, capped retry backoff, a 24-hour delivery window, and service
-- role only grants. The scheduled transactional-email drain supplies recovery.
--
-- Edge-only public booking intake:
-- public.create_public_booking_request(
--   uuid, text, text, uuid, text, text, text, uuid
-- ) returns table (booking_request_id uuid, outcome text)
-- SECURITY DEFINER with an explicit search_path. EXECUTE is revoked from
-- PUBLIC, anon, and authenticated, then granted only to service_role. It
-- validates the workspace/service, serializes rate checks, preserves request
-- token idempotency, and inserts the request/counters atomically. The
-- allow_booking_request_notification trigger suppresses its notification when
-- all_notifications or booking_request preferences are disabled.
-- public.create_public_booking_request_v3(..., uuid[]) adds a bounded list of
-- catalog add-on IDs and snapshots trusted service/add-on values. Legacy v2
-- overloads remain available to older clients.
-- public.get_public_booking_slot_suggestions_v2(text, uuid, text, uuid[])
-- validates the same active add-on IDs and uses their server-summed duration;
-- it returns capped UTC starts without appointment or occupancy metadata.
-- public.get_public_booking_slot_suggestions_v3(
--   text, uuid, text, uuid[], date
-- ) keeps the default response compatible and can restrict suggestions to one
-- customer-selected workspace-local date.
--
-- Authenticated transactional workflows:
-- public.create_task_workflow(jsonb) returns jsonb
-- public.create_booking_workflow(jsonb) returns jsonb
-- public.complete_booking_workflow(jsonb) returns jsonb
-- These public wrappers are SECURITY INVOKER, revoked from PUBLIC/anon, and
-- granted to authenticated. Private implementations validate auth.uid(),
-- workspace membership, linked-record ownership, conflicts, payload bounds,
-- and stable idempotency keys. Booking creation reuses an existing contact
-- when workspace-scoped digit-normalized phone values match; no country-code
-- inference is performed.

create unique index if not exists invoices_workspace_invoice_number_unique_idx
  on public.invoices(workspace_id, invoice_number)
  where invoice_number is not null;

-- A private before-insert trigger assigns PAY-### numbers when invoice_number
-- is omitted. Flutter should not generate payment numbers by counting rows.

-- 2026-09-05 email journey contract (authoritative rollout: dated migrations).
-- New workspaces: [1440,60]. Existing workspaces stay [] until configured.
-- User-owned tips: record_account_email_choice/get_account_email_preference;
-- touch_workloop_email_activity updates authenticated activity only.
-- Recipient mappings, reminder leases and marketing queues stay in app_private.
-- Worker RPCs are service-only; elevated Auth reads use private definer helpers.
alter table if exists workspace_settings
  add column if not exists customer_reminder_minutes integer[] not null default '{}';
alter table if exists workspace_settings
  alter column customer_reminder_minutes set default array[1440,60];

-- 2026-09-05 customer lifecycle emails (migration 20260905161843):
-- app_private.customer_event_emails + customer_email_suppression are service-only.
-- public.queue_payment_request_email(uuid,boolean,text) is authenticated,
-- membership/MFA checked, recipient-bound and deduplicated per Stripe transaction.
-- claim/customer_event_still_allowed/finish/suppress RPCs are service-only invokers.
-- public.account_email_context(uuid,integer) is a service-only wrapper over a
-- private Auth-aware definer; missing setup records and weekly aggregates are computed.

-- 2026-09-08 connected quotes/invoices (20260908180121_connected_quotes_and_invoices).
-- business_documents is the customer-facing commercial record; quotes and
-- drafts are intentionally absent from invoices so older clients cannot count
-- them as money owed. Columns: id, workspace_id, contact_id, appointment_id,
-- type (quote/invoice), status, invoice_number, issue_date, due_date,
-- service_date, subtotal, tax_rate, tax_amount, total, notes,
-- payment_instructions, business_snapshot, client_snapshot, items (bounded
-- JSON array), revision, issued_at, created_at, source_quote_id, invoice_id.
-- Business snapshot text fields: name/address/email/phone/legal_name/
-- company_number/vat_number; client snapshot name/address/email.
-- Quantities and unit prices accept up to 2 decimal places. The server
-- rounds each line, computes subtotal and document-wide VAT (0/5/20), and
-- rejects nonfinite, negative, excessive and client-supplied total overrides.
-- Nonzero VAT requires a VAT number. Issued invoices require legal name,
-- business/client names and addresses, supply date and valid due date.
-- Issuing one invoice atomically allocates a workspace number and inserts one
-- existing invoices row plus invoice_line_items, linked by source_document_id.
-- Issued commercial details/lines cannot be edited or deleted. Only unpaid
-- invoices without active Stripe collection may be cancelled; existing
-- payment reconciliation fields remain writable. Workspace deletion cascades.
-- Contact/booking deletion clears links while issued snapshots remain fixed.
-- app_private.business_document_counters serialises invoice/quote numbering.
-- app_private.business_document_manual_payments retains idempotency keys.
-- business_document_receipts(id,workspace_id,invoice_id,amount,received_at)
-- is read-only receipt timing derived from linked invoice amount_paid changes:
-- partial receipts and refunds are signed deltas in their actual recorded
-- period. No legacy PAY balance/history is backfilled or reinterpreted.
-- Document and receipt SELECT require workspace membership and existing MFA
-- policy. No anon reads or authenticated direct document/receipt writes.
-- Public SECURITY INVOKER RPCs call an unexposed member/MFA-checked writer:
-- save_business_document(uuid,jsonb,jsonb,uuid default null,integer default null)
-- issue_business_document(uuid,uuid,integer default null)
-- set_quote_status(uuid,uuid,text,integer default null)
-- convert_quote_to_invoice(uuid,uuid)
-- delete_business_document(uuid,uuid) -- draft only
-- cancel_business_document(uuid,uuid) -- issued, unpaid, no active collection
-- record_document_payment(uuid,uuid,numeric,text) -- bounded amount + retry key
-- Mutation responses are document JSON with derived amount_paid; deletion
-- returns id/deleted. Creation UUID, issue, conversion and payment keys make
-- retries idempotent. Revision guards reject stale draft edits. Conversion
-- requires accepted quote and creates at most one reviewable invoice draft.
-- Creation/update response-loss retries return success only for exactly equal
-- normalized content; changed retries require reopening the saved revision.

-- 2026-09-08 expense support (20260908180227_expense_receipts_mileage_tax_estimates).
-- expense_receipts stores immutable private object metadata against an
-- expense/workspace FK; expense-receipts Storage bucket allows bounded
-- PDF/JPEG/PNG objects and is never public. Object policies resolve the full
-- reserved metadata path with workspace/MFA isolation.
-- mileage_entries stores journey_date, integer miles_hundredths, purpose,
-- vehicle identity and vehicle_type. workspace_tax_estimates stores reviewed
-- 2026/27 inputs and rules_version, not an asserted tax liability or HMRC filing.
-- Each table uses existing workspace membership/MFA RLS; workspace removal
-- cascades relational records. Receipt Storage cleanup precedes account removal.

-- Hosted release 2026-09-08: after stored-body SHA-256 verification, only the
-- three newly deployed local migration filenames were reconciled to the hosted
-- versions: recurring_booking_series 20260908190556,
-- connected_quotes_and_invoices 20260908190606, and
-- expense_receipts_mileage_tax_estimates 20260908190613.
-- SQL bodies are unchanged; historical migration drift was not repaired.

-- 2026-09-08 invoice review (20260908193611_invoice_deposits_and_manual_refunds).
-- business_documents adds prices_include_vat boolean default false and
-- deposit_type (none/fixed/percentage), deposit_value numeric, deposit_amount
-- numeric(14,2), deposit_due_date. A fixed value is GBP; a percentage is 0..100.
-- Positive deposit requests are computed from and bounded by the full total;
-- none requires zero values/no date. Issue validates the deposit due date lies
-- between issue and final due dates. Requesting a deposit records no receipt.
-- invoices adds deposit_amount/date for managed documents only. Partial cash,
-- bank and card receipts all reduce the same existing invoice balance once.
-- Gross entry extracts VAT per rounded line using rate/(100+rate); line tax
-- rounds half-up to pennies, net + VAT always equals the agreed gross price.
-- Gross JSON items retain input quantity/unit_price/line_total and add
-- net_line_total, vat_amount, unit_price_ex_vat (up to four decimal places).
-- invoice_line_items uses the net unit/line values. Net entry retains the
-- original document-wide tax calculation. Issued pricing mode is immutable.
-- Client snapshots now also support phone. Invoice issue requires either a
-- business email or phone. Settings are copied into new draft snapshots only.
-- Booking issue may adopt exactly one matching, uncollected sent/overdue PAY
-- with no managed source, card transaction or card reservation. Its identity,
-- total and reference remain; reviewed lines and details are attached once.
-- This cannot create a second outstanding balance for that booking.
-- record_document_payment_received(uuid,uuid,numeric,date,text) and
-- record_document_refund(uuid,uuid,numeric,date,text) accept a positive amount,
-- explicit actual civil date and stable retry key; manual refunds are capped
-- to amount_paid minus stripe_amount_paid. Card refunds still use Stripe.
-- app_private.business_document_manual_payments extends its existing command
-- metadata with signed amount, received_at, received_date, receipt_id,
-- transaction_id and receipt_recorded. Client roles cannot read/write it.
-- The invoice delta trigger consumes this private context in the same
-- transaction and appends one signed business_document_receipts event.
-- Other reconciliation writes use their current timestamp. Retries compare
-- original signed amount/civil date even if business timezone has changed.
-- New entries reject future dates; no session GUC can override receipt time.
-- No existing cash history is backfilled. Membership/MFA, immutable issued
-- content, current card-collection guards and workspace cascades remain.

-- Hosted review release: the four new local filenames were reconciled only
-- after stored-body SHA verification: annual mileage 20260908200018,
-- invoice defaults 20260908200023, deposits/refunds 20260908200032,
-- recurring retry recovery 20260908200053. SQL bodies are unchanged.

-- 2026-09-08 reviewed invoice setup (20260908193610_business_document_defaults).
-- workspace_settings adds nullable business_structure (sole_trader,
-- limited_company, other), business_legal_name (200 chars), company number and
-- VAT number (40 chars each), default_payment_instructions (3000 chars), and
-- default_quote_validity_days (1..365, default 30). Existing business_address,
-- customer_contact_email/phone, default_payment_terms_days and default_tax_rate
-- remain canonical. Trading name comes from workspaces.name. No Auth identity
-- inference or historical document snapshot backfill is performed.
-- Existing workspace-settings membership/MFA policies and grants are unchanged.
-- Public profile and email payloads remain explicit field allowlists: these
-- additions do not publish legal details or payment instructions by themselves.

-- 2026-09-08 annual mileage review (20260908193503_reviewed_annual_mileage_estimate).
-- workspace_tax_estimates adds annual_car_van_miles_hundredths and
-- annual_motorcycle_miles_hundredths, each nullable bigint 0..100000000.
-- annual_mileage_pair requires both null or both supplied. Null keeps existing
-- estimates readable until review; these annual forecasts include logged
-- mileage but do not create or replace mileage_entries. Tax pence and rates
-- are computed by the versioned client rules, not stored as a final liability.
-- Existing workspace membership/MFA RLS, export and deletion cascades apply.
-- Reject invalid enabled hours before the onboarding transaction writes records.
-- Closed days may keep unfinished times; active blocks must be same-day and
-- non-overlapping. Both legacy open/close and current blocks payloads are valid.
-- Existing authenticated wrapper, SECURITY INVOKER, grants and retry semantics
-- remain unchanged. No rows are rewritten and no schema columns are added.

create or replace function app_private.complete_onboarding_implementation(
  business_name text,
  industry_name text,
  profile_handle text,
  service_rows jsonb,
  working_hours_value jsonb,
  revenue_target_value numeric,
  first_booking_value jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_workspace_id uuid;
  new_workspace_id uuid := gen_random_uuid();
  booking_contact_id uuid;
  booking_service_id uuid;
  booking_service_name text;
  booking_start timestamptz;
  booking_end timestamptz;
  service_row jsonb;
  hours_day record;
  hours_blocks jsonb;
  hours_block jsonb;
  hours_start text;
  hours_end text;
  start_minute integer;
  end_minute integer;
  day_ranges int4range[];
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  -- Serialise retries for one account. A completed first call is returned
  -- unchanged; a failed call rolls back fully before the lock is released.
  perform pg_advisory_xact_lock(hashtextextended(caller_id::text, 0));

  select wm.workspace_id
    into existing_workspace_id
    from public.workspace_members wm
   where wm.user_id = caller_id
   order by wm.created_at, wm.id
   limit 1;

  if existing_workspace_id is not null then
    return existing_workspace_id;
  end if;

  business_name := btrim(coalesce(business_name, ''));
  industry_name := btrim(coalesce(industry_name, ''));
  profile_handle := lower(btrim(coalesce(profile_handle, '')));
  service_rows := coalesce(service_rows, '[]'::jsonb);
  working_hours_value := coalesce(working_hours_value, '{}'::jsonb);
  revenue_target_value := coalesce(revenue_target_value, 0);

  if char_length(business_name) not between 2 and 120 then
    raise exception 'Business name must be between 2 and 120 characters';
  end if;
  if char_length(industry_name) > 80 then
    raise exception 'Industry must be at most 80 characters';
  end if;
  if profile_handle !~ '^[a-z0-9][a-z0-9_-]{2,39}$' then
    raise exception 'Handle must be 3-40 lowercase letters, numbers, underscores, or hyphens';
  end if;
  if jsonb_typeof(service_rows) <> 'array'
     or jsonb_array_length(service_rows) > 50 then
    raise exception 'Services must be an array containing at most 50 items';
  end if;
  if jsonb_typeof(working_hours_value) <> 'object' then
    raise exception 'Working hours must be an object';
  end if;
  for hours_day in select key, value from jsonb_each(working_hours_value)
  loop
    if hours_day.key not in ('Mon','Tue','Wed','Thu','Fri','Sat','Sun',
        'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')
       or jsonb_typeof(hours_day.value) is distinct from 'object'
       or jsonb_typeof(hours_day.value -> 'enabled') is distinct from 'boolean' then
      raise exception '%: choose whether this is a working day.', hours_day.key
        using errcode = '22023';
    end if;
    if hours_day.value -> 'enabled' = 'false'::jsonb then
      continue;
    end if;
    hours_blocks := case when hours_day.value ? 'blocks'
      then hours_day.value -> 'blocks'
      else jsonb_build_array(jsonb_build_object(
        'start', coalesce(hours_day.value -> 'start', hours_day.value -> 'open'),
        'end', coalesce(hours_day.value -> 'end', hours_day.value -> 'close')))
      end;
    if jsonb_typeof(hours_blocks) is distinct from 'array' then
      raise exception '%: add at least one working block.', hours_day.key
        using errcode = '22023';
    end if;
    if jsonb_array_length(hours_blocks) = 0 then
      raise exception '%: add at least one working block.', hours_day.key
        using errcode = '22023';
    end if;
    day_ranges := array[]::int4range[];
    for hours_block in select value from jsonb_array_elements(hours_blocks)
    loop
      hours_start := hours_block ->> 'start';
      hours_end := hours_block ->> 'end';
      if jsonb_typeof(hours_block -> 'start') is distinct from 'string'
         or jsonb_typeof(hours_block -> 'end') is distinct from 'string'
         or hours_start !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
         or hours_end !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception '%: use valid times such as 09:00.', hours_day.key
          using errcode = '22023';
      end if;
      start_minute := split_part(hours_start, ':', 1)::integer * 60
        + split_part(hours_start, ':', 2)::integer;
      end_minute := split_part(hours_end, ':', 1)::integer * 60
        + split_part(hours_end, ':', 2)::integer;
      if end_minute <= start_minute then
        raise exception '%: closing time must be after opening time.', hours_day.key
          using errcode = '22023';
      end if;
      if exists (select 1 from unnest(day_ranges) as r
          where r && int4range(start_minute, end_minute, '[)')) then
        raise exception '%: working blocks must not overlap.', hours_day.key
          using errcode = '22023';
      end if;
      day_ranges := array_append(day_ranges,
        int4range(start_minute, end_minute, '[)'));
    end loop;
  end loop;
  if revenue_target_value < 0 then
    raise exception 'Revenue target cannot be negative';
  end if;

  insert into public.workspaces(id, name, industry)
  values (new_workspace_id, business_name, nullif(industry_name, ''));

  insert into public.workspace_members(workspace_id, user_id)
  values (new_workspace_id, caller_id);

  insert into public.workspace_settings(
    workspace_id,
    working_hours,
    revenue_target
  ) values (
    new_workspace_id,
    working_hours_value,
    revenue_target_value
  );

  insert into public.business_profiles(workspace_id, handle)
  values (new_workspace_id, profile_handle);

  for service_row in select value from jsonb_array_elements(service_rows)
  loop
    if jsonb_typeof(service_row) <> 'object'
       or char_length(btrim(coalesce(service_row ->> 'name', ''))) not between 1 and 120
       or coalesce((service_row ->> 'duration_mins')::integer, 0) not between 1 and 1440
       or coalesce((service_row ->> 'price')::numeric, -1) < 0 then
      raise exception 'A service contains invalid values';
    end if;

    insert into public.services(
      workspace_id,
      name,
      duration_mins,
      price,
      description
    ) values (
      new_workspace_id,
      btrim(service_row ->> 'name'),
      (service_row ->> 'duration_mins')::integer,
      (service_row ->> 'price')::numeric,
      nullif(regexp_replace(
        service_row ->> 'description',
        '^[[:space:]]+|[[:space:]]+$', '', 'g'
      ), '')
    );
  end loop;

  if first_booking_value is not null
     and first_booking_value <> 'null'::jsonb then
    if jsonb_typeof(first_booking_value) <> 'object' then
      raise exception 'First booking must be an object';
    end if;

    booking_service_name := nullif(btrim(first_booking_value ->> 'service_name'), '');
    booking_start := (first_booking_value ->> 'start_time')::timestamptz;
    booking_end := (first_booking_value ->> 'end_time')::timestamptz;

    if char_length(btrim(coalesce(first_booking_value ->> 'client_name', ''))) not between 1 and 120
       or booking_start is null
       or booking_end is null
       or booking_end <= booking_start then
      raise exception 'First booking contains invalid values';
    end if;

    if booking_service_name is not null then
      select s.id
        into booking_service_id
        from public.services s
       where s.workspace_id = new_workspace_id
         and s.name = booking_service_name
       order by s.created_at, s.id
       limit 1;
    end if;

    insert into public.contacts(workspace_id, name, status)
    values (
      new_workspace_id,
      btrim(first_booking_value ->> 'client_name'),
      'active'
    )
    returning id into booking_contact_id;

    insert into public.appointments(
      workspace_id,
      contact_id,
      service_id,
      title,
      start_time,
      end_time,
      price,
      status
    ) values (
      new_workspace_id,
      booking_contact_id,
      booking_service_id,
      coalesce(booking_service_name, 'Booking'),
      booking_start,
      booking_end,
      coalesce(
        (select s.price from public.services s where s.id = booking_service_id),
        0
      ),
      'scheduled'
    );
  end if;

  return new_workspace_id;
end;
$$;
-- The detail editor changes an existing booking and its service-item snapshot
-- in one transaction. Catalogue history is retained for ordinary edits; an
-- explicit service/name replacement creates the newly chosen work snapshot.
-- Issued documents have independent immutable items and are never updated here.
create function app_private.edit_booking_workflow(
  p_appointment_id uuid, p_values jsonb, p_replace_service_items boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_booking public.appointments;
  v_saved public.appointments;
  v_base_id uuid;
  v_other_price numeric;
  v_item_count integer;
  v_duration integer;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'Multi-factor authentication is required' using errcode = '42501';
  end if;
  select * into v_booking from public.appointments
    where id = p_appointment_id
      and app_private.is_workspace_member(workspace_id)
    for update;
  if not found then
    raise exception 'Booking unavailable' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object'
     or not (p_values ?& array['contact_id','service_id','title','start_time',
       'end_time','location','notes','price'])
     or (p_values - array['contact_id','service_id','title','start_time',
       'end_time','location','notes','price']) <> '{}'::jsonb then
    raise exception 'Invalid booking edit' using errcode = '22023';
  end if;
  if p_values->>'contact_id' is not null and not exists (
    select 1 from public.contacts where id = (p_values->>'contact_id')::uuid
      and workspace_id = v_booking.workspace_id
  ) then
    raise exception 'Client unavailable' using errcode = '42501';
  end if;
  if p_values->>'service_id' is not null and not exists (
    select 1 from public.services where id = (p_values->>'service_id')::uuid
      and workspace_id = v_booking.workspace_id
  ) then
    raise exception 'Service unavailable' using errcode = '42501';
  end if;
  if not coalesce(p_replace_service_items, false)
     and (p_values->>'service_id')::uuid is distinct from v_booking.service_id then
    raise exception 'Changed service requires a new snapshot' using errcode = '22023';
  end if;
  v_duration := extract(epoch from ((p_values->>'end_time')::timestamptz -
    (p_values->>'start_time')::timestamptz)) / 60;
  if v_duration is null or v_duration not between 1 and 1440
     or (p_values->>'price')::numeric is null
     or (p_values->>'price')::numeric not between 0 and 1000000
     or nullif(btrim(p_values->>'title'), '') is null then
    raise exception 'Enter a valid booking name, duration and price' using errcode = '22023';
  end if;

  update public.appointments set
    contact_id = (p_values->>'contact_id')::uuid,
    service_id = (p_values->>'service_id')::uuid,
    title = btrim(p_values->>'title'),
    start_time = (p_values->>'start_time')::timestamptz,
    end_time = (p_values->>'end_time')::timestamptz,
    location = nullif(btrim(p_values->>'location'), ''),
    notes = nullif(btrim(p_values->>'notes'), ''),
    price = (p_values->>'price')::numeric
  where id = p_appointment_id returning * into v_saved;

  select count(*) into v_item_count from public.appointment_items
    where appointment_id = p_appointment_id;
  if coalesce(p_replace_service_items, false) or v_item_count = 0 then
    if char_length(v_saved.title) > 80 then
      raise exception 'Use a service name of 80 characters or fewer' using errcode = '22023';
    end if;
    delete from public.appointment_items where appointment_id = p_appointment_id;
    insert into public.appointment_items(workspace_id, appointment_id,
      item_kind, source_service_id, name, duration_mins, price, position)
    values (v_saved.workspace_id, v_saved.id, 'base', v_saved.service_id,
      v_saved.title, v_duration, v_saved.price, 0);
  elsif v_saved.price is distinct from v_booking.price then
    -- The editor changes the booking total. Retain selected extras/other
    -- services at their agreed prices and apply the change to the base item.
    select id into v_base_id from public.appointment_items
      where appointment_id = p_appointment_id and item_kind = 'base';
    select coalesce(sum(price), 0) into v_other_price
      from public.appointment_items
      where appointment_id = p_appointment_id and id <> v_base_id;
    if v_base_id is null or v_saved.price < v_other_price then
      raise exception 'The total must cover the other booked services and extras. Change the service to replace the item breakdown.'
        using errcode = '22023';
    end if;
    update public.appointment_items set price = v_saved.price - v_other_price
      where id = v_base_id;
  end if;
  if v_item_count = 1 and not coalesce(p_replace_service_items, false) then
    update public.appointment_items set duration_mins = v_duration
      where appointment_id = p_appointment_id;
  end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.position), '[]'::jsonb)
    into v_items from public.appointment_items i where i.appointment_id = p_appointment_id;
  return to_jsonb(v_saved) || jsonb_build_object(
    'appointment_items', v_items,
    'contacts', (select jsonb_build_object('name', name) from public.contacts where id = v_saved.contact_id),
    'services', (select jsonb_build_object('name', name) from public.services where id = v_saved.service_id));
end;
$$;
revoke all on function app_private.edit_booking_workflow(uuid,jsonb,boolean) from public,anon;
grant execute on function app_private.edit_booking_workflow(uuid,jsonb,boolean) to authenticated;

create function public.edit_booking_workflow(
  p_appointment_id uuid, p_values jsonb, p_replace_service_items boolean default false
) returns jsonb language sql security invoker set search_path = '' as $$
  select app_private.edit_booking_workflow(p_appointment_id, p_values, p_replace_service_items);
$$;
revoke all on function public.edit_booking_workflow(uuid,jsonb,boolean) from public,anon;
grant execute on function public.edit_booking_workflow(uuid,jsonb,boolean) to authenticated;

-- Business branding uses the existing workspaces.logo_url column. Public
-- business-logos Storage bucket: PNG/JPEG only, maximum 2 MiB, immutable
-- <auth user UUID>/<object UUID>.(png|jpg). Issued documents freeze its URL.
-- See 20260912105848_business_logos.sql for bucket configuration and policies.
