# Workloop Test Results

## Latest results — 4 September 2026

Flutter analysis clean; 475 Flutter tests passed with four feature-gated skips; separate payment-enabled checks passed. Deno 89 tests and release-tools 11 regressions passed. Signed iOS profile build/install/launch and distribution upload passed; Build 10 is externally testing. Signed Android AAB and exact-derived emulator APK startup passed after repairing eager Terminal initialization. Isolated full SQL replay: 413 assertions including OS. Marketing: 19 tests, typecheck, focused lint and build passed. OS: typecheck/build, App Store adapter, six runner tests and 20 SQL assertions passed.

See [current verification and its limits](../releases/2026-09-04-launch-audit.md) and [artifact chronology](../releases/2026-09-04-build-verification.md). Existing entries below describe earlier runs. No full hosted staging E2E, physical Android or live card transaction is claimed.

---

Last updated: 2026-08-13

> **Final local evidence ledger for branch
> `codex/comprehensive-launch-audit-2026-07-26`.** Commands below were observed
> after the last source, migration, and golden change. On 2026-08-05 the two
> reviewed hardening migrations and Stripe function v2 deployments were applied
> to the connected test-mode project. Passing evidence is not a substitute for
> the isolated
> staging, store, and physical-device gates recorded below.

## 1. Executive summary

The audit found a broad Flutter test inventory, targeted Deno tests, new
responsive/golden/integration harnesses, local pgTAP security contracts,
deterministic dataset tooling, guarded k6 scenarios, and expanded CI.

The 2026-08-08 historical candidate was clean for formatting/static analysis and
passed 346 Flutter plus 25 Deno tests. That evidence is preserved below, but it
is no longer the candidate verdict. On 2026-08-12 local analysis and 360/360
Flutter unit/widget tests passed, while the signed-out iOS simulator integration
failed because the Auth mode toggle was outside the tappable viewport. The
current owner worktree is also intentionally dirty and therefore cannot pass
the signed-artifact provenance preflight.

No user/business row was intentionally modified. The live pgTAP scripts ran
inside rolled-back transactions. Destructive, database-reset, client-SDK
multi-user, authenticated E2E, and load tests were not pointed at the project.

Verdict: **not yet ready for external beta invitations or public store launch**.
The red Auth integration journey must be fixed and rerun. Clean database/security execution,
authenticated staging E2E, physical Android/accessibility QA, production Auth
operations, public legal/support URLs, distribution signing, and store
operation remain open. No “bug-free” claim is made.

## 2. Work completed

The candidate includes:

- expanded unit/provider regression coverage for Auth/import, CRM, money/feed,
  finance boundaries, scheduling/tasks/notes, booking workflow/security, UI
  trust/accessibility, failure safety, and repository pagination;
- a multi-device/text-scale responsive harness;
- deterministic launch-surface golden tests;
- a signed-out Flutter integration smoke;
- guarded staging integration journeys for the connected core loop,
  two-account SDK isolation and public booking conversion;
- a local-only Supabase configuration and clean-schema baseline migration;
- pgTAP schema/grant and two-user RLS tests;
- deterministic small, medium, large, and 50,000-account fixture profiles;
- guarded k6 staging scenarios and explicit write/cost opt-ins;
- consolidated local QA scripts;
- pull-request database/integration jobs and scheduled dependency/load jobs;
- this testing strategy, matrix, results ledger, security plan, load runbook,
  and gap register.

See:

- [TEST_STRATEGY.md](TEST_STRATEGY.md)
- [TEST_MATRIX.md](TEST_MATRIX.md)
- [SECURITY_TESTING.md](SECURITY_TESTING.md)
- [LOAD_TESTING.md](LOAD_TESTING.md)
- [KNOWN_GAPS.md](KNOWN_GAPS.md)

## 3. Verified baseline before final audit changes

These commands passed earlier on 2026-07-26, before all current audit changes
were complete.

| Suite | Observed baseline | Scope warning |
| --- | --- | --- |
| Dart format | Clean across 161 files | Current tree changed afterward. |
| Flutter analysis | No issues | Current tree changed afterward. |
| Flutter tests | 156 passed, 0 failed, approximately 26.49 seconds | Current tree now contains additional tests and implementation changes. |
| Flutter line coverage | 4,727 of 17,074 lines, 27.69% | Aggregate coverage is not a critical-workflow guarantee. |
| Deno tests | 16 passed, 0 failed | Superseded by the 19-test final run below. |
| OSV-Scanner 2.4.0 | No known issue in the earlier supported lockfile scan | Superseded by the final Dart lockfile scan below. |
| Android profile | APK built and passed 16 KB `zipalign` verification | Not a signed release bundle. |
| iOS profile | Built and launched on an attached iPhone with Dart VM service evidence | Not App Store signing/export. |
| Web release | Built successfully | Does not prove public domain deployment. |

## 4. Final candidate command ledger

Use non-secret placeholder Dart defines for source-only tests/builds. Use an
isolated target only where backend behaviour is required.

