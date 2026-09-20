# Workloop Database Rules

Last updated: 2026-08-15

## Source of Truth

Database truth is split across:

- Live Supabase project `imtbyrvsonzvtddswbtb`.
- `supabase/schema_contract.sql`.
- `supabase/rls_policies.sql`.
- Flutter repositories and models.
- Notion Database Schema, which is older than the current implementation in several places.

For future work:

1. Update `supabase/schema_contract.sql`.
2. Apply a named Supabase migration.
3. Update repositories/models/tests.
4. Verify RLS.
5. Update docs if the product meaning changes.

## Live Tables

Live public tables as of 2026-07-26:

- `workspaces`
- `workspace_settings`
- `workspace_members`
- `contacts`
- `services`
- `appointments`
- `tasks`
- `task_checklist_items`
- `invoices`
- `invoice_line_items`
- `expenses`
- `business_profiles`
- `booking_requests`
- `notifications`
- `notification_preferences`
- `push_tokens`
- `calendar_sync_accounts`
- `account_deletion_requests`
- `account_deletion_audit`

All listed live tables currently have RLS enabled.

Private launch-hardening state lives in the unexposed `app_private` schema:

- `workflow_idempotency` records the result of authenticated booking/task
  workflows by workspace, user, operation, and idempotency key.
- `edge_rate_limit_events` stores short-lived public booking and Google Places
  rate-limit events, plus salted-hash waitlist throttling events.
  `anon` and `authenticated` have no direct access.
- `launch_waitlist` stores normalized launch-interest email addresses, consent
  time, source and operational status. It is Edge-only and has no anonymous or
  authenticated table grants.
- `waitlist_email_outbox` stores one durable welcome-delivery job per launch
  signup. It is private, service-role only, leased for delivery, retried with a
  cap, and never exposes recipient or provider state to web or app clients.
- `account_welcome_email_outbox` stores one durable welcome job when an Auth
  user first becomes email-verified, including already-confirmed provider
  signups. It does not backfill existing users, is service-role only, retries
  for at most 24 hours and cascades with the Auth user.
- `account_deletion_email_outbox` stores one request-received email and one
  deletion-complete email per retained deletion request. Both messages are
  created by database state transitions, remain private, and retry for no more
  than eight attempts or 24 hours.

## Table Purposes

`workspaces`

- One business account/workspace.
- Solo by default for V1.

`workspace_members`

- Connects Supabase auth users to workspaces.
- Workloop V1 permits one owner/member and has no collaborator workflow.
- The live table has no role column. Until an explicit ownership-role migration
  exists, destructive account deletion requires exactly one workspace
  membership and requires that membership to belong to the requester.

`workspace_settings`

- Business settings: timezone, address, working hours, revenue target, reminders, booking notice/window, calendar sync flag, and invoice defaults.

`contacts`

- CRM records.
- Stores name, phone, email, address, status, notes, important notes, tags, source, birthday, preferred contact method, last activity.

`services`

- Workspace service menu.
- Used by bookings and public profile.
- Includes duration, price, description, active, show-on-profile.

`appointments`

- Internal table for user-facing Bookings.
- Stores client/service links, title, start/end, status, price, notes, location, recurrence metadata.

`tasks`

- Business tasks.
- May link to contact and/or appointment.
- Includes priority, due date, reminder timing, status, completed timestamp.

`task_checklist_items`

- Checklist/subtask rows for tasks.

`invoices`

- Backend table for user-facing Payments/Money.
- Stores invoice/payment rows, status, due date, amount, paid amount, linked client and appointment.

`invoice_line_items`

- Existing line item table. Current app mostly uses simplified payment rows.

`expenses`

- Money-tracking expenses.
- Stores amount, category, date, notes.

`business_profiles`

- Public profile configuration.
- Stores handle, bio, cover/gallery/review fields, notice fields, booking mode, profile toggles.

`booking_requests`

