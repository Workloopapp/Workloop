# Workloop Known Quality and Launch Gaps

## Current gap update — 4 September 2026

See [the dated launch audit](../releases/2026-09-04-launch-audit.md) for the current decision. H-01 now has isolated full SQL/RLS replay evidence (PGlite, 413 assertions including OS), but hosted Supabase service/concurrency E2E remains open. Public membership guards have been deployed; H-04's former claim that promotion has not occurred is historical. H-08's absent signing/provenance claim is superseded by clean iOS/Android Build 10 snapshots, verified signed artifacts and external TestFlight distribution; Google Play and public store review remain incomplete.

Hosted authenticated/core-business, two-user SDK and deletion E2E, physical Android/accessibility, real merchant payment/refund, Android FCM credentials/delivery, production iOS push, operator/store/support requirements and load testing remain unclosed. A new Play personal account introduces a 14-day closed-test requirement. Earlier rows below preserve the original findings; they are not a claim that repaired defects remain unfixed.

---

Last updated: 2026-09-01

## How to use this register

This is a release-risk register, not a backlog of every desirable enhancement.
An item closes only when its exit evidence is recorded against the release
commit. A source implementation or written test is not equivalent to a passing
dynamic result.

No confirmed critical cross-user exposure, destructive bypass, or core data-loss
defect was identified in the static/read-only review. That does not prove their
absence because several critical dynamic suites are blocked.

## High-severity release blockers

| ID | Gap | Evidence and impact | Exit evidence | Suggested owner |
| --- | --- | --- | --- | --- |
| H-01 | Clean database replay was not executed for the Build 8 candidate | Docker/Podman is unavailable and the production project has no preview branch. The three new scheduling, entity-route, and public-member-boundary migrations therefore have source/contract coverage but no clean replay or current pgTAP result. | `supabase db reset --local` and `supabase test db` pass on the release SHA, or an approved isolated branch passes migration replay, pgTAP and lint; retain the run evidence. | Backend / QA |
| H-02 | Isolated authenticated core-business E2E is authored but not executed | A guarded staging harness now creates a client, booking, task, unpaid payment and note; completes the work/payment; verifies export; and cleans up. It compiles but has not run because no disposable staging branch/accounts are approved. Onboarding, restart, token expiry and recovery remain outside it. | Automated authenticated journey passes on iOS and Android against disposable Supabase staging, including onboarding, restart and failure recovery. | Mobile / QA |
| H-03 | SDK-level two-account isolation is authored but not dynamically proven | A guarded two-user SDK harness attempts cross-tenant select/insert/update/delete across 13 practical disposable tables: contacts, services, appointments, invoices/line items, expenses, tasks/checklists, notes, notifications, booking requests, push tokens and calendar-sync accounts. It verifies each victim marker remains unchanged and safely skips without two disposable staging accounts; no passing dynamic result exists yet. | Clean-replay pgTAP plus SDK-level two-user suite rejects every cross-tenant operation and validates unchanged victim data. | Backend security |
| H-04 | Build 8 public booking-request staging E2E is not executed | The candidate adds exact timezone-aware request times, working-hours guidance and a fail-closed member boundary. Production still contains 8 ownerless public profiles with 29 active services because the reviewed migration/Edge promotion has not occurred. | Disposable staging covers valid/exact/DST-invalid/outside-hours requests, ownerless-profile rejection, honeypot, invalid service, rate limits, duplicate/parallel submit, recovery, preferences, owner triage, decline and conversion. | Product / Backend / QA |
| H-05 | Account deletion is not verified end to end | Completion is destructive and was correctly not run against production. Sole-owner completion, multi-member rejection, cascade/orphan behaviour, audit access, retry, and operational follow-through remain unknown. | Disposable production-like accounts prove request, export, sole-owner completion, multi-member denial, cleanup, audit protection, retry, and user communication. | Backend / Operations |
| H-06 | Production Auth lifecycle evidence is incomplete | Strong passwords, leaked-password checks, bounded sessions, recovery SMTP, Apple/Google entry and opt-in MFA controls are configured. A fresh external confirmation/recovery/password-change journey, existing-email identity linking and candidate restart/expiry behaviour remain unproven. | External test accounts pass confirmation, recovery, password change, identity linking, token expiry/revocation and restart on both platforms; rate-limit/redirect behaviour is recorded. | Backend / Operations |
| H-07 | Support and legal approval remain incomplete | Canonical `workloop.uk` legal routes are public, but the deployed pages still contain the previous `workloop.app` support identity and navigation wording. Corrected local app/web copy includes Stripe and receipt-email processing, while mailbox monitoring, controller/address/company wording and launch-market legal review remain external. | Add the real operator details, retain launch-market legal approval, publish the reviewed local artifact, verify both hosts and redirects, and actively monitor support. | Operations / Legal |
| H-08 | Current-candidate signing and store operation are incomplete | iOS distribution signing and local IPA export work, but build 3 was not accepted and predates current source/backend changes. Android has no production upload keystore/AAB. The current worktree is dirty and cannot provide candidate provenance. | Clean tagged SHA passes preflight; signed AAB/IPA and signatures/provenance are retained; both console submissions, declarations and review access are complete. | Release manager |
| H-09 | Physical Android and full accessibility/device matrix are incomplete | Automated viewports cannot prove TalkBack/VoiceOver order, permissions, notification delivery, deep links, lifecycle, reinstall/upgrade, keyboard, and OS behaviour. The latest candidate has not completed the full iOS/Android manual matrix. | Signed manual results for a small and current Android device, supported iPhone/simulator set, VoiceOver, TalkBack, large text, reduced motion, permissions, notifications, deep links, offline, reinstall, and upgrade. | Mobile QA |
| H-11 | Brand and store-title clearance is unresolved | Other products use similar Workloop/WorkLoop names. This is not a code defect, but it can block or force a late launch change. | Professional target-market clearance and reservation of both store listing names, with explicit product decision. | Founder / Legal |