| Area | Command | Tests/checks | Passed | Failed | Skipped | Duration | Final status |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Toolchain | `flutter doctor -v` | Flutter 3.44.8 / Dart 3.12.2 | 5 categories | 1 category | 0 | 7.4 s | **Supported mobile toolchains pass; Chrome absent** |
| Dependencies | `flutter pub get` | 132 resolved Dart packages | 1 | 0 | 0 | 1.2 s | **Pass** |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test tool` | 186 files | 186 | 0 | 0 | 0.84 s | **Pass** |
| Analysis | `flutter analyze` | 0 diagnostics | 1 | 0 | 0 | 3.0 s | **Pass** |
| Flutter full suite | `flutter test --coverage --dart-define-from-file=.env` | 249 | 249 | 0 | 0 | approximately 33 s wall time | **Pass** |
| Flutter coverage | LCOV summary from `coverage/lcov.info` | 17,493 lines | 7,014 lines hit | 10,479 lines not hit | N/A | N/A | **40.10% line coverage** |
| Golden suite | Update, visual review, then non-update `launch_surfaces_golden_test.dart` | 11 tests / 13 image files | 11 | 0 | 0 | approximately 3 s | **Pass; safe-area-aware and human-reviewed after final UI change** |
| Responsive matrix | Included in full suite | 2 declarations / 108 render cases plus keyboard case | 110 render checks | 0 | 0 | Included in full run | **Pass** |
| Accessibility contracts | Included in full suite | 4 declarations | 4 | 0 | 0 | Included in full run | **Pass; physical AT still manual** |
| Booking regressions | Workflow, confirmation, controls, recurrence, and backend security files | 34 | 34 | 0 | 0 | Included in full run | **Pass** |
| Core audit regressions | `test/core_audit_*_test.dart` | 33 | 33 | 0 | 0 | Included in full run | **Pass** |
| Integration smoke | `QUALITY_DEVICE_ID=390... scripts/qa_integration.sh` on iPhone 17 Pro simulator / iOS 26.5 | 1 | 1 | 0 | 0 | 36.8 s build + 4 s test | **Pass** |
| Deno format | `deno fmt --check supabase/functions quality/load` | 20 files | 20 | 0 | 0 | <1 s | **Pass** |
| Deno lint | `deno lint supabase/functions` | 14 files | 14 | 0 | 0 | <1 s | **Pass** |
| Deno type checks | Function-specific `deno check` commands in `scripts/qa_all.sh` | 6 entry points | 6 | 0 | 0 | <1 s cached | **Pass** |
| Deno tests | `deno test supabase/functions` | 19 | 19 | 0 | 0 | 39 ms | **Pass** |
| Data profiles | Dry-run small, medium, large, and scale-50000 profiles | 4 profiles | 4 | 0 | 0 | 1.7 s | **Pass; no backend writes** |
| Small data generation | Generate then rerun the `small` profile | 8 represented accounts | 8 generated | 0 | 1 existing batch skipped on retry | Within 3.7 s combined generator run | **Pass; resume verified** |
| Scale batch generation | One `scale-50000` batch with isolated opt-in | 50,000 represented / 250 generated | 250 | 0 | 199 batches not requested | Within 3.7 s combined generator run | **Pass as generator evidence only** |
| Generator safety | Scale without isolated opt-in; output outside `build/quality_data` | 2 negative checks | 2 refused safely | 0 | 0 | 0.87 s | **Pass; exits 78 and 64** |
| Local migrations | `scripts/qa_local_supabase.sh` | 0 migrations executed | 0 | 0 | Entire run | 0.17 s | **Blocked: Docker unavailable** |
| pgTAP schema/security | `supabase test db` | 43 authored assertions | 0 executed locally | 0 | 43 locally | N/A | **Implemented, unexecuted locally** |
| Dependency scan | OSV-Scanner 2.4.0 against `pubspec.lock` | 132 Dart packages | 132 | 0 known issues | Deno/CocoaPods lock formats unsupported by scanner | 0.46 s | **Pass for supported Dart graph; scope-limited** |
| Dependency inventory | `flutter pub outdated --no-transitive` | 6 direct packages behind latest | N/A | N/A | N/A | 1.2 s | **Reviewed; no blind launch upgrade** |

The pgTAP total is 31 schema/grant assertions plus 12 isolation assertions.
It is an authored count, not an executed pass count.

## 5. Build and platform ledger

| Target | Command/device | Result | Evidence limit |
| --- | --- | --- | --- |
| Android debug APK | `flutter build apk --debug` with placeholder defines | **Pass; 157 MB** | Build only. |
| Android profile APK | `flutter build apk --profile --dart-define-from-file=.env` | **Pass; 113.5 MB; 16 KB `zipalign` pass; APK signature verifies** | Debug certificate is expected for profile and is not a store signature. |
| Android release AAB | `flutter build appbundle --release` | **Blocked safely: exit 1, “Release signing is not configured”** | No debug-key fallback. |
| Android emulator integration | API 35/Pixel-class emulator | **Not executed locally; CI harness only** | No local Android virtual device or hosted CI result. |
| Android physical device | Supported small/current phone | **Not executed in this audit** | Permissions, TalkBack, lifecycle, reminder, deep-link, reinstall, and upgrade remain manual. |
| iOS debug simulator | `flutter build ios --debug --simulator` | **Pass; installed and launched** | Custom recovery scheme registration verified; token exchange was not. |
| iOS profile unsigned | `flutter build ios --profile --no-codesign` | **Pass; 35.3 MB** | Not an App Store artifact. |
| iOS profile development-signed | `flutter build ios --profile --dart-define-from-file=.env` | **Pass; 34.8 MB** | Development signing only; not an App Store artifact. |
| iOS release unsigned | `flutter build ios --release --no-codesign` | **Pass; 26.2 MB** | Compile evidence only. |
| iOS IPA | `flutter build ipa --release` | **Not attempted: only Apple Development identity exists; Distribution profile/certificate absent** | Store artifact remains blocked. |
| iOS simulator integration | iPhone 17 Pro / iOS 26.5 | **Pass, 1/1** | Signed-out Auth/navigation smoke only. |
| iOS physical device | Ismaeel’s iPhone / iOS 26.5.2 | **Current profile installed and launched; CoreDevice confirmed the Workloop process running** | Physical launch is confirmed; full manual VoiceOver/permission/lifecycle coverage remains open. |
| Web release | `flutter build web --release` with placeholder defines | **Pass; 44 MB** | Does not deploy legal/support pages. |

## 6. Feature coverage summary

| Module | Unit/provider | Widget/UI | Integration | Database/security | Current confidence |
| --- | --- | --- | --- | --- | --- |
| Auth/onboarding | Partial | Partial | Signed-out harness only | Partial contracts | Medium-low until isolated E2E and production email/recovery |
| Dashboard/feed | Strong targeted logic | Partial responsive/state | None authenticated | Indirect | Medium |
| Clients/CRM | Strong targeted logic | Partial form/list/detail | None authenticated | Isolation harness pending | Medium |
| Bookings | Strong targeted logic/contracts | Partial form/list/detail | None authenticated | Workflow/RLS harness pending | Medium; public request flow remains high risk |
| Money | Strong calculation/boundary logic | Partial | None authenticated | Relationship/RLS harness pending | Medium |
| Tasks/notes | Strong targeted logic | Partial | None authenticated | Workflow/RLS harness pending | Medium |
| Notifications/reminders | Partial | Partial | None on device | Partial RLS contract | Medium-low |
| Profile/settings/services/hours | Partial | Partial | None authenticated | Partial RLS contract | Medium |
| Export/deletion | Partial | Partial | None destructive | Partial source/contracts | Low until disposable E2E |
| Platform/accessibility | Automated contracts and viewport matrix | Goldens pass and are reviewed | Signed-out iOS simulator smoke | Not applicable | Medium-low until physical-device matrix |

Detailed, test-file-linked coverage is in
[TEST_MATRIX.md](TEST_MATRIX.md).

## 7. Defects found and regression status

The following issues were reproduced during the audit, fixed in the candidate,
and covered by the final 249-test pass unless otherwise stated.

| Severity | Feature | Reproduction/root cause | Candidate fix | Regression evidence |
| --- | --- | --- | --- | --- |
| High | Repository data loading | Supabase-sized result sets could stop at a default page boundary, hiding later business records. | Shared stable pagination used across repositories/providers. | Final pagination and full suites pass. |
| High | Import retries | Partial retry could resubmit records already created, producing duplicate customer data. | Retain/retry only failed records. | Final Auth/import and full suites pass. |
| High | Booking requests | Stale lifecycle updates and retry/error paths could fail silently or lose price precision. | Workspace-scoped update checks, visible failure mapping, stable retry key, atomic conversion contract, and decimal price preservation. | 34 booking regressions, 8 request-validation Deno tests, and full suites pass; dynamic staging still required. |
| High | Money/dashboard | Date and daylight-saving boundaries could include/exclude the wrong records or misstate connected totals. | Explicit inclusive/exclusive period bounds and corrected aggregation. | Final finance/client/feed and full suites pass. |
| Medium | Booking status | Cancelled/no-show/completed entries could appear as the next actionable booking. | Restrict next-booking selection to actionable scheduled state. | Final scheduling and full suites pass. |
| Medium | Currency precision | Appointment and connected Money/CRM surfaces rounded `149.99` to `150`. | Central `formatPounds`/`currencyInputValue` across every currency surface. | Unit contracts pass; reviewed booking golden shows `£149.99`. |
| Medium | Small-phone appointments | Empty schedule content overflowed a 320×568 viewport. | Scrollable refreshable sliver empty state. | Final 96-case responsive matrix passes. |
| Medium | Large text shared header | Section label/action row overflowed at 2× text scale. | Flexible bounded label/action layout with line limits. | Final 96-case responsive matrix passes. |
| Medium | Contact/request reuse | Formatting differences in phone numbers could create duplicate-like contacts during booking conversion. | Normalised phone matching at the workflow boundary. | Backend/security contract and migration coverage added; dynamic DB run pending. |

Unresolved environment, operations, and evidence risks are tracked separately
in [KNOWN_GAPS.md](KNOWN_GAPS.md); none is silently converted into a pass.

## 8. Supabase security results

| Area | Result |
| --- | --- |
| Test-mode project changes | Two reviewed retry/RLS migrations and Stripe function v2 deployments applied on 2026-08-05 |
| Live metadata | Re-inspected on 2026-08-05 |
| Public table RLS | Enabled on inspected live application tables |
| Anonymous direct table grants | None observed on inspected application tables |
| Private workflow table client grants | None observed |
| Private-table RLS | Enabled with explicit false client policies on payment counters, workflow idempotency, and Stripe webhook state |
| User A/User B pgTAP | Live transaction-wrapped 14-assertion script reached its final successful check; clean replay and SDK E2E remain open |
| Storage isolation | Not tested; no launch bucket/policy workflow identified |
| Edge source tests | 25/25 Deno tests pass; both Stripe entry points type-check in addition to the existing function checks |
| Public booking abuse/concurrency | Not executed against isolated deployment |
| Account deletion completion | Not executed |
| Leaked-password protection | Disabled paid control; app-side new-password minimum is 12 characters, not an equivalent replacement |

See [SECURITY_TESTING.md](SECURITY_TESTING.md).

## 9. UI and accessibility results

| Area | Current result |
| --- | --- |
| Automated semantic/contrast contracts | Four launch accessibility declarations plus theme/primitive contracts pass in the 249-test suite |
| Phone/text-scale responsive matrix | 108 surface renders plus keyboard case pass after overflow fixes |
| Golden images | Eleven tests / 13 image files generated intentionally, human-reviewed, and passed in non-update mode |
| Keyboard/form safety | Targeted widget coverage exists; physical platform matrix pending |
| VoiceOver | Not executed on final candidate |
| TalkBack | Not executed |
| Reduced motion | Source/test contracts exist; manual device confirmation pending |
| Touch targets/focus order | Partial automation; manual review pending |

Automated semantics cannot confirm spoken wording, focus order across every
route, modal return focus, or OS assistive-technology behaviour.

## 10. Performance results

No release-grade device performance profile was executed.

Static and regression work addressed pagination and an avoidable client-CRM
aggregation cost, but no final before/after startup, query, frame, rebuild, or
memory measurements are recorded. The 1, 100, 1,000, and 10,000-record device
matrix remains open.

Do not convert algorithmic reasoning or a passing unit test into an unmeasured
latency claim.

## 11. Load-test results

No backend load test was executed. Exact status:

- backend users seeded: **0**;
- maximum concurrent users tested: **0**;
- requests per second: **not measured**;
- p50/p95/p99: **not measured**;
- error and timeout rates: **not measured**;
- failed writes/data corruption: **not measured**;
- 50,000-user target: **represented by a deterministic generator profile
  only**, not seeded or concurrently simulated.

See [LOAD_TESTING.md](LOAD_TESTING.md).

## 12. Tests not executed

- Clean local Supabase reset and pgTAP: Docker unavailable.
- Authenticated new-user, core-business, failure-recovery, destructive, and
  multiple-account journeys: no disposable staging environment.
- Public booking-request abuse/idempotency/conversion: no isolated deployed
  target.
- Account deletion completion: destructive and no disposable production-like
  account.
- k6 smoke through stress: no staging approval/tooling; production safety and
  cost boundary.
- Real Realtime subscription/reconnect load: not implemented in k6.
- Full app performance/profile/memory matrix: not yet measured.
- Physical Android, TalkBack, permissions, reminders, deep links, reinstall,
  and upgrade: device/manual gap.
- Final VoiceOver and cross-device accessibility matrix.
- Signed Android AAB and iOS IPA: signing credentials absent.
- Store submission, declarations, review account, and public legal/support
  operation: external prerequisites.

## 13. Release blockers and exact next actions

1. Run clean local/CI Supabase replay and all 43 pgTAP assertions.
2. Provision isolated staging and execute authenticated two-account plus
   connected-business E2E.
3. Exercise public booking requests and disposable account deletion.
4. Complete measured performance and staged load work.
5. Complete the iOS/Android physical accessibility, permission, lifecycle,
   offline, reminder, and deep-link matrix.
6. Enable and verify Auth leaked-password protection and email/recovery.
7. Publish and verify privacy, terms, deletion, and monitored support endpoints.
8. Configure release signing, store declarations, review access, and brand
   clearance.
9. Run the corrected hosted CI workflows and retain the run URLs.
10. Preserve the exact verified source in a clean reviewed commit/tag.

The full severity register is [KNOWN_GAPS.md](KNOWN_GAPS.md).

## 14. 2026-07-28 final UI/UX refinement evidence

This pass evolved the existing shell and workflows without changing the
four-destination navigation, product scope, data contracts, or persistence
architecture.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Focused refinement matrix | 76/76 tests passed | Targeted workflow, state, accessibility, responsive, and golden coverage |
| Dart formatting | All `lib` and `test` files clean after formatting one changed test | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot prove runtime service behaviour |
| `flutter test --dart-define-from-file=.env` | 279/279 tests passed | Local automated suite; authenticated staging E2E remains open |
| Golden suite | 11/11 tests passed in non-update mode; reviewed launch surfaces remain stable | Pixel coverage is limited to the declared fixtures |
| `flutter build ios --profile --dart-define-from-file=.env` | Pass; 34.8 MB `Runner.app` | Development signing, not App Store distribution |
| `flutter build apk --profile --dart-define-from-file=.env` | Pass; 113.6 MB APK | Profile artifact, not Play release signing |
| Physical iPhone profile launch | Installed and launched on iOS 26.5.2; Dart VM Service discovered; detached Runner process confirmed | Launch/debugger evidence, not a full manual workflow or VoiceOver pass |

The physical iPhone result confirms installation, launch, and debugger
attachment. Dynamic text, small-phone, keyboard reachability, reduced motion,
semantic actions, and failure recovery were exercised by automated widget
matrices. Physical Android, TalkBack, VoiceOver, permissions, notification
delivery, offline/reconnect, background/foreground lifecycle, reinstall, and
upgrade checks remain manual release gates.

## 15. 2026-07-28 dark-only usability and edge-case evidence

This pass removed the retired appearance preference, lifted the graphite
palette, aligned native startup surfaces, and expanded the responsive matrix.
It found and fixed a real 337-pixel overflow in the booking-request empty state
on a 320x568 viewport at 200% text.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Focused usability matrix | 86/86 tests passed | Dark-only, Settings ownership, responsive, accessibility, action geometry, and golden contracts |
| Launch responsive matrix | 11 surfaces x 6 phone viewports x 2 text scales = 132 render cases, plus keyboard reachability | Automated widget layouts; not a physical assistive-technology pass |
| Dart formatting | 189 `lib` and `test` files checked; no changes required | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot prove deployed services |
| `flutter test --dart-define-from-file=.env` | 280/280 tests passed | Authenticated staging and production backend journeys remain open |
| Golden suite | 11/11 tests passed; 13 launch images visually reviewed | Declared fixtures only |
| iOS profile build | Pass; 34.8 MB `Runner.app` | Development signing, not App Store distribution |
| Android profile APK | Pass; 113.5 MB | Profile artifact, not Play release signing |
| Signed-out iOS simulator journey | 1/1 passed: launch, auth-mode toggle, forgot-password navigation | Does not exercise authenticated business data |
| Physical iPhone profile | Installed and launched on iOS 26.5.2; Dart VM Service discovered; Runner process confirmed | Launch and attachment proof, not a full VoiceOver/workflow matrix |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds, but future Flutter toolchain
compatibility should be monitored.

## 16. 2026-07-28 navigation-assist evidence

This pass added a shared top-edge scroll shortcut, independent retained-tab
scroll targets, and safe back-swipe behaviour without changing routes or draft
contracts.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Navigation-assist tests | 5/5 passed | Covers native iOS status-bar forwarding, top-edge return, retained tabs, clean route eligibility, and protected draft invocation |
| Focused navigation/regression set | 11/11 passed | Includes shell geometry, responsive matrix, destructive guards, and client handoff |
| Dart formatting | 190 `lib` and `test` files checked; no changes required | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot assess physical gesture feel |
| `flutter test --dart-define-from-file=.env` | 285/285 tests passed | Automated evidence; authenticated staging remains open |
| iOS profile build | Pass; 34.8 MB `Runner.app` | Development signing |
| Android profile build | Pass; 113.6 MB APK | Profile artifact, not Play signing |
| Physical iPhone profile | Exact final artifact installed and launched on iOS 26.5.2; CoreDevice confirmed PID 34234 | Process/launch proof; human gesture feel checks on representative screens remain |

The protected iOS fallback only activates for a left-edge swipe when the
current route has rejected an immediate pop. It invokes `Navigator.maybePop`,
so existing saving/submission locks and Save/Discard/Keep editing prompts remain
authoritative.

## 17. 2026-07-29 physical navigation regression correction

The earlier automated contract did not match physical-device behaviour on
every screen. This correction replaces selected-controller assumptions with
global vertical-scroll discovery and extends the safe edge fallback to any
routed screen with a real previous/back action.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Navigation-assist tests | 8/8 passed | Includes implicit non-primary scroll discovery, complete clean-route swipe, direct routed-header action, retained tabs, and protected drafts |
| Dart formatting | 190 `lib` and `test` files checked; no changes required | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot assess physical gesture feel |
| `flutter test --dart-define-from-file=.env` | 288/288 tests passed | Automated evidence; authenticated staging remains open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing |
| Android profile build | Pass; 113.7 MB APK | Profile artifact, not Play signing |
| Physical iPhone profile | Rebuilt, installed, and launched on iOS 26.5.2; CoreDevice confirmed PID 37404 | Process/launch proof; the user should re-check gesture feel on representative authenticated screens |

The iOS status-bar detector now remains an eligible, scroll-enabled
`UIScrollView` behind Flutter's rendered view. The Dart side selects only the
current route or active retained-tab scope. Native Cupertino navigation gets a
short first-refusal window; if it has not changed the route, the fallback calls
the registered back action or `Navigator.maybePop`, preserving draft guards.

## 18. 2026-07-29 forgiving navigation interaction correction

Physical use showed two remaining gaps: the top shortcut still required a
precise tap and a fallback edge swipe could be lost when Flutter cancelled the
pointer sequence. The interaction layer now treats the calm top/header area as
the shortcut, resets every visible vertical layer, and commits a deliberate
edge gesture as soon as it crosses the threshold.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Navigation-assist tests | 11/11 passed | Adds broad top-zone, simultaneous vertical layers, interactive-header isolation, wider edge start, and cancelled-pointer coverage |
| Dart formatting | 190 `lib` and `test` files checked; no changes required | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot assess physical gesture feel |
| `flutter test --dart-define-from-file=.env` | 291/291 tests passed | Automated evidence; authenticated staging remains open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing |
| Android profile build | Pass; 113.7 MB APK | Profile artifact, not Play signing |
| Physical iPhone profile | Exact profile artifact installed and launched on iOS 26.5.2; CoreDevice confirmed PID 37437 | Process/launch proof; final human feel confirmation remains with the user |

## 19. 2026-07-29 retained-workspace and Clients navigation correction

Physical use isolated two concrete exceptions. Money, Tasks, and Notes are
retained shell destinations, so they had no Navigator route to pop. Clients
also placed tappable rows under the broad top zone and installed a full-screen
horizontal filter gesture, both of which could win before the app-level top
shortcut.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Navigation-assist tests | 13/13 passed | Adds retained-workspace return and a populated 40-row Clients top-zone journey |
| Clients regression | From a 760-point offset, the top-zone row tap returns to the Clients header instead of opening the row | Widget evidence; physical feel still requires user confirmation |
| Dart formatting | 190 `lib` and `test` files checked; no changes required | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot assess physical gesture feel |
| `flutter test --dart-define-from-file=.env` | 293/293 tests passed | Automated evidence; authenticated staging remains open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing |
| Android profile build | Pass; 113.6 MB APK | Profile artifact, not Play signing |
| Physical iPhone profile | Exact profile artifact installed and launched on iOS 26.5.2; CoreDevice confirmed PID 37567 | Process/launch proof; final human feel confirmation remains with the user |

## 20. 2026-07-31 adaptive appearance and Tools launchpad

This pass restored a persisted System/Light/Dark appearance choice, introduced
a low-glare light palette through the shared theme system, and turned Tools
into a useful launchpad with direct capture actions and live workspace context.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Theme and appearance tests | System default, persistence, rollback, adaptive aliases, contrast, native startup resources, and Settings selection passed | Automated colour and state contracts; not a manual colour-vision review |
| Launch responsive matrix | 12 surfaces x 6 phone viewports x 2 text scales x 2 appearances = 288 render combinations passed | Widget layouts; not a physical VoiceOver or TalkBack pass |
| Golden suite | 14/14 tests passed; updated Tools and Settings dark images plus new light images visually reviewed | Declared fixtures only |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance or physical interaction feel |
| `flutter test --dart-define-from-file=.env` | 305/305 tests passed | Authenticated staging and production backend journeys remain open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing, not App Store distribution |
| Android profile APK | Pass; 113.7 MB | Profile artifact, not Play release signing |
| Physical iPhone profile | Exact profile artifact installed on the paired iPhone 15 Pro Max | Automatic launch was denied because the phone was locked; no process-level launch confirmation in this pass |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds. The adaptive compatibility palette keeps
legacy feature widgets coherent while they are migrated gradually to direct
semantic theme tokens.

## 21. 2026-08-03 cohesive navigation-motion pass

This pass centralised forward motion for retained shell destinations and
refined the shared Android page transition while preserving native iOS
interactive navigation and all existing route and draft contracts.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Navigation-assist tests | 19/19 passed | Covers programmatic shell switching, forward retained-tool entry, reduced motion, native iOS back swipe, cancellation, retained workspaces, and draft guards |
| `flutter analyze` | No issues | Static analysis cannot assess subjective motion feel |
| `flutter test --dart-define-from-file=.env` | 308/308 tests passed | Automated evidence; authenticated staging journeys remain open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing, not App Store distribution |
| Android profile APK | Pass; 113.7 MB | Profile artifact, not Play release signing |
| Physical iPhone profile | Exact profile artifact installed and launched on the paired iPhone 15 Pro Max | CoreDevice launch confirmation; final transition feel remains a human review |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds.

## 22. 2026-08-03 retained-screen replay regression correction

A physical screen recording exposed repeated Add to Money sheets while moving
among New task, Home, Tools, and Tasks. The transition stack was remounting
retained feature screens and replaying an already-delivered create request.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Recording inspection | 60 frames sampled across the 29.65-second physical recording; repeated Money sheet replay confirmed across unrelated destinations | Visual diagnosis, not instrumentation |
| Navigation-assist tests | 20/20 passed | Includes retained create-request replay across repeated animated destination changes |
| `flutter analyze` | No issues | Static analysis cannot assess subjective motion feel |
| `flutter test --dart-define-from-file=.env` | 309/309 tests passed | Automated evidence; authenticated staging journeys remain open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing, not App Store distribution |
| Physical iPhone profile | Exact corrected artifact installed on the paired iPhone 15 Pro Max | Automatic launch was denied because the phone was locked; final replay check remains with the user |

The corrected stack keeps an identical outer tree and stable keyed layer for
every retained destination. Tools also clears Money, Task, and Note create
inputs after their first frame so remounting elsewhere cannot replay them.

## 23. 2026-08-03 light-mode contrast refinement

Physical dashboard review showed that the first low-glare Light palette was
readable but too tonally compressed. This pass increased layer separation and
added a canonical one-pixel border around neon-filled interactive controls.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Theme contracts | Light surface separation, divider contrast, accent-border contrast, and Material button border roles passed | Numeric and widget contracts; not a colour-vision simulation |
| Golden suite | 14/14 tests passed; 15 images generated, including a new dashboard Light fixture plus refreshed Tools and Settings Light fixtures | Declared deterministic data only |
| Visual review | Dashboard, Tools, and Settings Light fixtures reviewed at 390 x 844; canvas, surfaces, dividers, accent controls, and hierarchy remain distinct | Desktop image inspection, not ambient-light device measurement |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| `flutter test --dart-define-from-file=.env` | 310/310 tests passed | Authenticated staging journeys remain open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing, not App Store distribution |
| Physical iPhone profile | Exact refreshed artifact installed on the paired iPhone 15 Pro Max | Automatic launch was denied because the phone was locked; final ambient-light review remains with the user |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds.

## 24. 2026-08-03 warm-neutral Light mode redesign

The green-grey Light treatment and strong green outlines were replaced with a
warm stone canvas, ivory surfaces, neutral interaction layers, and selective
quiet sage edges around accent-filled controls. Dark mode and product workflows
were not changed.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Theme contracts | Warm layer separation, semantic text/status contrast, focus visibility, and one-pixel accent-edge roles passed | Numeric and widget contracts; not a colour-vision simulation |
| Golden suite | 14/14 tests passed; Light Dashboard, Tools, and Settings fixtures regenerated | Declared deterministic data only |
| Visual review | Home, Tools, and Settings reviewed at 390 x 844; page, cards, rows, text, and lime actions are clearly separated without green surface tint | Desktop image inspection, not ambient-light device measurement |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| `flutter test --dart-define-from-file=.env` | 310/310 tests passed | Authenticated staging journeys remain open |
| iOS profile build | Pass; 34.9 MB `Runner.app` | Development signing, not App Store distribution |
| Physical iPhone profile | Exact refreshed artifact installed on the paired iPhone 15 Pro Max | Automatic launch was denied because the phone was locked; final ambient-light review remains with the user |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds.

## 25. 2026-08-05 free launch-hardening sweep

This pass implemented only no-charge work. It did not enable live Stripe,
platform fees, Apple proximity-reader entitlements, store signing, a paid
Supabase plan, or public legal/support operations.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis is not runtime proof |
| Flutter suite with coverage | 324/324 passed; 47.15% lines | Authenticated E2E remains open |
| Golden suite | 14/14 passed after reviewing five intentional updates | Deterministic fixtures only |
| Edge formatting/lint/type checks | Passed, including both Stripe functions | Does not exercise every provider response |
| Deno tests | 25/25 passed | Pure/helper coverage, not live money movement |
| Live schema script | Final assertion 47 passed inside a rolled-back transaction | Current project state, not clean replay |
| Live isolation script | Final assertion 14 passed inside a rolled-back transaction | pgTAP role simulation, not client-SDK E2E |
| Supabase advisor | Only leaked-password protection warning remains | Paid control remains disabled |
| Edge deployment | `stripe-payments` v2 JWT-protected; `stripe-webhook` v2 signed-body boundary | Test mode only |
| HTTP boundary smoke | Missing JWT returned 401; unsigned webhook returned 400 | Negative-path smoke only |
| iOS profile | 70.7 MB build passed; installed and launched on paired iPhone 15 Pro Max | Development signing, not distribution or full manual QA |
| Android profile | 155.0 MB universal build passed; 69.9 MB arm64 split; 16 KB zip alignment and v2 signature verified | Profile size, not Play-delivery size; no physical Android run |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds.

## 26. 2026-08-05 editorial UI sweep

The screenshots supplied for this pass were translated into one shared system:
crisp Light neutrals, denser editorial type and spacing, list rhythm, restrained
geometry, and real-data visuals rather than a screen-by-screen reskin.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| Flutter suite | 325/325 passed | Authenticated staging journeys remain open |
| Golden suite | 15/15 passed; 18 images, including a new Light notification-list fixture | Deterministic fixtures only |
| Responsive matrix | Passed in Light and Dark across six phone sizes and two text scales | Simulated viewports, not every physical device |
| Visual review | Home, Clients, Bookings, Money, Tools, Settings, Auth, forms, public profile, and notifications reviewed at 390 x 844 | Desktop image inspection, not ambient-light phone review |
| iOS profile build | Pass; 70.7 MB `Runner.app` | Development signing, not App Store distribution |
| Physical iPhone profile | Exact artifact installed on the paired iPhone 15 Pro Max | Launch denied by device security because the development profile is not currently trusted |
| Diff hygiene | `git diff --check` passed | Worktree also contains the preceding authorised launch-hardening sweep |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds.

## 27. 2026-08-05 final visual-system acceptance pass

This pass audited the full route and feature inventory after the editorial
system landed, then closed the remaining page-grid, reduced-motion, onboarding
orientation, and secondary-route test gaps.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| Flutter suite | 331/331 passed | Authenticated staging journeys remain open |
| Golden suite | 16/16 passed in protected mode; 19 images | Deterministic fixtures only |
| Primary responsive matrix | Light and Dark passed across six phone sizes, two text scales, and 12 launch surfaces | Simulated viewports |
| Secondary responsive matrix | Nine routes passed in Light and Dark at 320 x 700, 200% text, and reduced motion | One compact viewport rather than every device |
| Keyboard and draft safety | Existing keyboard-visible form, native/fallback back, retained-state, and draft-guard tests passed | Automated interaction only |
| UI source contracts | No raw feature colour literals, weights above 600, or unguarded canonical motion durations | Does not replace visual review |
| Reviewed visuals | Onboarding operating loop, notifications, and public booking profile inspected after their intentional updates | Desktop image review |
| iOS profile | 70.7 MB build passed; exact artifact installed and launched on paired iPhone 15 Pro Max; process confirmed running | Development signing, not App Store distribution |
| Android profile | 129.4 MB APK build passed | No physical Android run |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds. Manual VoiceOver, TalkBack, physical
Android, and authenticated staging journeys remain separate release-QA gates.

## 28. 2026-08-05 graphite-frame UI revamp

This pass deliberately moved beyond the preceding refinement and introduced a
new visual identity across the shared shell and product surfaces: cool chalk,
graphite framing, lime signal geometry, editorial rules, square actions, and
strong operational focus panels. Routes, providers, repositories, persisted
state, and data contracts remain unchanged.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| Flutter suite | 332/332 passed | Authenticated staging journeys remain open |
| Golden suite | 16/16 passed in protected mode; 19 reviewed images | Deterministic fixtures only |
| Responsive coverage | Primary six-device Light/Dark matrix and compact 200%-text secondary-route matrix passed | Simulated viewports |
| UI contracts | Graphite/on-graphite contrast, shared-token, motion, navigation, and interaction safeguards passed | Automated checks do not replace assistive-technology traversal |
| iOS profile | 70.7 MB build passed; exact artifact installed on paired iPhone | Launch was denied because the device was locked |
| Android profile | 155.4 MB universal APK passed | No physical Android run |
| Diff hygiene | `git diff --check` passed | Worktree also contains the preceding authorised launch-hardening work |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds. Manual VoiceOver, TalkBack, unlocked
iPhone review, physical Android, authenticated staging journeys, and store
distribution remain separate release-QA gates.

## 29. 2026-08-06 soft-editorial UI replacement

This pass replaced the rejected graphite-frame interface with open typographic
headers, soft Light-mode neutrals, white focus surfaces, quiet selection rails,
restrained lime markers, and a lighter floating shell dock. Dark remains lifted
graphite but no longer repeats harsh near-black frames inside every workspace.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot assess subjective appearance |
| Flutter suite | 333/333 passed | Authenticated staging journeys remain open |
| Golden suite | 17/17 passed in protected mode; 21 reviewed images including Light/Dark shell navigation | Deterministic fixtures only |
| Responsive coverage | Primary six-device Light/Dark matrix and compact 200%-text secondary-route matrix passed | Simulated viewports |
| UI contracts | Semantic contrast, shared-token, reduced-motion, navigation and interaction safeguards passed | Automated checks do not replace assistive-technology traversal |
| iOS profile | 70.7 MB build passed | No physical iPhone was connected for install or interactive launch |
| Android profile | 155.4 MB universal APK passed | No physical Android run |
| Diff hygiene | `git diff --check` passed | Worktree also contains the preceding authorised launch-hardening work |

The iOS build still warns that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds. Manual VoiceOver, TalkBack, physical
device review, authenticated staging journeys, and store distribution remain
separate release-QA gates.

## 30. 2026-08-06 Workloop Studio complete visual reset

This pass replaced the complete application presentation layer with Workloop
Studio while retaining every route, provider, repository, draft guard,
retained workspace, Supabase contract and operational workflow.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot judge subjective appearance |
| Flutter suite | 334/334 passed serially | Authenticated staging journeys remain open |
| Golden suite | 17/17 passed in protected mode; 21 images manually reviewed | Deterministic fixtures only |
| Responsive coverage | Primary six-device Light/Dark matrix at 100% and 200% text plus compact secondary-route coverage passed | Simulated viewports |
| Studio contracts | Exact adaptive palette, Manrope controls, semantic contrast, named geometry and reduced-motion checks passed | Automated checks do not replace assistive-technology traversal |
| Native startup | Android and iOS no longer reference the retired lime launch bitmap; Studio startup colours are asserted | App icon replacement is a separate release decision |
| iOS profile | 70.7 MB `Runner.app` built, installed and interactively launched on the paired iPhone 15 Pro Max; running process confirmed | Development signing, not App Store distribution |
| Android profile | 155.5 MB universal profile APK built | No physical Android run |
| Diff hygiene | `git diff --check` passed | Worktree also contains the preceding authorised hardening work |

The installed iOS app is signed by the configured Apple Development identity,
passes strict local code-signature verification, embeds the correct
`com.ismaeel.workloop` application identifier and includes the connected
iPhone UDID. The profile is valid through 2026-08-12. Interactive launch and a
live `Runner` process were confirmed through CoreDevice. Manual VoiceOver,
TalkBack, authenticated staging journeys, live payment verification and store
distribution remain separate release-QA gates.

## 31. 2026-08-06 Studio composition and native-brand refinement

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues | Static analysis cannot judge subjective appearance |
| Flutter suite | 336/336 passed | Authenticated staging journeys remain open |
| Golden suite | 17/17 passed after update, manual review and protected replay | Deterministic fixtures only |
| Responsive coverage | Six phone sizes across iOS/Android, Light/Dark and 100%/200% text passed; keyboard form case passed | Simulated viewports |
| Hero contrast | Primary, secondary and muted semantic roles pass 4.5:1 at both gradient endpoints in Light and Dark | Does not replace physical ambient-light review |
| Shell clearance | 140 points asserted for a 34-point iPhone safe area; all seven shell-retained workspaces use the same calculation | Other platform insets are calculated at runtime |
| Native branding | Full iOS/Android launcher-icon sets and iOS/Android native splash assets compile | Store-side asset review is separate |
| iOS profile | 70.7 MB build installed and launched on the paired iPhone 15 Pro Max; final PID 69228 confirmed | Development signing, not App Store distribution |
| Android profile | 155.6 MB universal APK built | No physical Android run |
| Diff hygiene | `git diff --check` passed | Worktree also contains earlier authorised work |

The exact installed iOS artifact uses `com.ismaeel.workloop`. Installation and
interactive launch were confirmed separately. Manual VoiceOver, TalkBack,
authenticated production-data journeys, live payments and store distribution
remain separate release gates.

## 32. 2026-08-08 native-feeling booking calendar

This pass replaced the boxed Calendar mode and repeated next-booking/list
layers with an open month grid and selected-day time-rail agenda. Existing
booking data, List mode, Requests, creation, detail routes and repositories were
preserved.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Calendar interaction coverage | Month swipe, previous/next navigation, selected-day agenda, start/end times and selected-date creation entry passed | Widget interaction, not a physical gesture feel study |
| Accessibility contract | Previous/next controls remain labelled and at least 44 points; date cells expose selection and booking counts | Automated semantics, not VoiceOver traversal |
| Studio source contract | No feature-local raw colour system, unapproved geometry or unguarded motion | Static source safeguard |
| Golden suite | 19/19 passed; 23 images including deterministic Light and Dark Calendar fixtures | Deterministic fixture data only |
| Visual review | Light and Dark Calendar reviewed at 390 x 844 | Desktop image inspection, not ambient-light phone review |
| `flutter analyze` | No issues | Static analysis cannot judge subjective interaction feel |
| `flutter test --dart-define-from-file=.env` | 340/340 passed | Authenticated staging journeys remain open |
| iOS profile | 70.7 MB `Runner.app` built and installed on the paired iPhone 15 Pro Max | Automatic launch was denied because the phone was locked |
| Diff hygiene | `git diff --check` passed | The branch already contains extensive authorised uncommitted work outside this calendar pass |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` do not declare Swift Package Manager support.
The current CocoaPods build succeeds. Manual month-swipe feel, VoiceOver,
physical Android and authenticated schedule-data review remain separate QA
gates.

