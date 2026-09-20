# Regular-client follow-ups and tomorrow preview — 6 September 2026

Status: local implementation. No customer outreach, remote notification, backend migration, deployment or store upload was performed. Final integrated tests, visual review and native release checks remain with the parent release pass.

## Product decisions

The existing Needs attention client prompt used a fixed 42-day activity gap. That could flag imported contacts without visit history, ignore a pending request from the same customer, and describe a contact edit as a booking date. The replacement is a suggestion based on actual completed visits:

- Active clients need at least three completed visits separated by at least 24 hours. Multiple services in one visit cannot manufacture a regular pattern.
- The median of up to six recent gaps supplies an approximate usual interval. A grace period of 25% (at least 7 days, at most 30) avoids prompting as soon as the usual interval passes. Strongly irregular patterns and intervals outside 2–180 days do not create a nudge.
- Inactive clients, future/current scheduled bookings, matching pending/contacted booking requests, open client tasks, recently completed client tasks and recent client edits suppress the prompt. Request matching uses normalized email or a safely normalized/exact-formatted phone, never a name guess.
- Leads retain the existing seven-day follow-up rule. Active clients without sufficient completed history no longer receive a generic six-week nudge.
- Every prompt opens the exact client. The existing balanced four-row attention preview still preserves request/task/payment category coverage. No new feed or outgoing message is introduced.
- The client row offers **Hide for 7 days**. Only a user/workspace-scoped local preference is saved; no client activity, communication or delivery record is fabricated. The confirmation explicitly says **on this device**. A failed write keeps the row and offers the normal retry path.

At a glance gains one flat **Ready for tomorrow** row. It shows the actual business-zone next day, scheduled booking count, sum of known booking durations and first start time. Unknown duration totals are omitted. Tapping opens a scrollable flat list, and each row opens its exact booking through the existing fresh-record route. Empty/loading/failure states are distinct; an invalid/missing business timezone never produces an invented empty schedule. The brief carries workspace provenance so retained data cannot be presented as another workspace's schedule.

## Files and reasons

| Files | Change |
| --- | --- |
| `lib/shared/utils/client_follow_up.dart` | Pure cadence/suppression logic and calendar/DST-aware next-day selection, with injected clock. |
| `lib/shared/providers/client_follow_up_provider.dart` | Small local snooze adapter/provider and a tomorrow summary derived from canonical booking/settings providers. |
| `lib/shared/providers/dashboard_provider.dart` | Replace the fixed active-client gap; wait for saved snoozes in the existing attention resolution path. |
| `lib/features/dashboard/dashboard_screen.dart` | Existing client attention row gets a deliberate snooze menu with save/account/disposal guards; add the flat tomorrow row. Existing greeting, clock and booking hero are unchanged. |
| `lib/features/dashboard/tomorrow_brief_row.dart` | Compact preview, honest recovery and a scrollable exact-booking list with workspace guards. |
| `test/client_follow_up_brief_test.dart` | Cadence boundaries, insufficient/irregular history, matching requests, exclusions, local persistence and DST/date-line selection. |
| `test/tomorrow_brief_row_test.dart` | Loading/failure/retry, 320px at 2× text, exact booking navigation, workspace changes and missing duration. |
| `test/dashboard_attention_navigation_test.dart` | Actual snooze save/failure/retry plus existing direct-action and category coverage. |
| `test/dashboard_attention_provider_test.dart` | Its regular-client fixture now includes real completed booking history instead of assuming an old contact date proves regularity. |

## Verification receipt

- The six-file focused batch passed **59 tests** (`/tmp/workloop-client-follow-up-focused.log`), including existing dashboard loading, direct navigation and shared-data consistency cases.
- Final `test/tomorrow_brief_row_test.dart`: **6/6 passed** (`/tmp/workloop-tomorrow-final.log`), covering explicit workspace provenance and a real canonical-provider failure/retry. The retry now refreshes the failed booking/settings sources, and all source futures receive error handlers immediately. These final checks supplement the earlier 59-test batch; final full-suite/build/device receipts are still pending.
- Scoped Dart analysis and formatting were run. The sole final formatting lint was corrected; the final analysis receipt is `/tmp/workloop-client-follow-up-analyze.log`.
- Existing Today goldens may need an intentional update for the additional At a glance row. Review pixels first, and provide a truthful timezone/settings fixture rather than approving a mock-environment failure as the normal UI.

## Practical limits

This is an on-screen prompt when Workloop refreshes its data, not an automated email, SMS, WhatsApp or push campaign. Snoozes persist across restarts on this device and are separate per signed-in user/workspace; they do not sync to another phone. Completed booking status is the evidence used for regularity, so an owner who leaves all old bookings scheduled will not receive an inferred regular-client prompt. Task/contact recency is only a conservative reason to avoid another nudge; it is never described as proof a customer was contacted.

Tomorrow's duration is the sum of scheduled work, not a promise of free calendar time or a check that overlapping bookings are feasible. The existing booking workflow still validates overlaps when creating/editing. Physical-device interaction and final visual snapshots remain pending.

Suggested commit: `feat: surface regular client follow-ups and tomorrow's schedule`.
