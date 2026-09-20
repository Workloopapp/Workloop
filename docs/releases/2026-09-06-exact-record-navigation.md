# Exact record navigation — 6 September 2026

Notification taps and dashboard actions now resolve the supplied record ID through the existing workspace-scoped providers and open the existing booking detail, request detail, payment actions, task detail or note editor. The new `/clients/:clientId` destination resolves the current client before opening Client Overview. The dashboard action changes are documented separately in [dashboard direct actions](2026-09-06-dashboard-direct-actions.md).

## Repaired behaviours

- Initial record handlers previously consumed retained data while a refresh was pending, or marked an ID handled before its workspace/data was ready. They now wait for a successful current source, then recheck the ID, workspace and latest source again when the opening frame runs.
- Payment links resolve against the complete payment source, including older payments outside the visible period/history. Task, booking and request links similarly open completed, past or declined records when those records still exist.
- A missing or deleted record now has a persistent explanation and **Check again** action. It does not quietly leave the owner hunting through the parent list. A failed source load retains its existing connection/error retry state rather than being classified as a deleted record.
- Reusing a destination widget with a different record ID resets the one-time opening state. Client links resolve the current canonical client instead of retaining the dashboard's earlier map.
- Local taps now refresh the same canonical sources as remote taps. Deferred startup and warm taps check account ownership again before navigation; an already queued tap is discarded if its signed-in owner changes before the next frame.
- When an entity detail has been closed but its GoRouter URL remains, tapping the same notification reopens that record. The existing navigation observer and ordinary route names distinguish a visible parent page from the actual record presented in an editor/detail/sheet. A repeat tap for that record preserves its draft. If a different record has since been opened from the retained list, the requested record opens above it; returning preserves the earlier editor and its unsaved text.
- Historical collection-only links are routed to the notification inbox. Known record updates without an exact link explain that the original record link is unavailable and have no misleading navigation chevron. Real home summaries still open Today. External/invalid routes remain rejected.

## Source scope

- `lib/main.dart`: adds the authenticated `/clients/:clientId` destination.
- Existing initial-ID handlers in `appointments_screen.dart`, `finance_screen.dart`, `tasks_screen.dart`, `notes_screen.dart` and `booking_requests_screen.dart`.
- New `lib/features/clients/client_record_link_screen.dart` and `lib/shared/widgets/record_link_unavailable.dart` reuse the existing detail and shared UI components.
- `lib/shared/notifications/{local_reminder_bootstrap,remote_push_bootstrap,remote_push_service,notification_route,notification_navigation}.dart` and the existing notification inbox tile.

No new database schema or notification transport is introduced by this client change. The separately reviewed/deployed producer and historical repair changes are described in [exact notification routes](2026-09-06-exact-notification-routes.md).

## Automated verification

The final seven-file focused Flutter batch passed **66 tests**:

- `test/exact_record_navigation_test.dart`: actual booking/request/task detail screens, note editor, payment actions and Client Overview; six missing-record cases; retained loading data; reused incoming ID; reachable missing-record retry at 320×568 with 2× text.
- `test/notification_bootstrap_reliability_test.dart`: cold startup/login, bounded registration retry, permission events, signout/account changes, plus real task reopening and preservation of the same note-editor controller/unsaved text on repeat taps for **both** local and remote notifications. The A → close → B draft → A notification → back flow also verifies the requested record opens and B's original editor/draft survives.
- `test/notification_service_reliability_test.dart`, `test/remote_push_service_test.dart`, `test/notification_route_test.dart`: plugin lifecycle, safe route parsing and legacy collection fallback.
- `test/feature_workflow_refinement_test.dart`: inbox read/error/retry and repeated-tap navigation behaviour.
- `test/money_history_hierarchy_test.dart`: payment detail access independent of the current period/history limit.

Scoped Dart analysis reports **no issues** and `git diff --check` passes. Logs: `/tmp/workloop-exact-record-tests.log` and `/tmp/workloop-exact-record-analyze.log`.

## Evidence limits

These are local source and automated navigation results. They do not establish physical APNs/FCM delivery, actual iOS/Android cold-start behaviour, or a TestFlight upload. The parent integration task owns final whole-app tests, visual review, native builds and physical notification-tap checks. The user's TestFlight hold remains in effect.

Suggested commit message after the full working tree is reviewed: `fix: open exact records from notifications and attention actions`.