## 33. 2026-08-08 final completion and release-candidate sweep

This sweep re-audited the documented routes, user-facing modules, failure-state
contracts, settings actions, current Supabase boundaries and the complete local
verification surface. The only locally actionable P1 found was the partially
exposed recurring-series control; V1 now creates one booking at a time while
preserving historic recurrence data and backend compatibility.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Dart formatting | 205/205 files clean | Formatting only |
| `flutter analyze` | No issues | Static analysis cannot prove service behaviour |
| Flutter full suite with coverage | 340/340 passed; 9,650/19,424 lines, 49.68% | Authenticated staging E2E remains open |
| Recurrence decision coverage | New-booking UI does not expose the series control; recurrence utility and payload compatibility tests pass | Historic records are not a new-series workflow |
| Golden suite | 19/19 passed in protected mode; 23 image files | Existing reviewed fixtures; no golden was changed for this nonvisual removal |
| iOS simulator integration | Signed-out launch/Auth journey 1/1 passed | No authenticated business workflow |
| Edge verification | Format/lint clean, eight entry points type-check, 25/25 Deno tests pass under transient Deno 2.9.5 | Not deployed-provider E2E |
| Data profiles | Small, medium, large and scale-50000 dry runs pass | Generator evidence only; no backend writes or load |
| iOS profile | 70.7 MB build; strict signature verification passed | Development signing, not Distribution |
| Android profiles | Universal 155.6 MB and arm64 129.4 MB builds pass; arm64 passes 16 KB alignment and v2 signature checks | Profile signing, no physical Android |
| Web release | 43 MB build passes | Not a deployed legal/support operation |
| Physical iPhone | Exact candidate installed and launched on paired iPhone 15 Pro Max; CoreDevice confirmed the process | Interactive business journey and assistive-technology traversal are not claimed |
| Live Supabase read-only refresh | Active healthy Postgres 17.6.1; 23/23 public and 4/4 private application tables have RLS; zero anon grants; zero private client grants; only deletion audit lacks authenticated access | Read-only metadata and advisor evidence, not clean replay or SDK E2E |
| Security advisor | Only leaked-password protection warning | Paid Auth control remains disabled |
| Local database replay/pgTAP | Not executed | Docker engine unavailable |
| Diff hygiene | `git diff --check` passes | Worktree includes extensive earlier authorised, uncommitted work |

