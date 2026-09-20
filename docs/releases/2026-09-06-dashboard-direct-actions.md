# Dashboard clarity and direct actions — 6 September 2026

## Outcome and release state

This pass addresses the owner's three dashboard requests: remove the decorative
calendar, make the illustrated booking clock show the booked start time, and
open the exact record from every Needs attention entry.

The dashboard implementation is local source with **8 clock/dashboard checks**
and **34 attention/provider/navigation checks** passing. These batches overlap
in the existing dashboard tests; they are not 42 unique new tests. The companion
client route batch also passed **63 focused checks**, and the reviewed backend
route migration is live. Final full integration tests, reviewed goldens, exact-
source native builds and physical-device checks are pending at this report's
handoff. The integrator will append their final receipts. No TestFlight or Play
upload is implied, and the owner's TestFlight hold remains in force.

## Resulting behavior

### A quieter header and an accurate booking clock

- Remove the decorative calendar illustration beside Today and from the clear-
  day hero. The visible date and existing Open Bookings action remain available.
- A booking's analog clock uses the **same start time as its digital label**.
  It does not illustrate the current device time or a fixed sample time.
- The hour hand advances between hour marks according to the minutes; the
  minute hand points to the actual booked minute. Midnight, afternoon/evening
  values and quarter/half-hour starts are covered by paint assertions.
- Swiping between bookings updates the visible clock with that booking. A
  changed booking time invalidates the painter; an unchanged time does not.
- The existing local booking-time display and digital 24-hour label remain
  authoritative. This pass does not introduce a different timezone conversion
  policy or use the clock as evidence that a booking has started or finished.

### Needs attention opens the actual record

| Entry | Direct destination | Freshness rule |
| --- | --- | --- |
| Active booking request | `/booking-requests/<request ID>` | Read actual pending/contacted request rows; refresh the request collection before opening. Confirmed/declined requests are excluded. |
| Overdue payment | `/payments/<invoice ID>` | Refresh payments before opening the identified payment actions. The amount remains the actual outstanding balance, including partial payments. |
| Overdue task | `/tasks/<task ID>` | Refresh tasks before opening the identified task details. Completed tasks remain excluded. |
| Client follow-up | `/clients/<client ID>` | Refresh clients and resolve the exact client through the authenticated, workspace-scoped destination. Do not pass an old client snapshot as the destination's source of truth. |

The previous request-count row did not contain an entity ID. Each visible
request now names the requester and retains its own typed request record and
service context. One tap opens that request's existing review flow; payment and
task entries likewise open their existing actions/details without a second list
selection. Route path segments are encoded, and a missing/mismatched source
cannot be used to guess a record or fall back silently to a generic section.

The preview remains bounded to **four rows**. Select the first urgent item from
each available category, then fill remaining slots using the existing priority
and oldest-first ordering. Render the selected rows in that priority order.
For example, six requests plus an overdue task and payment produce two request
rows, the task and the payment. A request backlog cannot hide every other kind
of work that needs attention. Records outside the preview remain available in
their existing modules; the preview is not a complete backlog count.

Bookings and notes are not additional Needs attention producers in the current
dashboard. Its next-booking action already opens that booking, while the separate
Tasks/Notes shortcuts are intentionally module shortcuts. No new inferred
booking or note alerts were invented to satisfy the direct-action change.

### Notification destination repair

The companion client work resolves booking, request, payment, task, note and
client IDs through current workspace data. Initial-ID handlers wait for refresh
to finish and recheck the current target at the post-frame handoff. Removed or
unavailable records receive an explicit recovery screen rather than an
unexplained list. Its separate **63-test focused batch passed**; see
[Exact record navigation](2026-09-06-exact-record-navigation.md) for the actual
handler, push/local bootstrap and legacy-inbox behavior. The dashboard tests
alone are not evidence of those destination-handler checks.

