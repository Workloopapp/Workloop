# Finite recurring bookings — 8 September 2026

Status: implemented and verified locally. This report does not claim deployed database behavior, an installed mobile build or physical-device QA.

## Owner workflow

New booking now offers Once, Weekly, Every 2 weeks, Every 3 weeks and Every 4 weeks. Repeating bookings have a bounded count of 2–24, including the first booking, with a final-date preview. All occurrences are created together through the existing booking workflow. Optional payment-due records remain one per occurrence; inline preparation/follow-up tasks retain the existing first-booking scope, stated in the form.

Repeating times are interpreted in the saved business IANA timezone. Their civil hour stays constant across daylight-saving changes; nonexistent spring-forward times are rejected before submission. The first selected instant and unchanged booking edits preserve an ambiguous autumn instant. Existing one-off creation retains its existing device-local time contract. Booking detail shows series times in their saved zone.

Each occurrence is a normal appointment. Edit or cancel one from its booking detail; the other dates remain unchanged. The detail and cancellation copy make that scope explicit. There is no infinite schedule, background regeneration or edit-all-series action.

The booking detail Money disclosure also opens the connected invoice editor when its linked-payment query has successfully resolved empty. The editor returns into the invoice detail. Existing linked payments suppress the creation action to avoid a second amount owed; server-side invoice guards remain authoritative for races.

## Data and security

Migration `20260908190556_recurring_booking_series.sql` was created with the Supabase CLI. Its only new appointment column is nullable `recurrence_timezone`; legacy appointments stay readable. Existing `recurrence_rule` and `recurrence_parent_id` connect the finite series.

`public.create_recurring_booking_workflow(jsonb)` is security invoker and authenticated-only. It checks workspace membership, current business timezone, weekly cadence, occurrence count and elapsed duration, and forbids converting a single public booking request into a series. It delegates MFA, linked-tenant validation, service snapshots, schedule locking, conflict checks, payments, notifications and idempotency to the existing `create_booking_workflow`. A namespaced stable key prevents retries duplicating rows. Metadata is set only on newly materialized rows, so retry recovery cannot recreate cancelled dates or reset moved occurrences.

No production database mutation, migration deployment, notification sending or app distribution was performed.

## Files and purpose

- `lib/features/appointments/recurring_booking_fields.dart`: repeat interval/count controls, timezone and final-date preview.
- `add_appointment_screen.dart`: connect the form to business-zone series creation and truthful task scope.
- `appointment_detail_screen.dart`, `appointment_detail_sections.dart`: explicit occurrence-only edits/cancellation, preserved edit instants, saved-zone display, correct repeat labels and booking-to-invoice entry.
- `lib/shared/utils/appointment_recurrence.dart`: timezone-aware recurrence expansion, missing-hour validation and unchanged-instant preservation.
- `lib/shared/repositories/appointments_repository.dart`: matching preflight/transaction payload instants, civil payment dates and routing to the new RPC.
- `lib/shared/models/slate_models.dart`: retain the series timezone through Appointment reads and refreshes.
- `supabase/schema_contract.sql`, `supabase/rls_policies.sql`: additive column/ACL contract.
- `test/recurring_booking_series_test.dart`, `supabase/tests/database/026_recurring_booking_series.test.sql`: timezone, retry, occurrence exceptions, count/cadence bounds, atomic conflict recovery and tenant isolation coverage.

## Verification

- Scoped Flutter analysis: no issues (`/tmp/workloop-recurring-analyze.log`).
- Eight focused Flutter suites: 61 tests passed (`/tmp/workloop-recurring-flutter.log`). This includes new series tests and existing recurrence, booking workflow/time, add-on, service-bundle, booking control and client handoff tests.
- Current-source SQL replay: 97 migrations executed and the recurring suite passed all 27 assertions. Evidence: `/private/tmp/workloop-db-validation/recurring-series-20260908-results.json`; log: `/private/tmp/workloop-recurring-sql.log`.
- The temporary `documents-replay.mjs` harness uses real PostgreSQL via PGlite with explicit Auth/cron/Vault/Storage bootstrap substitutes. It does not prove hosted PostgREST/GoTrue integration or concurrent multi-session locking.
- `git diff --check`: clean.

Full app analysis, the complete Flutter suite, iOS profile build and physical device checks belong to the integrated parent phase. Before distribution, deploy the new migration and verify a series on a device through a clock-change boundary, cancel one occurrence, move another, and check that notifications/payment records reflect the intended occurrence.

Suggested commit: `feat: add finite recurring bookings with safe occurrence edits`.


## Workflow audit follow-up — 8 September 2026

The new-booking form now freezes the submitted details while saving and after an uncertain response. Retry sends the same payload and idempotency key without repeating schedule preflight against bookings the first attempt may already have created. A definite first-attempt database rollback unlocks editing and rechecks the changed submission. Retrying is blocked after an account/workspace switch until the original workspace is open again. Leaving an uncertain save explicitly advises checking Bookings before creating another booking.

CLI migration `20260908200053_recurring_booking_retry_recovery.sql` resolves committed results before mutable timezone validation. The public function remains security invoker. The new private read-only helper accesses the existing private idempotency table with narrowly scoped definer privileges, explicitly checks authenticated identity, workspace membership and enrolled MFA, and selects only that user's `create_booking` result under the `recurring:` key namespace. There is no new public endpoint or persisted data model. A known key returns its original result; a fresh key still validates the current timezone and complete series. Recovery does not rewrite or recreate moved/cancelled occurrences.

The booking invoice entry now also supports the single untouched matching unpaid legacy booking-payment case, coordinated with the invoice adoption transaction. Other collected, managed, mismatched or multiple entries cannot use that entry point. The invoice backend checks card activity and reservations before adoption. Managed invoices display deposit due/received and remaining invoice balance in the booking, and open the invoice's receipt workflow rather than the legacy full-payment shortcut.

Tomorrow now uses the same 44-point icon field, spacing and 16/13-point typography as neighboring dashboard Money/Tasks/Notes rows. The title is `Tomorrow`; exact-booking navigation and loading/error behavior are retained. Open schedule sheets additionally reject retained data from another workspace.

Verification for this follow-up:

- Scoped analysis: no issues (`/tmp/workloop-workflow-audit-analyze.log`).
- Five focused suites: 27 passed, including 320-point deposit handoff, exact lost-response retry, known rollback editing, workspace switching, DST cadence, retained-sheet isolation and two actual-dashboard goldens (`/tmp/workloop-workflow-audit-flutter.log`).
- Full local migration replay and recurring SQL suite: 39 assertions passed, including exact result recovery after timezone changes, new-series stale-zone rejection, separate-user isolation inside one workspace, cross-tenant denial, absent identity and MFA (`/private/tmp/workloop-db-validation/recurring-recovery-results.json`).
- Baseline/after screenshots were inspected: `/tmp/workloop-tomorrow-before-normal.png`, `/tmp/workloop-tomorrow-before-large.png`, `/tmp/workloop-tomorrow-after-normal.png`, `/tmp/workloop-tomorrow-after-large.png`. New golden files are `test/golden/files/dashboard-tomorrow-normal.png` and `dashboard-tomorrow-large.png`.
- `git diff --check` passed. Integrated full-suite/build/device verification remains in the parent phase; no production change was made by this follow-up.