No schema migration, Edge deployment, commit, push or production mutation was
performed during this sweep. Public-launch blockers remain the isolated
database/Auth/workflow evidence, destructive deletion proof, physical Android
and assistive-technology matrix, production email/legal/support operation,
live-money/provider gates, distribution signing, store operation and brand
clearance.

## 34. 2026-08-08 UI completion evidence and staging harness

This pass simplified the Tools workspace into one shared list composition,
expanded reviewed populated-state coverage, and implemented the three highest
value production-safe staging journeys without writing to the live project.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 346/346 Flutter tests, Edge format/lint/type-check, 25/25 Deno tests and all data profiles pass | Local deterministic evidence only |
| Protected golden suite | 25/25 passed; 29 image files | Reviewed fixtures, not physical ambient-light/accessibility QA |
| Visual coverage added | Populated booking requests/detail, Profile, Money, Tasks and Notes; Tools Light/Dark refreshed | Selected representative states rather than every data permutation |
| iOS simulator integration | Signed-out launch/Auth 1/1 passed; three staging tests compiled and safely skipped | No backend write occurred without explicit staging configuration |
| Staging safety | Runner requires explicit write opt-in and rejects project ref `imtbyrvsonzvtddswbtb` | A passing staging run still requires approved branch cost and disposable users |
| iOS profile | 70.2 MB `Runner.app` built, installed and launched on the paired iPhone; CoreDevice confirmed PID 78555 | Wireless Dart VM discovery timed out, so install/launch is proven but interactive QA is not claimed |
| Android profile | 156.6 MB universal APK built | Physical Android and release signing remain open |

