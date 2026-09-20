# Workloop recent-request coverage audit — 4 September 2026

## Closure update — 4 September 2026, after deployment

This document retains the discovery-stage findings below. The completed outcome is recorded in [the dated launch audit](2026-09-04-launch-audit.md). Customer-selectable multi-service bundles (up to eight existing services plus eligible extras) now exist in app/backend and deployed website; this follows the original customer-composition request rather than adding a separate pre-priced package editor. Combined snapshot totals/duration, availability and confirmation were tested. Offline logout, digest routing, Resend receipts, Apple relay sender registration, per-token push routing and Android startup were repaired. The OS runner now verifies isolated analysis/tests before approved apply, while latest upload and external distribution are shown separately. Both website runtime React patches are published. Build 10 is externally available to the existing beta group; final Android AAB is signed/emulator-verified. Real payments, Android account/closed testing/device, FCM credential approval, full hosted journeys and unconnected OS integrations remain explicit gates. Historical recommendations below are not all still open.

---

Read-only review by QA Reviewer and Technical Librarian perspectives. No app, backend, provider or deployment changes made. This report distinguishes actual user requests from earlier assistants' claims. Source was inspected on 4 September; live-state facts below come from the same-day parent audit at `/Users/ismaeelsmiley/Documents/Codex/Audits/Workloop-audit-2026-09-04.md`, not new provider queries by this reviewer. Parent is now implementing fixes, so this is the pre-remediation baseline.

## Main conclusion

Most recent mobile feedback has implementation and tests in the current checkout, but testers are still on Build 6. Several past “completed” claims mixed source, locally installed builds and deployed backend. Genuine multi-service bundles remain missing: a manually named combined service is not the same feature. Email reporting and morning brief failures are confirmed real defects. Workloop OS's newer cloud work also means its original local checkout is stale.

The user has now clarified that Android and iPhone release and real card collection are required for public launch. Those are mandatory launch gates, not optional later enhancements.

## Requests actually reviewed

`Plan Build 6 beta rollout` (`01a058b4-4742-7c33-a48e-465128263fce`): reviewed the most recent 20 turns, covering the initial screenshot feedback, repeated reports that changes did not work, Build 9 backend promotion and duration guard, live booking selector, shared UI standardisation, final persistent canvas/add-ons polish and phone launch.

`Build Workloop OS foundation` (`01a0632d-3438-7dc1-94bd-dcab4eef515b`): reviewed most recent 10 turns, covering Supabase pulse, model activation, Codex runner, guarded review/apply, and separate provider connections.

`Next Workloop Build` (`6a9a7c73-89c4-83ed-bc05-7f758857b1e7`): reviewed all 10 available turns, covering live Product/Development departments, removal of fake readiness, TestFlight read connector, Analytics, and the failed Google OAuth-console retry.

`Apple Private Relay Explained` (`6a9927d8-1418-83eb-b52e-abede85f800a`) and `Implementing Stripe Payments` (`6a970a0c-6360-83eb-9bad-c78ca52bac02`): reviewed all available turns. Stripe discussion was strategic advice; it did not itself instruct implementing every alternative processor. The current explicit card-collection instruction supersedes the historical payments-off launch boundary.

This was a focused recent-history audit, not an exhaustive reading of every old task or screenshot attachment. Screenshot requests were recovered through the user's accompanying text and implementation records.

## Release identity

| Layer | Evidence at start | Meaning |
|---|---|---|
| Current Flutter source | `pubspec.yaml:19` = `1.0.0+8`; `docs/CurrentState.md:1645` deliberately reclassifies prior Build 9 as superseded rehearsal | Contains final persistent canvas and owner-created add-on selection changes |
| Existing IPA | Parent audit: 34,766,747-byte Build 9, dated Sep 2 | Cannot represent later Build 8 source merely because 9 is larger; rebuild from final source |
| Local phone | Most recent reviewed task installed/launched Build 8 after earlier Build 9 installs | Development/profile device evidence only |
| Apple upload | Parent live audit: Build 7 Ready to Submit; Build 6 Testing | Newest upload is not active beta |
| Installed testers | Parent live audit: 13 tester rows show Build 6 | They do not have recent client feedback fixes |
| Git provenance | Parent audit: HEAD `dbac130`, 147 modified tracked + 86 new files | A current immutable release snapshot must be captured; don't overwrite dirty work |

