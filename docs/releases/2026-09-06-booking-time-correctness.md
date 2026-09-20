# Booking time correctness — 6 September 2026

Status: implemented locally, with focused checks. No backend migration, live function deployment, physical booking test or app upload was performed by this pass. The final integrated suite and signed build belong to the parent release pass.

## Findings resolved

- Accepting a request in the repeated autumn hour now preserves the customer's original instant when the owner leaves the selected date and time unchanged. Changing those fields deliberately creates the selected replacement time; unavailable zones fail clearly instead of silently falling back to London.
- Working-hours checks use the workspace timezone. Request creation/review and owner booking creation/editing preserve their existing absolute booking timestamps and overlap rules. A booking crossing a clock change is checked using its actual elapsed duration.
- Retrying a confirmation after the server committed but its response was lost can recover the existing idempotent result. A freshly confirmed request bypasses client-side preflight against its own newly created booking; the existing server workflow remains authoritative. Missing or declined requests cannot proceed through this recovery path.
- Structured public requests require a valid ISO timestamp with an explicit offset. JavaScript no longer silently rolls impossible dates into another month or interprets a timestamp without a zone using the server's clock. Legacy requests without structured times remain supported.
- The coordinated UI pass protects conversion from malformed zones and old requests outside the current date-picker bounds. It uses the request zone's civil day and a 366-day upper bound, and preserves the recorded request until the owner deliberately changes it.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/shared/utils/booking_time.dart` | Shared validated timezone conversion; civil display values are distinct from absolute booking instants. |
| `lib/features/public_profile/booking_request_time.dart` | Preserve an unchanged repeated-hour instant and validate hours across DST boundaries. |
| `lib/shared/repositories/appointments_repository.dart` | Optional workspace-zone working-hours checks, retaining existing overlap queries. |
| `lib/shared/repositories/profile_repository.dart` | Validate loaded zones; use workspace settings in request preflight; recover committed request retries through the existing idempotent backend. |
| `lib/features/appointments/add_appointment_screen.dart`, `appointment_detail_screen.dart` | Pass already-loaded workspace timezone to owner booking preflight. |
| `lib/features/public_profile/booking_requests_screen.dart` | Coordinated UI-agent change: supply the preferred instant, show an honest unavailable-time state, and keep picker bounds valid. |
| `supabase/functions/create-booking-request/request_validation.ts`, `index.ts` | Validate an explicit requested instant before RPC and return a safe invalid-time response for server validation failures. |
| `test/booking_time_repository_test.dart`, `test/booking_request_time_test.dart` | Real repository HTTP fixtures, timezone/DST boundaries, response-loss recovery and local reminder elapsed-time checks. |
| `test/screen_transition_isolation_test.dart` | Update its repository override for the new optional argument; behavior unchanged. |
| `supabase/functions/create-booking-request/request_validation_test.ts` | Offset, leap-year, impossible-date and malformed timestamp cases. |

## Verification

- Scoped Dart analysis of the affected helper, repositories, owner screens and tests: **clean** (`/tmp/workloop-booking-time-analyze.log`).
- Booking helper/repository, recurrence and local reminder tests: **35 passed** in the focused run. The existing conversion test's keyboard hit-target assumption then failed while the shared sheet was being changed; the UI owner fixed the test interaction and subsequently reran **all 7 conversion cases successfully**. Its combined sheet/picker/conversion batch passed **16 tests**. These are separate runs, not a claimed single full-suite result.
- Public request/availability Deno tests: **19 passed** (`/tmp/workloop-booking-time-deno.log`). Full `create-booking-request` import-graph typecheck passed (`/tmp/workloop-booking-time-deno-check.log`).
- Scoped formatting and `git diff --check`: clean.
- Existing database tests already specify retry → one booking and one confirmation outbox row; they were inspected but not rerun here. No schema change was needed.

## Deployment handoff

The exact local function bundle is `/tmp/workloop-booking-time-edge-20260906/create-booking-request/`: `index.ts`, `request_validation.ts`, `deno.json`, `deno.lock`, with a SHA-256 manifest alongside. Preserve the repository's existing `verify_jwt = true` configuration and existing endpoint access/rate-limit settings. The parent should compare and deploy this concrete bundle; preparing it did not activate any change.

## Limits and follow-up

- A device/browser end-to-end test should still create a public request, accept it and compare the stored requested/confirmed instants, including both occurrences of the autumn repeated hour. Simulated repository and widget tests are not evidence of physical delivery or a live request.
- Existing email reminder workers use absolute start instants minus the selected offsets and recheck status/start before dispatch. Local reminder offset tests cover spring and autumn changes; actual permission, reboot, background scheduling and phone timezone changes still need device evidence. SMS remains off.
- The confirmation backend still decides whether a retry is valid; the client never declares an email sent or creates a second appointment to recover a response. A commit racing between the new status read and overlap preflight may still need another retry.
- Existing recurrence expansion tests pass. New recurring-series creation remains outside V1 because edit scope and exception handling are not implemented; this pass does not enable it.
- Owner date/time editors retain their existing phone-local display contract. Only working-hours validation was changed to the explicit business zone; this is not a global calendar-timezone redesign.

Suggested commit: `fix: preserve booking instants and recover confirmation retries`.