The first parallel platform-build attempt collided in Flutter-generated iOS
files; the same builds passed when rerun sequentially. Flutter also warns that
`device_calendar` and `flutter_local_notifications` do not yet support Swift
Package Manager, and that warning should be resolved before Flutter makes it an
error.

## 35. 2026-08-08 command-centre UI polish

This pass refined Home, Bookings, Clients, Tools and the shared control/list
system without changing repositories, routes, schema or workflow behaviour.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Protected golden suite | 25/25 scenarios passed; refreshed Home, Clients, Bookings and Tools images were visually reviewed in Light and Dark where declared | Representative fixtures, not every live-data combination |
| Responsive coverage | Primary launch surfaces pass across the six-phone and text-scale matrix; a narrow-phone booking-header regression test was added | Widget geometry, not physical thumb-reach observation |
| iOS profile | 70.3 MB no-codesign profile build passed | Build evidence only; device deployment used a separately signed build from the same source |
| Android profile | 156.7 MB universal profile APK passed | No physical Android run |
| Physical iPhone | Signed profile candidate installed and launched; CoreDevice confirmed `Runner` PID 78739 | Install/launch only; wireless Flutter diagnostics did not complete an interactive QA session |
| Diff hygiene | `git diff --check` passes | The worktree contains extensive earlier authorised, uncommitted work |

The iOS build continues to warn that `device_calendar` and
`flutter_local_notifications` lack Swift Package Manager support. It is not a
current build failure, but should be addressed before a future Flutter release
makes the warning fatal.

## 36. 2026-08-10 muted Dark mode and active-job motion

This pass neutralised the Dark palette and made Home's schedule node follow the
booking selected in the Today carousel without changing booking data or routes.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Theme contracts | Semantic text, controls, module colours, focus indicators and both hero gradient endpoints pass declared contrast checks | Automated colour math, not every physical display condition |
| Responsive/accessibility checks | Phone/text-scale matrix and Reduced Motion source contract pass; selected job advances with carousel state | Automated widgets cannot judge perceived bounce quality |
| Protected goldens | 25/25 scenarios pass after refresh; Dark Home, shell, Bookings, Tools and Settings were visually reviewed | Representative fixtures only |
| iOS profile | 70.3 MB build passes | Development profile, not Distribution |
| Android profile | 156.7 MB universal APK passes | No physical Android run |
| Physical iPhone | Final signed build installed and launched; CoreDevice confirmed `Runner` PID 84894 | Install/launch only; interactive motion quality still requires the owner's on-device judgement |
| Diff hygiene | `git diff --check` passes | Worktree contains earlier authorised, uncommitted work |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 37. 2026-08-10 Notes list refinement