## Request → implementation → delivery matrix

Paths are relative to `/Users/ismaeelsmiley/Workloop` unless prefixed Website or OS. “448 pass” refers to the parent's same-day full run, not a new run by this reviewer.

| User request | Current implementation evidence | Test / delivery evidence | Remaining gap or required action |
|---|---|---|---|
| Keep users signed in; stop unexpected sign-outs | `lib/shared/repositories/auth_repository.dart:149,190,208` refreshes sessions; `lib/main.dart:347-446` seeds current session and guards user/workspace transitions | Current 448-test suite passes; initial feedback task identified expired-token 403 handling | Verify overnight/expired-token resume on final signed iPhone and Android; Build 6 lacks candidate changes |
| Stop dashboard briefly showing different information | `lib/main.dart:347-446`; dashboard coherent-reveal gate; `test/dashboard_initial_reveal_test.dart`, `dashboard_failure_states_test.dart` | Tests exist and full suite passes | Physical account switch, refresh, resume and network failure on final build |
| Auth fits phone, less crowding, correct Workloop icon | `lib/features/auth/auth_screen.dart:186-213` compact/tight layout; `test/auth_screen_compact_test.dart`, auth golden images | Protected source tests and goldens; locally installed candidate | Verify small phone, keyboard, large text; not on current external beta |
| Booking preview back arrow fixed | Public-profile safe-area control and `test/ui_audit_public_profile_test.dart`; feedback source record | Current local suite | Final-device navigation check |
| Notification taps open exact booking/request/payment/task/note | `lib/shared/notifications/notification_route.dart:6-47`; `remote_push_service.dart:92`; `test/notification_route_test.dart` | Source routes/tests present | Production queue has four BadDeviceToken failures, no active destination; exact TestFlight receipt/tap proof missing |
| Generate push for new booking requests | Entity-routing migration + public booking workflow; exact request route supported | Backend promotion recorded Sep 2 | Same production registration/delivery blocker; test after final distribution build launch |
| Permit overlapping and outside-hours appointments | `add_appointment_screen.dart:273-283,322`; shared `showBookingScheduleWarning` / Book anyway in `slate_ui.dart:320`; `test/booking_confirmation_test.dart` | Source tests; Sep 2 backend promotion/rehearsal | Manual owner creation and public-request acceptance on final build, preserving warning/explicit consent |
| Request date/time must equal customer's chosen time | `public_profile_screen.dart:113`; exact instant/workspace timezone contract; `test/booking_request_time_test.dart` | Staged and production promotion recorded; current source tests | Device/web London DST boundary and timezone comparison |
| Editable service names, hours/minutes durations, 12-hour opening times | Onboarding and public-profile implementations; UI and duration tests | Current suite | Final device presentation check |
| No absurd 999999-minute services | `lib/shared/repositories/services_repository.dart`; `20260902174021_bound_public_service_durations.sql`; `test/service_duration_validation_test.dart` | Sep2 production guard quarantined two invalid services; parent live audit sees latest functions | Retain inactive owner-review status; don't silently republish invented service values |
| Remove inappropriate decorative service icons | `settings_services_section.dart`, public profile/service rows; source record `CurrentState.md:1564-1566` | Current UI suite/goldens | Final visual check; functional disclosure icons need not be removed |
| Standardise navigation, headers, top-right + and all bottom sheets | Shared launcher `lib/shared/widgets/slate_ui.dart:60-74`; canonical top action/navigation; `test/ui_system_contract_test.dart`, `shared_ui_refinement_test.dart` | Sep2 standardisation task says all 44 sheets migrated; current suite passes | Keyboard-heavy sheets and exact deep-link back routes need device check |
| Add restrained colour in light/dark, one persistent background | `lib/main.dart:161` `WorkloopAppCanvas`; `slate_ui.dart:1065-1114` persistent backdrop scope; theme tokens | Final 448-test pass and profile install; `CurrentState.md:1645-1662` | Saved Build9 IPA predates latest pass; regenerate |
| Service add-ons in app and website, including owner-created bookings | `add_appointment_screen.dart:302-303,428-459,767`; `service_add_ons_editor.dart`; `slate_models.dart:208`; `test/appointment_add_ons_test.dart`; Website `booking-request-form.tsx:333-353` | Backend live from Sep2; public selector published; final owner-created selection source added later | Verify immutable prices/durations on real workflow; tester client still old |
| Users/customers can create bundles of services and add-ons | Only one `serviceId` + `addOnIds`; `CurrentState.md:1566,1658-1660` calls manually combined ordinary services packages | Prior agent explicitly admitted true multi-service bundles absent, then later claimed package support | **Not fully implemented.** Add genuine owner-defined composition of existing services or explicitly negotiate scope; do not count renamed single services as delivery |
| Website displays available slots | Website `/Users/ismaeelsmiley/Documents/Workloop Website/app/[handle]/booking-request-form.tsx` uses availability endpoint, service/add-on selections | Task explicitly published Sep2; clean source `db6ce46`; parent live website audit | Rerun live page and booking flow after backend changes |
| Date selector less busy, hide/show, future dates actually work | Same Website file: abort controller `106`, preferred-date change `372`, Show/Hide/Change `404`; target-date migration | Historical 16 site tests, 5 availability Edge tests, Sep24 exact-date live response; parent publication check | Keep one-day/capped slots and stale-response guards in final verification |
| Morning brief automation | Operational SQL exists but entity routing CASE has no ELSE | Parent observed four failed morning runs Sep4 | **Confirmed defect**, corrective migration + regression and real subsequent scheduler proof |
| Apple private relay email bounces | No application fix can authorize Apple sender domains; prior task diagnosed only | Parent Resend dashboard confirms Unauthorized Sender, hello@workloop.uk / send.workloop.uk | **Configuration incomplete**, authorize actual envelope/from sources, then controlled relay delivery |
| Email health reflects delivery failures | Reporting RPC exists but SECURITY DEFINER `current_user` guard rejects legitimate call | Parent observed 500 retries and zero recorded webhook events | **Confirmed defect**, fix authorization, ingest/replay retained signed events, distinguish accepted/delivered/bounced |
| OS real departments, no invented readiness | v11+ history claims Product/Development real and fake 68% removed; parent v13 UI sees actual aggregate data | Parent inspected live v13 | “100% evidence coverage” still misleading; surface automation/push/email-reporting gaps |
| OS live TestFlight | Sep3 v12/v13 read adapter; parent sees live Apple response | Actual read works | Preserve marketing version, external group/testing state and installed-vs-latest distinction |
| OS Codex Inspect/Prepare → review → approve → apply → verify | Original runner `runner/workloop_codex_runner.py:327-418`; approval route `app/api/codex/route.ts:105-152` | Parent queue has two completed inspect jobs, zero apply requests | End-to-end unproven. Original runner only verifies file content after apply, not analyzer/tests promised in task. Check latest v13 source before repairing |
| OS Gmail/Analytics, Notion, Canva, Stripe, Meta | Original connection foundations + Sept3 Analytics adapter | Parent live: Analytics configured but read fails; remaining providers Planned; history says Google console timed out | Separate OAuth/provider credentials incomplete. Desktop connections are not the site's authorization |
| Public Android + iPhone, real card collection (new explicit scope) | Stripe gated off at `lib/core/workloop_capabilities.dart:4`; Android release signing guard and sample properties | Parent live merchant restricted, charges/payouts disabled, zero transactions; no current production Android release evidence | **Mandatory launch gate now**: actual payment/refund/reconciliation + platform/store entitlement/signing/distribution evidence |

