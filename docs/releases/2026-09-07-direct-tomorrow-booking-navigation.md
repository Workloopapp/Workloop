# Direct booking navigation — 7 September 2026

## Cause and change

The `/bookings/:id` destination constructed `AppointmentsScreen` on its default
Today tab. Its initial-ID handler waited until after rendering that page, then
pushed the booking detail as another route. This exposed the wrong schedule
briefly and left an unnecessary Back step. The tomorrow sheet also invalidated
the complete booking collection before opening an already loaded record.

- `lib/features/appointments/appointments_screen.dart`: exact-ID mode now
  resolves the existing workspace-scoped provider and renders the detail on
  the same route. It never builds the schedule toolbar or Today list. Loading,
  failure and missing records have explicit booking-only states. A workspace
  change removes the old record; an ordinary booking refresh retains the open
  detail and its editing draft. Normal list/calendar entry remains unchanged.
- `lib/features/dashboard/tomorrow_brief_row.dart`: open the exact route without
  forcing an unnecessary whole-collection reload. Format the converted business
  time as `HH:mm`, without visible BST/GMT/other abbreviations.
- `lib/features/appointments/appointment_detail_screen.dart`: the accessible
  Back label is now simply “Back”, because the source can be the dashboard or
  another record as well as the booking list.

## Verification

**29/29 focused tests passed** with `.env`: the new
`test/booking_direct_navigation_test.dart`, updated
`test/tomorrow_brief_row_test.dart`, existing exact-record navigation tests and
existing booking-status/draft safety tests. Scoped Dart analysis and diff checks
were clean. Log: `/tmp/workloop-tomorrow-direct-tests.log`.

The direct-route regression checks the first rendered route frame and the next
24 frames at 16ms intervals, asserting that Today, Upcoming, the empty Today
state and the schedule's TabBarView never appear. It also observes exactly one
new route, checks that one Back action returns to the dashboard, and confirms
that a loaded collection is read once. Other cases hold a refresh unresolved to
prove no stale detail/list flashes, change workspace with an exact record open,
and preserve an unsaved edit across a background booking refresh.

Time formatting assertions cover UK summer/winter time, midnight rollover and
a half-hour offset zone. The existing 320px/2x tomorrow-sheet test also passes.
The first attempted combined run was blocked by a concurrent, temporary
booking-request callback compile error; that screen's owner fixed it before
the successful rerun. No test assertion was weakened to hide it.

This is source and controlled-test evidence. No physical-device check, signed
build, upload, database change or external deployment was performed in this
pass. The change applies to every existing `/bookings/:id` entry, including
notification links, so the parent release pass should include its usual
notification-navigation smoke test.

Suggested commit: `fix: open exact bookings without an intermediate schedule`.