Notes now uses flat divider-led rows while preserving pinned/date grouping,
search, filters, editor entry, imports and destructive-action protections.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Protected goldens | 25/25 scenarios pass; populated Light Notes fixture refreshed and reviewed | Representative data only |
| Notes row contract | Populated fixture asserts both note rows use the canonical flat list mode | Widget structure, not subjective physical density |
| Responsive and safety checks | Phone/text-scale matrix, note checklist accessibility and failed-delete retention pass | Declared scenarios only |
| Platform profiles | iOS 70.3 MB and universal Android 156.7 MB builds pass | Android not run on physical hardware |
| Physical iPhone | Final signed revision installed and launched; CoreDevice confirmed `Runner` PID 84931 | Install/launch only |

## 38. 2026-08-10 compact calendar agenda

Calendar mode now places the selected-day agenda directly after the compact
month grid and renders bookings as flat time-rail list rows.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Calendar geometry contract | Test asserts the agenda divider starts within 1.5 logical pixels of the month grid | Deterministic 390 x 844 fixture |
| Booking-row contract | Selected-day booking asserts canonical `WorkloopListRow.flat == true` | Structural presentation check |
| Protected goldens | 25/25 pass; Light and Dark Calendar fixtures refreshed and visually reviewed | Representative selected day only |
| Platform profiles | iOS 70.3 MB and universal Android 156.7 MB builds pass | Android not run on physical hardware |
| Physical iPhone | Final signed revision installed and launched; CoreDevice confirmed `Runner` PID 84974 | Install/launch only |

## 39. 2026-08-10 unified booking-record rows

Schedule and Calendar now share one booking-record component. Calendar keeps
its continuous selected-day time rail; Schedule keeps Today/Upcoming/Past and
multi-day grouping.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Shared-row contract | List and Calendar fixtures assert flat `WorkloopListRow` geometry with the same padding; Schedule also asserts visible start and end times | Representative populated booking only |
| Protected goldens | 25/25 scenarios pass; refreshed populated Schedule and existing Light Calendar fixtures were visually compared | Representative data and viewport only |
| Responsive coverage | Full phone and text-scale matrix passes inside the 347-test suite | Automated layout evidence, not physical accessibility review |
| Platform profiles | iOS 70.3 MB and universal Android 156.7 MB profile builds pass | Android not run on physical hardware |
| Physical iPhone | Signed profile revision installed and launched; CoreDevice confirmed `Runner` PID 85094 | Install/launch only; owner should judge final density on live data |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 40. 2026-08-10 Bookings workflow-density pass

The Bookings List now places time filters and display mode in one responsive
toolbar, renders the seven-day load as a compact inline strip, and brings the
first job materially higher. Calendar retains the full month and time rail but
uses tighter surrounding rhythm so the selected-day agenda is visible sooner.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Schedule hierarchy contract | Standard 390 x 844 fixture asserts the first populated booking begins before logical y=450; reviewed golden moves it approximately 120 points higher | One representative data set |
| Calendar hierarchy contract | Standard fixture asserts the first selected-day booking begins before logical y=770 while the month grid keeps 44-point date cells | One six-week month and selected day |
| Responsive/accessibility matrix | Six phone sizes, Light/Dark and 1x/2x text pass; narrow/large-text toolbar stacks and the load strip expands for large text | Automated geometry, not VoiceOver manual QA |
| Protected goldens | 25/25 scenarios pass; refreshed Schedule plus Light/Dark Calendar fixtures were visually reviewed | Representative viewports only |
| Platform profiles | iOS 70.3 MB and universal Android 156.7 MB profile builds pass | Android not run on physical hardware |
| Physical iPhone | Signed profile revision installed and launched; CoreDevice confirmed `Runner` PID 85161 | Install/launch only; owner should judge live-data density and thumb flow |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 41. 2026-08-10 schedule-first Bookings hierarchy

The main Bookings screen now opens directly into the schedule. The redundant
seven-day workload graphic and full-width Schedule/Requests switch are removed;
a counted inbox action opens the existing Active/New/Closed request workspace.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Request workflow contract | Compact header inbox exposes the active count, opens `BookingRequestsScreen`, and continues into the selected request detail | Widget navigation test, not a live public submission |
| Schedule hierarchy contract | Standard fixture asserts the first populated List booking begins before logical y=320 after the chart and peer switch are removed | One representative populated day |
| Calendar hierarchy contract | Standard fixture asserts the first selected-day booking begins before logical y=710 while preserving the month grid and direct agenda handoff | One six-week month and selected day |
| Responsive/accessibility coverage | Six phone sizes, Light/Dark and 1x/2x text pass; the request action remains semantic and the compact-phone header does not overflow | Automated geometry, not manual VoiceOver QA |
| Protected goldens | 25/25 scenarios pass; refreshed Schedule plus Light/Dark Calendar fixtures were visually reviewed | Representative viewports only |
| Platform profiles | iOS 70.7 MB and universal Android 156.6 MB profile builds pass | Android not run on physical hardware |
| Physical iPhone | Final signed profile candidate installed and launched; CoreDevice confirmed `Runner` PID 85201 | Install/launch only; wireless Dart VM discovery timed out |
| Diff hygiene | `git diff --check` passes | Worktree contains earlier authorised, uncommitted work |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 42. 2026-08-10 compact feature creation and unified booking navigation

Clients, Bookings, Money, Tasks and Notes now use one circular feature-header
plus action. Bookings replaces the separate time and display controls with one
Today/Upcoming/Past/Calendar rail.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `DENO_BIN=... ./scripts/qa_all.sh` | 208 Dart files formatted, clean analysis, 347/347 Flutter tests and 25/25 Deno tests pass | Local deterministic evidence only |
| Create-action contract | Shared `WorkloopTopAction` renders only the plus while retaining the feature-specific semantic label and a target larger than 44 points | Widget semantics and geometry, not manual VoiceOver QA |
| Booking-navigation contract | Exactly one navigation rail exposes Today, Upcoming, Past and Calendar; Calendar still opens the month workspace and time choices retain their tab state | Widget navigation test |
| Responsive/accessibility coverage | Six phone sizes, Light/Dark and 1x/2x text pass, plus compact large-text secondary surfaces | Automated layout evidence |
| Protected goldens | 25/25 scenarios pass; Bookings, Calendar, Clients, Money, Tasks and Notes were refreshed and visually reviewed | Representative fixtures only |
| Platform profiles | iOS 70.7 MB and universal Android 156.6 MB profile builds pass | Android not run on physical hardware |
| Physical iPhone | Signed profile candidate installed and launched with an available Dart VM service; CoreDevice confirmed `Runner` PID 85495 | Launch evidence, not a completed manual workflow |
| Diff hygiene | `git diff --check` passes | Worktree contains earlier authorised, uncommitted work |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 43. 2026-08-11 atomic appearance transition

Appearance changes now synchronise semantic theme state and the legacy adaptive
palette before the app screen tree builds. Settings icon and identity surfaces
also consume semantic tokens directly.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| First-frame appearance contract | Manual Light, Dark and System brightness resolution passes; Settings icon and avatar surfaces hold the incoming colour after one pump | Deterministic widget rendering, not camera-based frame analysis |
| Responsive appearance matrix | Settings and the primary surface matrix pass in Light and Dark | Declared phone sizes and text scales |
| Full Flutter verification | `flutter analyze` reports no issues and 355/355 Flutter tests pass | Local automated evidence only |
| iOS profile build | Signed profile build passes at 71.0 MB | Development signing, not App Store distribution |
| Physical iPhone | Exact signed profile installed and launched; CoreDevice confirmed `Runner` PID 90217 | Install/launch proof; owner should perform the final rapid-toggle visual check |
| Diff hygiene | `git diff --check` passes | Worktree contains earlier authorised, uncommitted work |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 44. 2026-08-11 beta interface uniformity sweep

Work now keeps one stable command header while Schedule, Tasks and Notes swap
inside retained child surfaces. Shared feature headers, create actions, root
navigation, peer navigation and semantic module colours were aligned across the
primary operating loop.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Retained Work contract | Header geometry remains unchanged while Schedule, Tasks and Notes switch; one canonical create action remains present | Automated interaction, not a human rapid-tap session |
| Header and action geometry | Primary feature headers align and create-capable screens use the same 46-point circular action | Canonical shell surfaces |
| Protected visual references | 27/27 launch scenarios pass after reviewing Work, Money, Business and dark shell navigation | Representative fixtures and viewports |
| Full Flutter verification | `flutter analyze` reports no issues and 358/358 Flutter tests pass | Local automated evidence only |
| iOS profile build | Unsigned 70.8 MB profile compilation passes | Release signing is blocked by the profile capability mismatch |
| Physical iPhone | Temporary QA-signed copy installed and launched; CoreDevice confirmed `Runner` PID 90668 | The QA copy omits Apple sign-in entitlement and is not the TestFlight artifact |
| Beta signing gate | Current provisioning profile lacks `com.apple.developer.applesignin`; Xcode reports no signed-in developer account to regenerate it | Requires one Apple-account provisioning action in Xcode or the Developer portal |
| Diff hygiene | `git diff --check` passes | Worktree contains earlier authorised, uncommitted work |

The existing Swift Package Manager warnings for `device_calendar` and
`flutter_local_notifications` remain unchanged.

## 45. 2026-08-12 release-candidate QA refresh