## Exact bundle wording and recommended implementation

Original user request, task `Plan Build 6 beta rollout`, turn `01a05e84-c520-7e22-bee2-9e24d0fa428b`:

> shall we also add "add on" services to our services in the app and website. so users and customers can create bundles of services and add ons

The user later repeated “Added service add-ons and bundle support” in the list of changes that did not work (turn `01a05ec9-f9ba-7d70-8514-cc078fb155db`) and again requested implementation if missing (turn `01a0642b-a3f1-7ce2-9a68-a036c8516aac`). An assistant's explicit clarification during backend promotion says “True multi-service bundles are not implemented; add-ons are implemented.” Subsequent documentation changes this to ordinary services with a combined name, price and duration. That is a partial workaround, not evidence that existing services can be composed.

Minimum coherent existing-architecture implementation:

1. A bundle is a selectable catalogue service containing at least two existing services from the same workspace. Add a small owner-only composition editor to the current Services workflow, not a new module.
2. Store component membership/order explicitly; prohibit cycles/nested bundles and cross-workspace references. Compute aggregate duration server-side. Retain an explicit owner-set total package price so a discount is possible and never inferred by the client.
3. Extend existing immutable `ServiceItemSnapshot`/request/appointment item rows to carry each component identity, display name, duration and price allocation at booking time, plus chosen extras. Existing `serviceId` continues identifying the selected bundle catalogue item. Confirming later must not reinterpret edited service definitions.
4. Extend the existing public profile and availability contract to show the included services and evaluate the combined duration. One booking/appointment, one confirmation, one payment workflow; no shopping cart or multi-appointment engine.
5. Support parent-scoped optional extras, bounded number/duration/price, and same-workspace active checks. Legacy Build6 requests remain safe and accepted for non-bundle services during rollout.
6. Test owner creation/edit, public selection, total duration, changed service definitions after request, invalid components, concurrency/availability, confirm/email/payment totals, and rendering in both Flutter and website.