Backend producer and historical-route repair is tracked separately in
[Exact notification record routes](2026-09-06-exact-notification-routes.md).
The reviewed migration was applied at **6 September 00:24:36 BST**. It repaired
96 deterministically recoverable stored destinations; notification content,
read states, preferences and outbox rows remained unchanged. The backend work
preserves legitimate multi-record
morning summaries and repairs historical records only when their stored IDs
resolve deterministically; it does not guess from names or message wording.
No notification was sent or re-enqueued by repairing its stored destination.
The companion report contains the deployed migration identity, before/after
checksums and the limits of the remaining ambiguous historical alerts.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/dashboard/dashboard_screen.dart` | Remove decorative calendar chrome; pass each booking's start time to its clock; use exact attention routes and category-balanced preview; refresh only the relevant source before handoff; retry the request source when attention cannot load. |
| `lib/shared/widgets/workloop_quiet_warm.dart` | Optional booking time for clock illustration, minute-aware hour-hand geometry and repaint dependency. Other illustration styles remain reusable. |
| `lib/shared/providers/dashboard_provider.dart` | Compose individual active-request rows from the canonical provider, derive encoded destinations from matching typed entities, and select the bounded category-balanced preview without persisting a second backlog. |
| `test/booking_clock_paint_test.dart` | Verify actual painted hand endpoints at midnight, quarter/half-hour and late-day values; verify repaint behavior. |
| `test/dashboard_failure_states_test.dart` | Preserve failure/notification behavior and verify that swiping the real booking carousel changes the booking clock; assert decorative calendar removal. |
| `test/dashboard_attention_provider_test.dart` | Request identity, filtering, oldest-first ordering, resolution refresh, honest source errors, encoded IDs and rejection of aggregate/mismatched sources. |
| `test/dashboard_attention_navigation_test.dart` | Real dashboard taps into exact routes for all four attention types, matching-source refresh, distinct requests, mixed backlogs, invalid-source recovery and a 320-pixel/2×-text interaction. Destination builders in this fixture record the route; companion tests exercise the actual detail handlers. |
| `test/shared_data_consistency_test.dart`; `test/core_audit_client_money_feed_test.dart` | Adapt existing attention fixtures from request counts to request records while preserving shared-data and remaining-balance assertions. |
| `lib/main.dart`; `lib/features/clients/client_record_link_screen.dart`; `lib/shared/widgets/record_link_unavailable.dart` | Companion authenticated exact-client route, fresh scoped client lookup, preservation of an opened editing draft and explicit missing-record recovery. |
| Initial-ID handlers in `lib/features/appointments/appointments_screen.dart`, `lib/features/finance/finance_screen.dart`, `lib/features/tasks/tasks_screen.dart`, `lib/features/notes/notes_screen.dart` and `lib/features/public_profile/booking_requests_screen.dart` | Companion exact-target refresh, changed-ID, post-frame and missing-record handling, covered by the separate 63-test batch. |

The checkout contains earlier authorized work. This inventory describes the
changes relevant to these dashboard requests, not the origin of every dirty
file. Notification producer/migration files and payload verification are listed
in the companion backend report rather than duplicated here.

## Verification and remaining checks

| Check | Evidence at handoff |
| --- | --- |
| Clock/dashboard batch | **8 passed**; `/tmp/workloop-booking-clock-tests.log`. Actual paint assertions and carousel interaction are included. |
| Attention/integration batch | **34 passed**; `/tmp/workloop-dashboard-exact-attention-tests.log`. Includes the new route tests, six provider tests and existing shared-data/finance/dashboard regressions. |
| Scoped analysis | No issues across dashboard source and the changed attention/consistency tests after removing an unused import. Changed-file whitespace checks pass. |
| Backend source verification | Companion report records **92 migrations / 25 suites / 687 database assertions**, including 40 new route assertions, plus 23 push payload tests. These are local verification receipts, not provider/device delivery proof. |
| Actual destination-handler/client batch | **63 focused tests passed**, reported by the client integrator and detailed in the exact-record navigation companion report. |
| Backend live receipt | Applied at **00:24:36 BST**; 96 repaired destinations, unchanged non-route notification fields/preferences/outbox, no queued or sent verification notification. See the backend companion report. |
| Golden review, final full suite and native builds | Pending the integrator's exact-source checks; earlier app-build receipts do not cover this revision. |
| Physical notification display/tap | Not verified by these tests. No test push, delivery claim, quiet-hour override or TestFlight upload is part of this report. |

Remaining checks: visually review the changed Today goldens; run the final
combined suite and builds; on the available iPhone compare analog/digital times,
swipe bookings, and tap request/payment/task/client attention rows. Verify
foreground/background/terminated notification destinations separately when
device access allows. Android push provider activation remains a separate
configuration limit recorded in the companion report; this pass does not change
the owner's service-account key policy.

The four-row dashboard is a preview, not the complete inbox or payment queue.
A refresh may show that the chosen record was removed, changed or is outside
the current business; that state should be explicit and retryable. An already
delivered provider payload cannot be rewritten by a later database route repair.
No architecture replacement, new business-data schema, automatic messaging or
payment activation is introduced by the dashboard changes.

Suggested commit: `Make dashboard clocks accurate and attention actions direct`

## Final integration receipt — 6 September 00:39 BST

The exact-source integration checks are complete. This receipt supersedes the
pending test/build entries above; it does not supersede the physical push-tap
or Android provider limitations.

- `flutter analyze`: **no issues**.
- Full `flutter test --dart-define-from-file=.env`: **758 passed**, with six
  capability-gated payment tests skipped in that default configuration.
- Payment-enabled batch: **18 passed**, including those six gated tests and
  payment-history/deep-link regressions. Payment collection was enabled and
  Tap to Pay remained disabled.
- The initial full run found one obsolete accessibility fixture: its booking
  alert used `/work` while expecting to open a related record. The fixture now
  supplies an exact booking ID; its accessibility expectation is preserved.
  The subsequent complete suite passed. Separate legacy-link tests retain the
  unavailable-original-record behaviour.
- Visually inspected dark/light Today and the notification list before updating
  their three intentional reference images. The same two golden tests then
  passed, followed by all goldens in the full suite. The booking clocks match
  the adjacent time, and Today has no decorative calendar.
- The final companion client batch is **66 passed**, including the additional
  A → close → B draft → A notification → back checks for remote and local
  notifications, and compact large-text missing-record recovery.
- Fresh signed iOS profile build: **74.1 MB**, signature verification passed.
  Existing plugin Swift Package Manager adoption warnings remain; they did
  not prevent this build.
- Fresh Android profile build: **163.1 MB**. No Android handset validation or
  remote-push activation is implied.
- CoreDevice installed the fresh app on the owner's iPhone 15 Pro Max and
  launched it successfully at **00:38:18 BST**. Installed metadata confirms
  **1.0.0 (12)**; the local build was replaced without a store-version bump.
- `git diff --check`: passed. No TestFlight/Play upload, commit or push.

The final source also identifies presented detail/editor/sheet routes. Repeated
taps preserve the matching open record; tapping a different record opens that
record above the current editor, so returning restores its unsaved draft.

Physical visual/notification-tap checks remain outstanding: iPhone Mirroring
reported iPhone in Use, then iPhone Not Found on reconnect, even though
CoreDevice could install and launch the app. No test push, quiet-hour override
or customer notification was sent for this validation. Follow-up is to compare
the clock and digital label while swiping on the phone, then exercise genuine
foreground/background/terminated alert taps once mirroring is available.
Android remote push remains pending under the owner's unchanged key policy.
Older alerts lacking a recoverable identity cannot promise an exact destination;
the inbox explains that limit. Already delivered push payloads cannot be changed
by the database repair.

Evidence logs are `/tmp/workloop-direct-actions-analyze.log`,
`/tmp/workloop-direct-actions-full-tests-final.log`,
`/tmp/workloop-direct-actions-enabled-tests.log`,
`/tmp/workloop-direct-actions-goldens-final.log`,
`/tmp/workloop-direct-actions-ios-build.log`,
`/tmp/workloop-direct-actions-android-build.log`,
`/tmp/workloop-direct-actions-device-install.log` and
`/tmp/workloop-direct-actions-device-launch.log`.

Artifact SHA-256:

- iOS Runner executable:
  `9603687f0dfad043ebf12f2ad3c69f58278ec902bedae580bb0a85714ddf72cc`
- Android profile APK:
  `6eda4481108f47d48f7cf2f4fe478c2f3176814b979f3e0bda87abf08d99ecae`