| Evidence | Observed result | Limit |
| --- | --- | --- |
| `flutter analyze` | No issues after the QA/documentation remediation | Local static evidence; full candidate suite still required |
| `flutter test --dart-define-from-file=.env` | 360/360 unit/widget tests passed before remediation | Does not include live providers or manual interaction |
| Signed-out iOS integration | **Failed** on iPhone 17 Pro simulator: Auth mode toggle centre was below the 402 x 874 tappable viewport and Create-account state did not appear | Beta-blocking current failure; staging tests compiled/skipped |
| Database plan inventory | 82 authored: 51 schema/security, 16 isolation, 15 privileged-MFA/payment-retention | Zero clean local execution in this audit; Docker/Supabase CLI unavailable |
| Two-user SDK coverage | Expanded to read/insert/update/delete attempts across 13 practical disposable core/relationship/device tables with owner-side cleanup | Authored and formatted, not run against disposable staging |
| Candidate preflight | `scripts/qa_release_candidate.sh` passed Bash syntax and refused the current dirty/untracked tree with exit 78 before writing provenance | Expected safe refusal, not candidate success |
| Existing iOS build 3 | Local IPA signature/distribution metadata previously verified; not accepted by App Store Connect | Predates current source/backend work and is not releasable |

This refresh supersedes older current-verdict/count statements while retaining
their historical command evidence. External beta is blocked until the Auth
integration failure, clean database/82 pgTAP run, disposable staging journeys,
external Auth lifecycle and clean current signed-artifact provenance are green.

## 46. 2026-08-12 integrated beta-remediation verification

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Dart formatting | 220 files checked, zero changed | Local working tree |
| Flutter analysis | No issues | Static analysis |
| Flutter full suite | 371/371 passed | Local unit/widget/golden evidence |
| Flutter line coverage | 10,788/20,417, 52.84% | Aggregate coverage is not workflow proof |
| Protected visuals | 27/27 passed after reviewing Auth and Business baseline changes | Representative fixtures |
| Deno | 30 files formatted, 22 linted, eight Edge entry points checked, 30/30 tests passed | Local source/helper evidence |
| Data profiles | Small, medium, large, and scale-50000 dry runs pass | No backend writes |
| Signed-out iOS integration | 1/1 passes on iPhone 17 Pro simulator, 402 x 874 | Auth/navigation journey only |
| Staging integration | Three harnesses compile and safely skip without write opt-in/credentials | No dynamic staging result |
| iOS profile | Signed 71.3 MB app; strict code-sign verification passes | Development-signed, not TestFlight |
| Physical iPhone | Fresh profile installs and launches on iPhone 15 Pro Max; Runner PID 95655 confirmed | Install/launch only, not manual or VoiceOver QA |
| Android profile | 158.7 MB APK; 16 KB alignment and v2 signature pass | Debug profile signer, not store AAB |
| Web release | Build passes | Not deployed by this remediation |
| Candidate preflight | Exits 78 on the dirty owner tree and writes no provenance | Expected fail-closed result |
| Database | 82 pgTAP assertions authored | Clean replay unexecuted; required before promotion |

The previous Auth failure is closed by the visible `auth-first-run-cta` and the
passing simulator journey. Production was not migrated or redeployed.

## 47. 2026-08-13 exact-tag beta-candidate verification

This evidence was produced against clean app-source tag `v1.0.0-beta.4` at
`81673f6e5f67b11a5c4f2697e51477d95811ab4f`. This documentation update is a
later evidence-only commit and does not move the tag or change the binary.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Dart/Flutter | 222 files formatted; analysis clean; 375/375 tests pass | Local source evidence |
| Coverage | 10,810/20,449 lines, 52.86% | Aggregate coverage is not E2E proof |
| Protected visuals | Golden tests pass without baseline update | Representative fixtures; physical review remains separate |
| iOS simulator integration | Signed-out Auth/navigation journey passes; three staging journeys compile and skip safely | No authenticated hosted staging result |
| Deno | 32 files formatted, 24 linted, eight entry points checked, 32/32 tests pass | Candidate source, not deployed behaviour |
| Local Supabase | 52 migrations replay from empty; database lint clean; 83/83 pgTAP pass | Isolated local Postgres, not a live-derived branch |
| Local Auth/Data API | Confirmation, sign-in, recovery/password update, refresh-token revocation, TOTP/AAL2 and denial boundaries pass | Mailpit/local GoTrue, not external provider delivery |
| Android profile | 132,102,618-byte QA APK builds; 16 KB alignment and v2 signature pass | Debug/profile signer; no release AAB or physical Android |
| Web/iOS compilation | Web release and unsigned iOS profile/release pass | Compile evidence only |
| App Store IPA | 33,854,083 bytes; SHA-256 `2dc632e23f5ea00a54df57405d9b675fb8ca33b749310ba4df5c461a0ca3c6fa`; strict Apple Distribution signature; Store profile; build 4 | Not uploaded or TestFlight-installed |
| Physical iPhone | Build 4 profile is installed and launches; CoreDevice confirmed Runner PID 99913 after unlock | Install/launch only; no exact-build manual/VoiceOver pass |
| Public URLs | Apex, privacy, terms and deletion return 200; canonical support/navigation are current | Live policy copy remains less complete than tagged source |

Verdict: **not ready to upload** under the strict brief. Local source, database
and distribution artifact gates are green; hosted staging, destructive
deletion, external Auth, exact-build manual accessibility/lifecycle, support
and legal operations, observability/load, and safe production promotion remain
open.

## 48. 2026-08-13 booking-confirmation email source verification

This section began as working-tree evidence for the Build 5 feature slice. The
later hosted preview and external-inbox results are recorded in section 49. A
clean local `v1.0.0-beta.5` tag is frozen after the final checks below; a Build
5 distribution artifact still does not exist.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Flutter | Full 383/383 suite passes after updating the v2 Edge source contract; analysis reports no issues | Local unit/widget/golden source evidence, not deployed E2E |
| Deno | 37 files format-clean, 28 files lint-clean, both new handler entry points type-check, 38/38 full Edge tests pass | Provider calls are mocked; functions are not deployed |
| Local Supabase | Empty reset replays all 55 migrations; lint reports zero warning-level schema errors | Isolated local database |
| pgTAP | Four files, 111/111 assertions pass, including 28 outbox/email-boundary assertions | Hosted preview proof is recorded in section 49 |
| iOS profile | Build succeeds as `1.0.0 (5)`, 71.2 MB; strict code-sign verification passes | Dirty working-tree profile evidence, not an App Store archive/IPA |
| Diff hygiene | `git diff --check` passes | Working tree remains intentionally uncommitted |

The local contracts prove normalized intake, legacy compatibility, private
grants, atomic one-row enqueue, workflow retry idempotency, contact-email
preservation, lease ownership, backoff, stale-lease recovery and terminal
failure. They do not prove Resend delivery, the every-minute scheduler,
SPF/DKIM/DMARC, bounce/suppression handling or recipient/content correctness in
a controlled external inbox. Production remains unchanged.

## 49. 2026-08-13 hosted booking-email rehearsal

Owner-approved preview branch
`booking-email-beta5-rehearsal-20260813` was isolated from production data and
charged at the quoted $0.01344/hour while active. It was cleaned and deleted
after this evidence was captured; production schema and functions were not
changed.

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Hosted schema | All 55 migrations applied; remote lint reports no schema errors | Preview branch, not production promotion |
| Hosted pgTAP | Four files, 111/111 assertions pass | Does not replace production-history reconciliation |
| Staging app E2E | Core workflow, practical two-tenant isolation and signed-out public request/conversion pass on iPhone 17 Pro simulator | Account deletion and external Auth lifecycle remain open |
| Intake safety | Honeypot creates no request; duplicate token creates one request; invalid service is rejected | Load/abuse volume was not measured |
| External delivery | Resend delivered the fixed-sender confirmation to `delivered@resend.dev` with the expected customer, business, title and BST time | Sandbox delivery, not a broad mailbox/client matrix |
| Retry operations | Forced provider 401 leaves the booking successful, records attempt 1 with bounded backoff, then sends after key recovery at attempt 2 | Terminal alerting and human response still need operations ownership |
| Scheduler/auth | Vault-backed pg_cron invokes the custom-token drain every minute; cron succeeds and pg_net receives HTTP 200; missing/wrong tokens return 401 | Must be recreated deliberately during production promotion |
| Domain trust | Resend marks `workloop.uk`, DKIM and SPF verified; message insights mark DMARC valid and plain text present | Bounce/complaint/suppression lifecycle is not yet exercised |

Final source recheck after the two portability/index migrations: 222 Dart files
format-clean, Flutter analysis clean, 383/383 Flutter tests pass, 55 local
migrations replay from empty, 111/111 local pgTAP pass, local database lint is
clean, 38/38 Deno tests pass, all ten Edge entry points type-check, and the iOS
profile build succeeds as `1.0.0 (5)` at 71.2 MB.

## 50. 2026-08-15 TestFlight build 5 handoff

| Evidence | Observed result | Limit |
| --- | --- | --- |
| App Store upload | `1.0.0 (5)` upload is complete and processed; it is attached to `Workloop Private Beta` and is `Waiting for Review` | Apple Beta App Review is pending |
| Distribution provenance | Remote immutable tag resolves to `6ae85c8fff5e523b83b47f357d2d9b4ac4bceede`; local IPA is 33,864,325 bytes with SHA-256 `d01e8aa70cac321f5b2b9f7780704d4f4cb7e341c4f8111534cb70fa64d2787f` | Later website/waitlist/golden-only commits do not alter the tagged mobile binary |
| iOS signature | Strict verification passes; Store profile has `get-task-allow=false`, `beta-reports-active=true` and Sign in with Apple | TestFlight install and interactive physical-device smoke still need a tester |
| Flutter gate | 222 files format-clean, analysis clean, 383/383 tests pass | Automated source/widget evidence |
| Edge gate | 42/42 tests pass; 11 handlers type-check; format and lint pass | Provider and production behaviour additionally rely on the recorded hosted rehearsal |
| Production backend | Current booking-email migrations and functions are deployed; Vault-backed every-minute drain is active; no paid preview branch exists | Bounce/suppression and terminal-failure operations remain an owner support responsibility |
| TestFlight setup | Internal group retains Build 5; external `Workloop Private Beta` contains Build 5 and the submission is waiting for review | Apple approval and first tester install remain pending |
| Public invitation | `https://testflight.apple.com/join/1ycJPHWx` is created with a controlled 50-tester limit | Apple keeps the link closed until the build is approved |
| Reviewer access | Dedicated fictional-data account confirmation email delivered, corrected `workloop.uk` redirect consumed, password grant authenticated, and monitored reviewer contact saved | Credentials live in App Store Connect/local Keychain only |
| Auth redirect boundary | Site URL is `https://workloop.uk`; allow-list retains the two mobile deep links plus `https://workloop.uk/**`; retired `workloop.app/**` was removed | Existing issued links retain their original redirect and should not be reused |