This is a schema change and needs explanation/rehearsal before creation/promotion. Product choice: owner-defined packages are the smallest clear feature. If the user means customers arbitrarily selecting any several base services, explicitly explain that distinction; the original wording plausibly includes this, so do not silently claim an owner-defined package fully satisfies arbitrary customer composition.

## OS source provenance

Original local checkout from the foundation task:

`/Users/ismaeelsmiley/Documents/Codex/2026-09-02/referenced-chatgpt-conversation-this-is-an/work`

Parent audit verified it clean at `e98284d` (Sep2), while live saved v13 source is `aa6b3bae16e06ad68164b204fcf71d0dede65fb0` from later cloud work. The original directory lacks the later Apple/Analytics adapters, consistent with that mismatch. No newer local checkout path is present in reviewed task history. Retrieve Sites v13/source snapshot for project `appgprj_6a98610e9ae48191914ef178f865a295` before editing OS; do not deploy the old directory over current cloud work.

## Documentation quality problems

The documents are append-heavy and retain contradictory operational claims. `docs/testing/KNOWN_GAPS.md` still prominently labels remote push deliberately absent, old build numbers unsigned, older support identity/public guards unresolved; later sections and live evidence supersede many of them. `docs/CurrentState.md` opens with Build8 then chronicles Build9 and back to Build8. Preserve history but put one authoritative current summary at the top with dated evidence links; distinguish completed source, production deployment, exact signed artifact, externally available build, and device proof.

Crash/error reporting remains absent in source (`pubspec.yaml` and `lib` have no Sentry/Crashlytics integration). “No crash feedback” from Apple does not replace monitoring. This is a reliability gap given the user's speed/smoothness/no-crash request, though it requires choosing/configuring a provider rather than pretending tests eliminate all runtime failures.

## Suggested next closure order

1. Repair confirmed SQL/email operational defects and APNs environment/registration; make live health reporting honest.
2. Implement genuine bundle scope and finish highest-value UI/lifecycle regressions; do not broaden the architecture.
3. Close card collection and Android release requirements in parallel with iPhone release preparation.
4. Verify isolated database/security/payment workflows plus real devices. Capture one final source snapshot and regenerate all required artifacts.
5. Upload/assign newest verified beta to existing groups and confirm availability/install evidence. Each tester still controls installing/updating the app.
6. Update authoritative current docs and OS against the correct latest source, then connect incomplete authorized providers.

Memory used: `/Users/ismaeelsmiley/.codex/memories/MEMORY.md:127-139` for release-evidence boundary and historical status to refresh; rollout ID `01a05495-ddea-7503-ae17-6f651d6c27d0`. Actual conclusions above come from fresh source/task review plus the same-day parent live audit.