## Medium-severity launch risks

| ID | Gap | Impact | Exit evidence | Suggested owner |
| --- | --- | --- | --- | --- |
| M-01 | No staging project or executed load test | No measured RPS, p50/p95/p99, error rate, database pressure, rate-limit response, or post-spike recovery exists. Scale confidence is unknown. | Approved isolated staging; smoke, baseline, moderate, spike, and recovery evidence with integrity checks. | Backend / SRE |
| M-02 | No measured in-app performance profile | Pagination, concurrent client aggregation and a deterministic 10,000-client computation are covered in source/tests, but startup, frame timing, memory, rebuilds, query latency and long-list UI remain unmeasured on target devices. Several primary repositories deliberately page complete datasets. | DevTools/trace evidence before and after fixes on representative iOS/Android hardware and datasets. | Flutter / QA |
| M-04 | CI changes have no hosted pass history | Database and Android integration jobs are configured, but source configuration alone cannot prove runner/tool compatibility or stability. | Successful PR and scheduled workflow URLs retained for release SHA; failures/flakes resolved. | DevOps |
| M-05 | Production crash/error reporting is absent | Post-launch crashes, Edge failures, and degraded journeys may be invisible until users report them. This increases incident time and weakens launch confidence. | Adopt a privacy-reviewed crash/error service or explicitly accept the risk with support/monitoring and rollback procedures. | Product / Engineering |
| M-06 | Repository fakes and network-failure coverage remain thin | Many widget tests exercise UI logic, but real repository failures, timeouts, stale responses, cancellation, and partial payloads are not consistently injectable across modules. | Standard repository fakes cover loading/error/retry/offline/token-expiry for every critical module. | Flutter |
| M-07 | Storage isolation is untested | No launch attachment workflow or bucket policy was identified. Generated file metadata does not prove Supabase Storage security. Risk becomes high if attachments are enabled or marketed. | Keep attachments out of launch claims, or add buckets, least-privilege policies, two-user tests, signed URL expiry, size/type limits, malware/privacy operations. | Product / Backend |
| M-09 | Public booking and Places operational controls are not verified | Server key restriction, quotas, billing alerts, booking salt/limits, timeout behaviour, and external dependency degradation are operational rather than source-only controls. | Staging/production configuration review and monitored smoke tests, without exposing keys. | Backend / Operations |
| M-10 | Reminder behaviour is not proven across device lifecycle | Logic tests cannot prove OS permission denial, reboot, app update, DST/time-zone changes, background limits, reschedule/cancel, and tap routing. | iOS/Android device matrix with controlled clocks and restart/reboot cases. | Mobile QA |
| M-11 | Import and export platform edges remain manual | Retry logic has regressions, but contact/calendar/file picker denial, revocation, malformed files, huge datasets, interruption, encoding, and share-sheet outcomes need device tests. | Permission and failure matrix on both platforms, including duplicate-free partial retry and complete workspace export. | Mobile QA |
| M-12 | Large legacy screens and mixed local routing remain | Oversized booking, finance, tasks, settings, and client files increase regression cost; mixed GoRouter/local routes complicate deep links and restoration. Refactoring now would add launch risk. | No launch-blocking behaviour failure; schedule small, test-backed extractions after release rather than a broad rewrite. | Flutter |
| M-13 | Non-Dart dependency vulnerability coverage is tool-limited | OSV-Scanner 2.4.0 found no issue in 132 resolved Dart packages. It did not recognise the Deno or CocoaPods lock formats; six direct Flutter packages are behind their latest releases. Blind upgrades can also introduce regressions. | Produce an SBOM or use scanners that support the Deno and native graphs; review and test each justified upgrade. | Flutter / Security |