## 51. 2026-08-31 TestFlight build 6 push handoff

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Flutter gate | Analysis clean; 386/386 tests pass; signed iOS profile build passes as `1.0.0 (6)` | Automated source/widget evidence plus development-signed profile build |
| Push worker gate | Edge formatting/type-check passes and 4/4 focused delivery tests pass; an actual APNs ES256 signing check succeeds | Provider failure/retry cases are otherwise mocked |
| Production backend | Push migration and follow-up foreign-key indexes are live; minute worker is deployed; APNs secrets are present; security/performance advisors were reviewed | Local pgTAP was not run because no local Docker/Podman runtime was available |
| Physical iPhone push | Real APNs token registered; Apple accepted controlled privacy-safe sandbox alerts in one attempt; the user visibly confirmed receipt, including a terminated-app check | Foreground duplicate suppression, tap routing, quiet hours and two-account token reassignment remain manual checks |
| App Store IPA | 34,619,970 bytes; SHA-256 `bf109d03084ece3bffec358abf8aba0549a2fd4da92d84efd56cc86a0bd088d1`; strict Apple Distribution signature; Store profile; production APNs; `get-task-allow=false`; `beta-reports-active=true` | Built from the current uncommitted working tree, so no immutable commit/tag provenance exists yet |
| App Store upload | Build 6 upload completed and processed | Upload warned that `StripeTerminal.framework` lacks a matching dSYM, limiting that framework's crash symbolication |
| TestFlight distribution | Build 6 is `Testing` in internal and private groups with 9 invitations and automatic notification enabled | TestFlight showed no Build 6 installations yet at the final check |
| Tester transition | Existing bundle ID, app identity, Supabase workspace and public link are retained; Build 5 testers receive an in-place Build 6 update | Testers still need to choose Update/install it in TestFlight |
| Release selection | Build 6 is attached to both intended groups | A separate Build 7 upload is `Ready to Submit` and intentionally remains outside the external group |

## 52. 2026-09-01 Build 8 feedback source verification

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Flutter gate | 233 Dart files format-clean; analysis clean; 406/406 tests pass, including compact Auth, dashboard first reveal, exact notification routes, schedule exceptions, async lifecycle guards and timezone-aware booking requests | Automated source/widget evidence; no physical-device interaction in this pass |
| Visual gate | Updated login, registration and public-booking goldens were inspected; smallest-phone responsive/auth regressions pass | Deterministic 390 x 844 and responsive test fixtures, not ambient-light or VoiceOver review |
| Edge gate | 59 files format-clean, 47 files lint-clean, all configured handlers type-check and all 65 Edge tests pass | Provider delivery and database RPC calls remain mocked/local |
| Push lifecycle | Direct APNs carries FlutterFire's required message identifier; bootstraps navigate via the app router, defer routes through sign-in, and revalidate user/workspace state around token registration | Physical foreground/background/terminated taps and sign-out races remain manual |
| Database gate | Three new migrations retain default overlap rejection, add explicit owner consent, exact requested instants/timezones, entity-route enrichment and a fail-closed public-workspace-member insert guard | No local replay, lint or pgTAP run because Docker/Podman is unavailable; the production project has no preview branch; not promoted |
| Live read-only check | Production migration history remains at Build 6 push; current advisors were reviewed; 8 ownerless public profiles still expose 29 active services through the old deployed Edge versions | The Build 8 source guard is not live and production was not mutated |
| Compatibility | `create-booking-request` selects the legacy overload when Build 6 omits structured time fields and the exact-time overload for Build 8 | Must still be rehearsed against an isolated hosted branch before production promotion |
| iOS profile | Development-signed `1.0.0 (8)` profile build succeeds at 73.2 MB with APNs development, Sign in with Apple and `get-task-allow=true` | Not an App Store archive/IPA and not installed on a physical iPhone |
| Diff hygiene | `git diff --check` passes | The working tree contains earlier uncommitted Build 6/account/reporting work and has no immutable release provenance |

Build 6 remains the live TestFlight beta. Build 7 predates this feedback. This
source is therefore a Build 8 candidate only; it is not a deployed backend or
tester-visible release.

## 53. 2026-09-01 Build 9 booking and interface source verification

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Flutter | Format clean, analysis clean and 432/432 tests pass after fixing the compact-height Auth overflow and adding narrow current-schema fallbacks | Automated source/widget evidence |
| Visual | 27 launch-surface goldens pass after intentional refresh; key Auth, shell, Work, Money, Business, Settings, booking-request and public-booking light/dark images were inspected | Deterministic fixtures, not physical accessibility review |
| Edge | 63 files format-clean, 50 files lint-clean, configured handlers type-check and 71/71 tests pass | Database/provider calls are mocked or contract-level |
| Database | Availability and add-on/snapshot migrations include pgTAP for privacy, RLS, trusted totals, legacy intake, confirmation snapshots and email wrapping | No local PostgreSQL/Docker runtime; pgTAP has not executed |
| Compatibility | Build 6 intake remains available; the app retries legacy projections only when the new snapshot/add-on relations are specifically absent | New overlap, suggested-time and add-on behavior still requires hosted replay and backend promotion |
| iOS profile | Development-signed `1.0.0 (9)` passes strict verification, installs and launches on the paired physical iPhone; CoreDevice confirmed the process | Install/launch evidence only; development APNs and `get-task-allow=true`, not TestFlight distribution |
| App Store IPA | 34,770,219 bytes; SHA-256 `bc7360754b294aa459fdace3e87b497fcbcd30760f15980ece905e6a423f2c73`; strict-valid Apple Distribution signature; production APNs; `get-task-allow=false`; `beta-reports-active=true` | Built from the current dirty working tree and not uploaded |
| Release identity | Source, installed development profile and distribution IPA are `1.0.0 (9)` | Production backend, physical feature matrix and TestFlight upload remain pending |

## 54. 2026-09-02 Build 9 hosted rehearsal and production promotion

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Hosted branch replay | All five migrations replayed from the production base after correcting conflict targeting, retry ordering, service-role ACL handling and four covering indexes | Disposable branch; deleted after the final run to stop hourly billing |
| Hosted behavior | Exact request/timezone, trusted base and add-on snapshots, duplicate token, exact notification route, bounded availability, default overlap rejection, explicit overlap/out-of-hours acceptance, deactivated-add-on retry and orphan-profile 404 all passed | Controlled branch data, not a physical UI walkthrough |
| Production database | Migrations `20260902172036`-`20260902172046` are live; RLS, grants, triggers and indexes match the branch; advisors show no target-specific security or unindexed-FK finding | Existing private no-policy informational lints and intentional authenticated workflow warnings remain unchanged |
| Production functions | Public profile v25, public booking request v28, availability v1 and scheduled worker v21 are ACTIVE; every retrieved deployed file equals local source | Provider push tap behavior still requires a device lifecycle check |
| Scheduled worker | The protected minute call returned HTTP 200 continuously after v21 deployment | The only stored iOS token is a disabled development token (`apns_baddevicetoken`); a TestFlight launch must register a production token |
| Production public smoke | Existing published profile and suggested availability both returned HTTP 200; the response is capped and uses Europe/London without diary metadata | No synthetic booking request was inserted into a real customer workspace |
| Flutter gate | 234 Dart files format-clean; analysis clean; 435/435 tests pass; signed `ios-profile` build succeeds at 73.4 MB | The paired iPhone was unavailable for a post-promotion install |
| Edge gate | 62 files format-clean, 50 files lint-clean, configured handlers type-check and 71/71 tests pass | Provider calls in unit tests are mocked |
| Fresh App Store IPA | 34,766,683 bytes; SHA-256 `2d4179b6043cd241ee1365fa03d173918ed8497f553c3775644fd5d14f6128a4`; strict Apple Distribution signature; production APNs; Store profile; `get-task-allow=false`; `beta-reports-active=true`; Sign in with Apple | Not uploaded or TestFlight-installed; working tree remains uncommitted |

Build 9 now has a promoted backend and a fresh signed artifact. It is not yet
the tester-visible beta: physical post-promotion checks, two invalid published
service durations and the App Store Connect upload/assignment remain open.

## 55. 2026-09-02 public service duration guard

| Evidence | Observed result | Limit |
| --- | --- | --- |
| Production data | The two outliers (`0` and `9,999,999`) are reset to 60 minutes, inactive and hidden; invalid service count is zero | Owners must review the fallback before reactivating those two services |
| Database boundary | Validated `services_duration_mins_check` enforces 5-1,440; hosted pgTAP completes 9/9 and a controlled absurd update is rejected | Add-on durations intentionally keep their separate 0-1,440 rule |
| Public API | `get-public-profile` v26 is ACTIVE, source-equal and filters the same bounds; both affected handles return HTTP 200 without the quarantined row | Smoke evidence covers the two affected production profiles |
| Flutter and Edge | Analysis clean; 438/438 Flutter tests, 71/71 Edge tests, Edge format/lint/check and signed iOS profile build pass | Automated evidence, not a physical-device walkthrough |
| Fresh App Store IPA | `1.0.0 (9)`, 34,766,747 bytes, SHA-256 `e8e0df6a5b657a8043049503cf5f33d7b68d760120da92eddeeff59d16145006`; strict-valid Apple Distribution, production APNs, Store beta entitlement and Sign in with Apple | Not uploaded to App Store Connect in this pass |

Build 7 remains a separate already-uploaded App Store Connect build and cannot
be replaced by another `1.0.0 (7)`. Build 9 is the current candidate because it
contains the later stability, booking, UI and service-duration work.
