# Screen and workflow review — 5 September 2026

This is the feature-review portion of the pre-TestFlight improvement pass. It records source inspection and focused automated checks, not a claim that every feature has been exercised on a physical device. No TestFlight upload or backend deployment was performed by this review.

## Product decisions

- Keep the core Client → Booking → Work → Payment → Repeat flow and retained Work views.
- Remove the visible Business Feed from Today. Its synthetic summary duplicates the schedule, money and attention views, requires eight data sources, and the dashboard filters out many of the items it generates. Existing bookings, payments, client histories, notes and notification records remain intact. The legacy URL should land safely on Today.
- Keep the notification inbox for important events the owner may have missed. Needs attention is the operational action list; an unread notification is a historical alert and must not imply that an action is still outstanding.
- Remove the separate Coming up dashboard block only with a top-card fallback to the next future booking when there are none left today. The schedule remains the full agenda.
- Leave the unused legacy MoreScreen source alone; it is not a visible primary destination. Deleting that source does not improve the user's current workflow.

## Findings corrected in this feature pass

| Finding | Change | Primary source |
| --- | --- | --- |
| Refresh animations ended before replacement data arrived | Await canonical provider futures and keep failed refreshes in existing visible retry states | Clients, Notes, Tasks, Bookings, Booking requests, Notifications |
| Empty or short lists could not reliably be refreshed | Always-scrollable refresh containers, including empty/filtered booking requests and notifications | `appointment_list_view.dart`, notification/request list screens |
| Business could interpret failed reads as missing services/hours and unfinished setup | Show explicit unavailable states rather than invented setup status | `business_screen.dart` |
| Saved working hours could read “not set” | Normalize full and abbreviated weekday keys; count enabled days with usable blocks | `profile_screen.dart` |
| Rapid notification taps could launch duplicate routes | Single activation guard per keyed notification row | `notifications_screen.dart` |
| Invalid notification links still showed navigation chevrons | Show navigation affordances only for allow-listed routes | `notifications_screen.dart` |
| A badge could remain uncleareable when unread items were older than the latest 50 | Bulk-read availability uses the complete unread count | `notifications_screen.dart` |
| Device permission looked disabled while loading, and stayed stale after visiting Settings | Explicit checking/error states and recheck on app resume | `notifications_screen.dart` |
| Permission alone was described as delivery readiness | Copy now says notifications are allowed; it does not claim remote delivery has been proved | `notifications_screen.dart` |
| Profile and booking-page refresh could surface uncaught async failures | Await all requested data and retain provider error handling | Profile, Booking page, Business |

## Findings handed to the integration/data owners

These findings were reported for integration; their final verification belongs in the parent pass report.

- Guard repeated booking submissions and back/discard actions during in-flight saves in the client, booking and money editors.
- A booking cancellation can already be committed before a notification-preference fetch fails; the notification must not turn that committed action into an apparent failed cancellation.
- Manual money actions should not generate noisy unread alerts about the owner's own action. An entry with a future due date must not be classified as an overdue notification.
- Dashboard duplication, opacity during transitions, clock-based data freshness and provider sharing were reviewed with the integration/data owners. This feature pass did not modify those shared systems.

## Review coverage

| Area | Inspection scope | Evidence limits |
| --- | --- | --- |
| Main routes and five-tab shell | Destination map, legacy routes, retained Work sections and dashboard/feed duplication | Transition rendering and device performance belong to integration validation |
| Today | Source of attention, upcoming booking selection, feed filtering, refresh fan-out | Root owns dashboard changes and visual verification |
| Clients | List refresh, filters, create/edit guards, linked booking/payment/task tabs and detail snapshot flow | Data owner handles canonical linked-data providers |
| Bookings | List/calendar refresh, add/edit/status paths, request navigation, customer request submit validation | No real customer booking was created in this review |
| Tasks and Notes | List filters, refresh/empty states, initial entity routing, editor mutation/notification paths | Existing editor tests remain necessary; not every rich-text interaction was manually reproduced |
| Money | Income/expense create/edit guards, manual paid action and its notification side effects | No live card payment or refund was performed |
| Business | Booking-page status/readiness, service/hour/name summaries, settings and editor navigation | New cases tested for failure and weekday-format compatibility |
| Booking page and Business profile | Initial loading gates, refresh failure handling, preview/share and editor routing | Sharing to external apps was not performed |
| Notifications and preferences | List/bulk read, valid routes, duplicate activation, empty refresh, permission lifecycle, email preference embedding | Push-provider delivery and physical notification taps not reverified by this sub-review |
| Auth and onboarding | Entry/recovery/MFA actions, onboarding step map and draft/final-save paths | Account creation, recovery and MFA were not performed against live accounts |
| Settings, privacy, support and legal | Destination map, account update paths, notification/email embedding, export/deletion links, support/legal destinations | No account deletion or data export was executed |
| Imports and calendar tools | Contacts/CSV/calendar/text review and retry paths, partial-import reconciliation, one-time import/export wording | Device permissions, real contacts/files and external calendar apps not exercised |