## Closed during this audit

| ID | Closed risk | Exit evidence |
| --- | --- | --- |
| H-10 | Final candidate safe verification was incomplete. | [TEST_RESULTS.md](TEST_RESULTS.md) now records the final 249-test Flutter run, 19-test Deno run, goldens, integration smoke, dependency evidence, generator guards, and supported platform builds. |
| M-03 | Launch goldens were not final or human-reviewed. | Eleven tests produced 13 expected images; every image was reviewed after the final UI change and the non-update suite passed. |
| M-08 | Private workflow tables lacked defence-in-depth RLS. | Live migrations enable RLS, remove client DML, add explicit false client policies, preserve trusted service access, and return the security advisor to only the paid leaked-password warning. |

## Low-severity and follow-up gaps

| ID | Gap | Recommended action |
| --- | --- | --- |
| L-01 | Automated coverage remains uneven by feature even if aggregate line coverage rises. | Track critical behaviours by matrix row; do not chase 100% or use aggregate percentage as the release verdict. |
| L-02 | Edge Deno tests cover selected helpers/functions, not every deployed error path. | Add contract tests for each response code, CORS/auth boundary, malformed payload, timeout, and safe error body. |
| L-03 | Notification history is bounded rather than user-paginated. | Add cursor pagination when real usage shows the owner needs older history; preserve bounded dashboard/provider reads. |
| L-04 | Domain email authentication was not fully verified. | Configure and verify SPF, DKIM, and DMARC for the production sender/support operation. |
| L-05 | Source is prepared as `1.0.0+4`; no clean signed Build 4 artifact exists. | Preserve monotonic build numbers and bind the next signed candidate to its reviewed full commit SHA. |
| L-06 | No automated upgrade/migration compatibility suite exists. | Preserve representative previous-version local data and add upgrade tests before the first update release. |

## Deliberately absent or limited launch capabilities

These are not defects if product copy remains accurate:

- remote APNs/FCM push delivery;
- live or two-way calendar sync;
- operational card-payment collection, deposits, or bank feeds; the default
  beta build hides Stripe collection behind
  `PAYMENT_COLLECTION_ENABLED=false`, while merchant onboarding,
  payment/refund evidence, Apple entitlement, device and release gates remain;
- recurring-series creation or series editing; existing recurrence data remains
  readable, but V1 exposes only single-booking creation;
- subscription entitlement or paid-plan gating;
- file attachments or Supabase Storage-backed user files;
- AI-first workflows or an enabled AI assistant;
- team/staff operation;
- tablet-optimised or landscape UI.

If any store listing, onboarding screen, support response, or marketing page
claims one of these capabilities, the gap becomes a launch-blocking copy defect.

## Release position