- Public profile request-booking submissions.
- Owner triages and can manually confirm into a booking.
- New public requests require a normalized customer email. Legacy rows may be
  blank. The captured request email is immutable during owner confirmation and
  remains the authoritative confirmation-email recipient.
- `request_token` makes a retried client submission idempotent per workspace.
- `source_hash` is an Edge-only abuse-control value, not a public identity.

`notifications`

- In-app bell centre records.

`notification_preferences`

- Workspace-level notification toggles.

`push_tokens`

- Future push delivery device tokens.

`calendar_sync_accounts`

- Legacy-reserved calendar integration state. The launch app uses explicit
  event import and point-in-time ICS export; it does not create or advertise a
  live sync account.

`account_deletion_requests`

- Account deletion request tracking.
- Actual deletion is completed only by the trusted account-deletion Edge
  Function and its audited retry workflow.
- Request and completion paths independently revalidate that the requester is
  the sole workspace owner before deleting workspace data.

## Relationships

Core relationships:

- Workspace has many contacts, services, appointments, tasks, invoices, expenses, notifications, and booking requests.
- Contact has many appointments, invoices, tasks.
- Appointment belongs to workspace, optionally contact and service.
- Appointment can have linked tasks and linked invoices.
- Task belongs to workspace, optionally contact and appointment.
- Invoice belongs to workspace, optionally contact and appointment.
- Business profile belongs to workspace.
- Booking request belongs to workspace and optionally service.

## Auth Flow

Supabase Auth handles email/password sign-up, sign-in, password update, session persistence, and sign-out.

Flutter app flow:

- Supabase initialized from `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Auth session is read through Supabase auth stream.
- Workspace membership determines whether the user enters the app or onboarding.
- Workspace data access is filtered through `workspace_id`.

## RLS Principles

Principle:

Every workspace-owned table must enforce access through `workspace_members`.

Helper function:

`public.is_workspace_member(target_workspace_id uuid)`

Expected rule:

- Authenticated users can access rows only where they are members of the row's workspace.
- Public profile reads go through the `get-public-profile` Edge Function, which returns only intended public data.
- Public booking request writes go through the `create-booking-request` Edge Function, which validates handle/service ownership, bounds input, forces `pending`, and rate-limits.
- Privileged operations such as final account deletion happen through trusted Edge Function code, not Flutter.

## Transactional Workflow Rules

The launch migrations expose three bounded authenticated RPCs:

- `create_task_workflow(jsonb)` creates a task and its initial checklist
  together.
- `create_booking_workflow(jsonb)` creates one or more booking occurrences and
  the requested inline client, payment, task, booking-request update, and
  notification together.
- `complete_booking_workflow(jsonb)` completes a booking and performs its
  linked payment and notification handling together.

Rules:

- Public wrappers are security-invoker functions granted only to
  `authenticated`.
- Private security-definer implementations set an explicit search path,
  require `auth.uid()`, verify workspace membership and every linked tenant
  record, and validate bounded payloads before writing.
- Booking creation serialises schedule writes per workspace so the overlap
  check and insert cannot race.
- Overlap rejection remains the server default. An authenticated owner may
  bypass it only by sending explicit `allow_overlap=true` after the client has
  shown the schedule warning; public or implicit writes cannot bypass it.
- New booking requests store `requested_for` as `timestamptz` together with the
  matching IANA `requested_timezone`. The public Edge boundary verifies that
  timezone against the workspace setting. Legacy free-text requests remain
  readable during the staged mobile rollout.
- A stable idempotency key is reused for retries. Repeating a completed request
  returns the stored result rather than creating duplicate business records.
- `app_private.workflow_idempotency` is not available through the client Data
  API.

Public booking and Places abuse controls are service-role-only database
functions called by Edge Functions. They serialise limit consumption, validate
hash format and payload bounds, and keep rate-limit rows private.

Booking-request conversion also commits one private transactional-email outbox
row in the same transaction. Provider delivery is a separately retryable side
effect: a five-minute lease recovers stale workers, retry delay is capped, and
delivery stops after eight attempts or 24 hours. The event/request unique key
prevents workflow retries from duplicating email intent. Client roles cannot
inspect recipient or body data.

Deployment state checked 2026-07-26:

- Live migrations: `20260726000048` transactional task,
  `20260726000057` Edge rate limits, `20260726000102` deletion export,
  `20260726000110` reserved profile routes, and `20260726000118`
  transactional bookings, plus `20260726000520` explicit client-deny RLS for
  the private rate-limit ledger.
- Active functions: `create-booking-request` v8,
  `places-address-search` v8, `get-public-profile` v6,
  `request-account-deletion` v6, and `complete-account-deletion` v9.
- Structural, grant, and advisor smoke checks passed. Production-like workflow,
  abuse, and destructive deletion tests remain launch gates;
  migration/function presence alone is not end-to-end evidence.

## Live RLS State

Live RLS is enabled on all current public tables.

Recent cleanup:

- Removed all direct anonymous table privileges. Public profile and booking
  traffic can reach only the bounded Edge Function interfaces.
- Limited `authenticated` to `SELECT`, `INSERT`, `UPDATE`, and `DELETE` on
  active app tables. Account-deletion creation and completion remain
  server-only; authenticated members may only read their own workspace's
  request history under RLS so privacy exports remain complete. Deletion audit
  rows have no client grants.
- Revoked default Data API table privileges so future migrations must opt a
  table into client access explicitly.
- Removed legacy duplicate `*_policy` policies from the live project.
- Scoped member policies to `authenticated`.
- Removed direct public table policies for profiles, services, and booking requests; public access now uses Edge Functions.
- Updated `public.is_workspace_member(...)` to use `(select auth.uid())`.
- Added missing foreign-key indexes flagged by Supabase advisors.
- Added authenticated atomic/idempotent task and booking workflows.
- Added private public-booking and Places rate-limit state plus idempotent
  request tokens.
- Added an explicit deny-all client RLS policy to the private Edge rate-limit
  ledger as defence in depth.

## Security Advisor State

Read-only advisor state checked 2026-09-01:

- Seven `app_private` outbox/operations tables report the informational
  `rls_enabled_no_policy` lint. They are intentionally deny-by-default and have
  no client grants; do not add permissive policies to silence the lint.
- Seven authenticated application RPCs report the generic
  `authenticated_security_definer_function_executable` warning. Their purpose
  is to provide bounded atomic onboarding, booking, task, deletion-state and
  push-token workflows; each must keep explicit `auth.uid()` and
  workspace/ownership validation plus narrow EXECUTE grants.
- The former leaked-password-protection warning was not present in this check.

Performance advisor highlights:

- No unindexed-foreign-key, auth-initplan or duplicate-policy warnings were
  reported.
- Low beta traffic leaves several relationship, abuse-control and planned-query
  indexes marked unused. Keep required foreign-key/security-path indexes and
  review query statistics after representative load before removing any.

## Naming Conventions

Database table names remain backend-stable:

- `appointments` is user-facing Bookings.
- `invoices` is user-facing Payments/Money.
- `contacts` is user-facing Clients.

Do not rename these live tables casually. Prefer product-language aliases in UI while preserving backend compatibility.

## Migration Rules

- Never make manual schema changes without updating `supabase/schema_contract.sql`.
- Apply DDL through Supabase migrations.
- Name migrations in snake_case.
- Do not hardcode generated UUIDs in migrations.
- Add indexes for new foreign keys.
- Add RLS policies in the same migration or immediately after.
- Verify with Supabase table list and advisors.
- Update Dart models/repositories/tests in the same feature slice.
- For multi-record user actions, prefer one bounded transactional workflow over
  sequential client writes. Require a stable retry key when a repeated request
  could duplicate business records.
- Scheduled business attention must use stable notification deduplication keys,
  respect stored notification preferences and remain workspace scoped.
- Operational health state belongs in `app_private`; client roles must not
  receive table access or claim/finish execution privileges.
- Retention jobs must scrub the narrow sensitive payload rather than deleting
  business or financial records whose retention has a separate legal purpose.
- A cached Auth session is not sufficient authorization for onboarding. The
  server-side user must exist and must not have a pending deletion request.
- Push tokens are device credentials, not user-entered records. Register and
  reassign them only through membership-checked RPCs, make the provider token
  globally unique, and remove only the current user's token at sign-out.
- Remote delivery state belongs in `app_private`. Fan out from the canonical
  notification row, enforce preferences and local quiet hours before enqueue,
  use leases and bounded retry, and disable invalid provider tokens without
  exposing token or provider data to app roles.
- Public service-role endpoints must verify that the target workspace still
  has at least one member before returning profile data or accepting a booking
  request. `booking_requests` also has a before-insert trigger enforcing this
  invariant because service-role Edge code bypasses RLS.
- Optional service extras belong to one parent service. Public clients submit
  only bounded add-on UUIDs; trusted SQL validates workspace, parent, active
  state, duration and price before creating immutable request snapshots.
- `booking_request_items` and `appointment_items` are business-history
  snapshots. Catalogue edits or deletes may clear source identifiers but must
  not rewrite saved name, duration or price. Legacy intake overloads must pass
  through the same automatic base-snapshot boundary.
- Suggested public times are advisory and privacy-bounded. Compute them from
  trusted workspace hours, timezone, notice, window, buffer and selected item
  duration; never return appointment identifiers, client data, busy intervals
  or internal counts.
- Base service durations are authoritative business inputs and must remain
  between 5 minutes and 24 hours at both repository and database boundaries.
  Any corrupt legacy row must be made inactive and private before a bounded
  fallback is stored; only the owner may review and republish it.

## Client Secret Rules

- `SUPABASE_ANON_KEY` / publishable key may exist in the client bundle.
- `service_role` keys must never enter Flutter, `.env`, docs, commits, screenshots, or logs.
- APNs private keys are server/provider secrets and must never enter Flutter
  source, repository files, screenshots or logs.
- `.env` must remain ignored.
- `.env.example` should document required variables only.

## 2026-09-05 email reminder and account journey boundaries
Customer reminder timings live in workspace_settings.customer_reminder_minutes and use existing workspace RLS. Recipient mapping, unsubscribe preferences and leased queues live in app_private. Worker endpoints authenticate before using service-only RPCs; the few Auth reads use private security-definer helpers with empty search_path and no anon/authenticated execute grant. Do not grant general service-role access to auth.users to make a worker function work. New verified-account enrolment requires a recorded signup notice; old unsubscribes and consent scope must not be widened. Cancellation, reschedule, recipient changes and preferences are rechecked at delivery. See releases/2026-09-05-email-system.md.

### 2026-09-05 — customer email event boundary
Customer lifecycle intents are private, leased and deduplicated; the worker rechecks source status, authoritative recipient, expiry and suppression before sending. Payment requests require authenticated workspace membership/MFA and explicit recipient review, with a pending real Stripe checkout transaction and a valid outstanding GBP amount. No caller-supplied URL or arbitrary recipient is accepted. Owner setup/summary context is service-only and reads the current records; no private client notes are included. Public RPC wrappers use invoker security; narrow Auth reads remain inside private definers. See migration 20260905161843.

### 2026-09-05 — Customer-facing business contact contract

`workspace_settings.customer_contact_email` / `customer_contact_phone` are optional validated contact details governed by existing settings RLS/MFA. Explicit business email overrides verified non-relay owner-email fallback; no Auth phone fallback. `public.customer_email_contact(kind,id)` is service-only and invoker, resolving an existing private email intent rather than a caller-supplied workspace. Contact data is frozen at first composition for retry identity; the reminder queue stores only this contact snapshot alongside existing appointment references. See migration `20260905164210_business_email_contact_details.sql` and pgTAP suite 019.