## Focused verification

- `test/feature_workflow_refinement_test.dart`: **13 passing** regressions. Covers refresh completion for five main feature lists, notification empty/error refresh, old unread bulk-read availability, invalid links, repeated taps, business read failures, current/legacy weekday formats and permission resume.
- Existing targeted suites passed while making the changes: UI audit states, Work/Business navigation, compact Business, Profile overview and Booking-page hub.
- Changed feature files and the new regression file pass targeted Flutter analysis.
- Final full-suite, visual, build and physical-device results must be reported by the integration pass. Existing dirty work was preserved; no commit, upload or deployment was made here.

## Follow-up: proportions and access to everyday actions

The owner requested less repeated branding, less empty space above content and
more balanced screen proportions. This feature pass adopts the root-owned
compact header and Today-only wordmark while preserving routes and data flows.

- Business replaces the tall booking-page hero with a compact customer-bookings
  panel. Requests have their own first row, including zero/loading/error states,
  and remain accessible when booking-page setup checks fail. Services, working
  hours and the business profile fit above the navigation on a standard 390pt
  phone at normal text size.
- Booking Page puts the request inbox before the readiness checklist. Preview,
  copy, share and editing remain available. Its status surface and section gaps
  are smaller.
- Work, Bookings, Tasks and Notes remove explicit wordmark overrides and reduce
  gaps between headers, peer controls and the actual list. Embedded sections
  retain one shared safe area. Client detail also removes its repeated wordmark;
  the client list brings search, filters and records closer together.
- Profile and Settings use compact flat management rows and smaller section
  gaps. Profile's identity graphic is 48pt. Settings adds the Getting started
  guide entry, validates the current account/workspace before opening it and
  guards repeated taps. Guide content and progress persistence belong to the
  tutorial feature owner.
- Money uses a smaller total/receipt treatment and target graphic. Expenses
  appear before spending-by-category analysis, keeping record management first.
- Business and Booking Page now use the existing working-hours parser: an
  enabled day with an explicitly empty block list cannot make the booking page
  appear ready. This matches the Profile summary.

Verification: the initial four-file feature batch passed **27 tests**. After
the working-hours correction, `test/feature_hierarchy_refinement_test.dart`
passed **10 tests**, including two additional empty-hours regressions. The new
tests cover action order, above-the-fold Business management, inbox access
during a page failure, a single top safe inset, absent repeated wordmarks and
expense-before-analysis hierarchy. This is source/widget evidence; it does not
replace final physical-device appearance checks, live sharing or payments.

## Follow-up: interrupted communication saves and client next action

Client Overview's Next booking now considers only scheduled future bookings.
Previously a future-dated booking already marked completed or no-show could
still appear as next. Client Overview also retains pull-to-refresh on short
content. A targeted widget regression verifies that those finished/cancelled
records cannot displace the next scheduled booking.

Communication settings now keep cache invalidation with the provider-owned
write, avoiding stale switches when the owner leaves a screen before a slow
save finishes. Checks cover a different workspace and a disposed provider scope.
SMS permission confirmation verifies that the same user is still signed in;
the business contact dialog rejects a changed/closed workspace context and
guards repeated save callbacks. Retry clears resolved settings errors. SMS
permission and business contact dialogs scroll titles and content together for
small screens, larger text and the keyboard.

The final focused batch passed 31 tests (24 SMS/communication/client edge cases,
five email-setting tests and two client cache-edit/deletion tests). Targeted
analysis and diff checking passed. Runtime provider delivery, real account
switches on a physical phone and the final global suite remain integration
checks, not claims made by this feature review.