The 2026-08-08 refresh passes 346/346 Flutter tests, 25/25 Deno tests,
25/25 protected goldens covering 29 image files, the signed-out iOS simulator journey, all supported
profile/web builds, APK alignment/signature checks, and exact iPhone
install/launch with a CoreDevice-confirmed process. Live read-only inspection
confirms the project is healthy with RLS on all inspected application tables
and only the leaked-password protection security warning.
These results improve source confidence but do not close the isolated backend,
authenticated E2E, destructive, physical Android/accessibility, signing, legal
or operational gaps below.

The three highest-value staging journeys now exist as production-refusing,
write-opt-in integration tests. Their implementation reduces setup work but
does not close H-02, H-03 or H-04 until a disposable branch is approved and the
recorded runs pass.

The current evidence supports continued controlled internal testing. It does not
yet support “technically ready for public release” because H-01 through H-09
and H-11 include unexecuted database/security/E2E/device evidence and external
store operation.

The final safe local suite now passes. A closed beta becomes reasonable only
after the high-risk database/Auth/booking gates needed by beta users are
closed, access is controlled, support is staffed, and no
production-destructive testing is implied. Public store launch still requires
every applicable high-severity exit condition.

## Prioritised closure order

1. Run a clean local Supabase replay and pgTAP in Docker/CI.
2. Provision disposable staging and run User A/User B plus authenticated core
   E2E.
3. Exercise public booking-request and deletion workflows safely.
4. Complete physical Android/iOS, accessibility, permission, reminder, offline,
   lifecycle, and deep-link QA.
5. Enable and test production Auth protections and email delivery.
6. Publish and verify legal/deletion/support operations.
7. Run measured app performance and staged load tests.
8. Configure signing, stores, declarations, review access, and brand clearance.
9. Run and retain hosted CI evidence for the candidate.
10. Tag the exact reviewed candidate and retain all evidence.

## 2026-08-12 superseding release position

The latest safe local evidence is 360/360 Flutter unit/widget tests and clean
analysis, but the signed-out iOS integration journey is red. The current pgTAP
inventory is 82 authored assertions with no clean execution, and all three
write-capable staging journeys remain unexecuted. The present dirty worktree
also correctly fails the new candidate-provenance boundary. These facts
supersede the older “final safe local suite passes” wording above: external beta
invitations are not yet approved.

## 2026-08-12 remediation update

H-12 is closed in local source: the first-run Create account action is visible
above the fold and the signed-out journey passes on the same 402 x 874 iPhone
17 Pro simulator. The full Flutter suite now passes 371/371 and the Deno suite
passes 30/30.

H-01 through H-09 and H-11 retain their evidence boundaries where applicable.
In particular, the MFA/payment/retention fixes are unapplied until a clean
82-assertion migration replay and disposable staging run succeed; the current
dirty owner worktree is not a release candidate; and operational support,
external Auth, physical accessibility, Stripe onboarding/live refund, store,
brand, performance/load, and crash-observability work remain external gates.

## 2026-08-13 superseding gap status

- H-01 is closed for local evidence: all 52 migrations replayed from empty and
  83/83 current pgTAP assertions passed with clean database lint.
- H-08 is closed for the iOS artifact boundary: clean source is committed and
  locally tagged, and an exact-SHA Apple Distribution IPA with matching
  checksum/provenance exists. Apple upload and TestFlight install are not done;
  Android store signing remains open.
- H-07 is narrower than the historical row: live pages already use
  `support@workloop.uk` and current Business deletion navigation. The live
  12 August policy copy still trails the fuller tagged copy, and monitored
  support, named controller details and professional legal review remain open.
- H-02 and H-03 are materially narrower: an owner-approved isolated preview
  branch ran the core, practical two-user-isolation and public-booking journeys,
  plus controlled Resend delivery and real outage/retry recovery. Production
  promotion, disposable account deletion and broader export/destructive checks
  remain open. H-04 and H-05 remain high for payments and operational evidence.
- H-06 and H-09 remain high: local Auth is substantially proven, but external
  provider/email/linking and exact-build physical accessibility, permissions,
  lifecycle, deep-link, reinstall and upgrade evidence are absent.
- M-01, M-02, M-04 and M-05 remain open: no hosted load run, measured startup/
  frame/memory profile, exact-SHA hosted CI, or production crash reporting.

The strict current verdict is **not ready to upload**, despite a valid signed
iOS IPA, because the hosted staging and human/operational gates above remain
unclosed.
