# Repeated services per booking

Date: 2026-09-20
Status: Deployed and included in iOS build 22

## Product decision

A booking may contain up to eight catalogue service occurrences, including the
same service more than once. Each occurrence contributes its catalogue price
and duration and is stored as its own immutable booking-item snapshot. This
keeps one booking, payment and schedule entry while accurately representing
work such as the same treatment for two people or the same service repeated.

The first occurrence remains the legacy primary `service_id`. Ordered
`service_ids` carry every occurrence through owner-created bookings, public
booking requests and availability calculations. Optional extras remain unique
within the booking and are not multiplied implicitly.

## Implementation

- The shared additional-service picker keeps selected services available and
  removes one occurrence at a time.
- Owner and public totals count repeated services while de-duplicating optional
  extra controls and values.
- Public Edge validation accepts repeated ordered service IDs but retains UUID,
  primary-service and eight-item validation.
- Migration `20260920115353_allow_repeated_services_per_booking.sql` updates the
  existing selection function without changing tables, RLS or direct grants.

## Release boundary

The migration and the affected public booking/availability Edge Functions must
be deployed before a build exposing this behavior is distributed. They were
deployed to the Workloop Supabase project before the build 22 device install.

## Local verification

- `flutter analyze`: clean.
- `flutter test --dart-define-from-file=.env`: 1,468 passed, one existing
  configuration-dependent skip.
- Affected Edge formatting, 19 tests and both entry-point type checks: passed
  with checksum-verified Deno 2.9.7.
- `flutter build ios --profile --dart-define-from-file=.env`: passed for
  Workloop `1.0.0 (22)`.
- Migration `allow_repeated_services_per_booking`: applied and verified with a
  read-only repeated-service selection against the deployed function.
- `create-booking-request` v35 and `get-public-booking-availability` v8:
  active, with deployed validation sources matching the tested local files.
