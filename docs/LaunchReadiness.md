# Workloop Launch Readiness

> Current evidence: [7 September launch preparation](releases/2026-09-07-launch-preparation.md). Dated sections below retain their historical findings.

## Current launch decision — 4 September 2026

**Public launch on both iPhone and Android is not yet ready.** iOS Build 10 is externally testing; Android has a signed, emulator-verified AAB but no completed Play registration or distribution. The new personal account requires real-device verification and 12 closed testers continuously opted in for 14 days before a production-access application. Card collection also needs a genuine verified merchant and real charge/refund evidence; demo Clearview cannot supply that.

See [the dated launch audit](releases/2026-09-04-launch-audit.md) for the current authoritative gate list and completed repairs. Historic version numbers, missing-signing claims and earlier test counts below remain historical evidence.

---

Last updated: 2026-08-31

This is the release gate for Workloop 1.0 on iOS and Android. “Code ready”
means the repository passes its automated and device checks. “Store ready”
also requires the external accounts, legal details, hosted pages, signing
credentials, and declarations listed below.

## Product release position

Workloop launches as a mobile-first business operating system for solo service
business owners. Its promise is one calm daily loop:

1. See what is happening.
2. See what needs attention.
3. Take the next useful action without switching tools.

Clients, bookings, money, tasks, and notes are connected operating modules, not
separate mini-apps. V1 must not claim real-time calendar sync, automated bank
feeds, operational card collection, or remote push notifications unless those
services are actually connected and verified. Stripe live credentials and the
server-side live-mode switch are configured, but the first merchant is still
pending hosted onboarding and no live charge/refund has been completed. Payment
collection therefore remains release-gated.

## Repository launch gates

| Area | Gate |
| --- | --- |
| Identity | Workloop name, `com.ismaeel.workloop` identifiers, existing `#C1FF72` app icon, Studio indigo native startup |
| Navigation | Today, Clients, Work, Money, Business; Schedule, Tasks, and Notes are retained views inside Work |
| Visual system | Persisted System/Light/Dark appearances; porcelain Light and midnight Dark; Studio indigo actions; bundled Manrope; shared floating-dock and control geometry; reduced-motion handling; semantic labels |
| Core workflows | Auth/onboarding, clients, atomic/idempotent single-booking and task workflows, money, notes, profile/settings, retry-safe imports, one-time calendar import/export, on-device reminders; recurring-series creation is intentionally outside V1 |
| Trust | Workspace export, protected deletion request, in-app privacy/terms, public policy/deletion artifacts |
| Platform | Flutter 3.44.8; iPhone-only portrait scope on iOS 15+; Android portrait, API 36 target/minimum API 26, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20, Java 17; production network permission, no cleartext release traffic, sensitive backup exclusion, iOS/Android recovery link |
| Quality | Formatting, analysis, full tests, Android profile build with 16 KB page alignment, iOS profile build, web release build; current-candidate physical iPhone install and CoreDevice-confirmed launch, recorded separately from interactive workflow QA |
| Automation | Secret-safe CI runs Flutter formatting/analysis/tests, Deno formatting/checks/tests, Gradle-wrapper validation, Android profile and web builds, plus an unsigned iOS profile build on macOS |

The final verification evidence for a release candidate must be appended to
`docs/CurrentState.md`; failures are never waived silently.

## Production backend gate

Connected project:

- Project: `imtbyrvsonzvtddswbtb`
- Region: London (`eu-west-2`)
- Status checked 2026-08-08: active and healthy on Postgres 17.6.1
- Client access is protected by workspace-scoped RLS; the current security
  advisor reports no missing-RLS or RLS-enabled-without-policy finding.
- Anonymous Data API table grants are removed. Authenticated app tables expose
  CRUD only, while deletion request/audit tables remain Edge-only.
- Public profile, booking request, address search, and deletion operations use
  Edge Functions rather than direct public table access.
- Live migration history checked 2026-07-26 includes:
  `20260726000048` transactional task, `20260726000057` Edge rate limits,
  `20260726000102` deletion-request export,
  `20260726000110` reserved public routes, and
  `20260726000118` transactional booking workflows, followed by
  `20260726000520` explicit client-deny policy for the private Edge rate-limit
  ledger. Test-mode Stripe payment storage and reconciliation were added by
  `20260804181440` and its foreign-key indexes by `20260804181648`.
  Retry/RLS hardening followed as `20260805210418`, with explicit private-ledger
  deny policies in `20260805210559`.
- Repository source routes task creation, booking creation, booking-request
  conversion, and booking completion through authenticated, tenant-validating,
  idempotent workflows. Public request and Places source use bounded private
  rate-limit state.
- The last recorded active Edge deployments include `create-booking-request` v9,
  `places-address-search` v9, `get-public-profile` v7,
  `request-account-deletion` v7, `complete-account-deletion` v10,
  `workloop-ai-assistant` v4 and `stripe-payments` v8. Re-read deployed versions
  from the release environment before promotion rather than relying on this
  historical inventory.
  Structural/grant smoke checks passed. The release gate remains open until the
  production-like signed-out, authenticated-workflow, and destructive deletion
  matrix is recorded.
- The historical transaction-wrapped live schema and tenant-isolation scripts
  reached their final 47th and 14th successful assertions. This validated that
  project state without persisting fixtures; it is not a clean database replay.
- A 2026-08-08 read-only grant/RLS refresh found RLS on all 23 public and all
  four private application tables, zero anonymous table grants, zero client
  grants on private tables, and `account_deletion_audit` as the sole public
  table intentionally unavailable to authenticated clients. The security
  advisor reported only leaked-password protection at that time. The 2026-08-11
  hardening record below supersedes that historical advisor state.

Before submission:

- [x] Add `workloop://reset-password` to Supabase Auth redirect URLs.
- [x] Enable Supabase Auth leaked-password protection. The live Auth service
      also enforces the 12-character uppercase/lowercase/number/symbol policy,
      and the security advisor reports no findings.
- [x] Production SMTP, `auth@workloop.uk`, DKIM/SPF/DMARC and one real
      password-recovery delivery are configured and verified.
- [ ] Complete fresh-account confirmation, password change and recovery with an
      address outside the development team before external beta invitations.
- [ ] Review Auth signup/reset rate limits and enable CAPTCHA if public signup
      abuse warrants it.
- [ ] Confirm `GOOGLE_PLACES_API_KEY` is a restricted server key with quotas and
      billing alerts.
- [ ] Set a dedicated booking rate-limit salt (the function securely derives a
      fallback from the Edge-only service secret) and confirm the
      account-deletion admin token is
      set in production secrets.
- [ ] Apply the candidate migration to isolated staging and deploy the candidate
      `create-booking-request` source there. After the full booking/security
      matrix passes, promote the reviewed versions and record the live
      migration/function versions. Existing production functions were not
      changed during this audit.
- [ ] Exercise account deletion end to end with a disposable production-like
      sole-owner account and record the operational result. Confirm a
      multi-member workspace is rejected at both request and completion
      boundaries.
- [ ] Exercise public profile and booking request abuse controls from a
      signed-out device, including honeypot, duplicate request token,
      source/phone limits, invalid service, and recovery after the limit window.
- [ ] Reconcile the candidate migration and changed Edge source with the final
      isolated-staging evidence before production promotion.
- [ ] Preserve the final verified release state in a clean commit/tag before
      store submission.

Do not remove “unused” production indexes solely because a pre-launch database
has little traffic. Reassess them after representative usage exists.

## Verified release-candidate evidence

Completed 2026-07-26:

- Dart formatting clean across 186 files, Flutter analysis clean, and all 249
  Flutter tests passing with 40.10% line coverage.
- Eleven golden tests produced 13 reviewed images and passed again in non-update
  mode. The responsive matrix covered 108 phone/text-scale renders plus keyboard
  safety.
- Deno formatting/lint and all six entry-point type checks are clean; all 19
  Edge tests pass.
- OSV-Scanner 2.4.0 found no known issue in 132 resolved Dart packages. Deno
  and CocoaPods lock formats were not supported by that scanner and remain a
  documented scope limit.
- The signed-out iOS simulator integration smoke passed. iOS simulator debug,
  device profile, and device release compilation passed; the recovery custom
  scheme is registered.
- The current 34.8 MB profile is installed and launched on the physical iPhone;
  CoreDevice confirmed the Workloop process is running.
- Android debug/profile compilation passed. The profile APK passed 16 KB
  `zipalign` and signature verification.
- Web release compilation passed.
- iOS IPA export is blocked by the missing Distribution certificate/profile.
  Android AAB creation fails closed until the production upload keystore is
  configured.
- Clean Supabase replay/82 current pgTAP assertions, authenticated staging E2E, and
  backend load testing were not executed and remain release gates.

Refreshed 2026-07-28 after the final UI/UX refinement:

- Formatting is clean, Flutter analysis reports no issues, and all 285 Flutter
  tests pass. The focused 86-test usability/refinement matrix and the 11-test
  golden suite also pass.
- Development-signed iOS profile and Android profile APK builds pass. Workloop
  launched on the physical iPhone with a discoverable Dart VM Service, and the
  detached Runner process was confirmed on-device.
- Automated checks cover responsive phone layouts, large text, keyboard
  reachability, reduced-motion branches, semantic actions, retry states, and
  critical booking/request/import recovery. They do not replace manual
  VoiceOver, TalkBack, permission, lifecycle, offline, or physical Android QA.
- The 132-case launch-surface matrix found and now protects a small-phone,
  200%-text booking-request overflow. Native iOS and Android startup surfaces
  use the Flutter graphite background, preventing a light flash.
- Thirteen navigation-assist tests protect the native iOS status-bar bridge,
  implicit and visible-screen scroll targeting, shell-tab independence, native
  clean-route back-swipe eligibility and completion, broad top-zone taps,
  simultaneous visible vertical layers, header-action isolation, direct-route
  and retained-workspace back actions, a populated Clients top-zone journey,
  cancelled pointer sequences, and draft-protected edge-swipe behaviour.
- The source-level UI/UX gate is materially stronger; the backend, security,
  store signing, legal hosting, and manual-device blockers below are unchanged.

Refreshed 2026-08-08 after the final completion sweep:

- Formatting is clean across 205 Dart files, analysis reports no issues, all
  340 Flutter tests pass, and coverage is 9,650/19,424 lines (49.68%).
- The protected golden suite passes 19/19 across 23 image files; the signed-out
  iOS simulator journey passes 1/1.
- Deno format/lint, all eight Edge entry-point checks, and 25/25 Deno tests
  pass. Clean local Supabase replay and pgTAP remain blocked by absent Docker.
- iOS profile (70.7 MB), universal Android profile (155.6 MB), Android arm64
  profile (129.4 MB), and web release (43 MB) builds pass. The arm64 APK passes
  16 KB alignment and v2 signature verification; the iOS app passes strict
  local signature verification.
- The exact iOS candidate installed and launched on the paired iPhone after an
  initial locked-device denial; CoreDevice confirmed the running process.
  Install/launch does not replace interactive workflow or accessibility QA.
- Recurring-series creation is removed from V1 rather than left partially
  functional. Historic recurrence data remains readable and data-compatible.

Refreshed 2026-08-10 after Booking page and public-web consolidation:

- Formatting is clean across 206 Dart files, analysis reports no issues, all
  349 Flutter tests pass, and the protected golden suite passes against its
  reviewed updated Home, Tools, Business profile and public booking images.
- The iOS profile build succeeds at 71.0 MB. The exact build installed and
  launched on the paired physical iPhone through CoreDevice.
- Managed Sites version 4 is publicly deployed with production Supabase runtime
  configuration. Live Home, `/:handle`, privacy, terms and deletion requests
  return successfully, and a honeypot booking request reached the Edge boundary
  without creating data.
- The canonical apex and `www` host are attached but await the supplied DNS
  validation/A/CNAME records and SSL activation. Support monitoring, manual
  signed-out submission, legal approval and store gates remain open.

## External launch blockers

These cannot be completed safely from source code alone:

### 1. Brand clearance and store-name reservation

Other current store products use “Workloop” or “WorkLoop,” including products
in adjacent business/productivity categories. Before spending on launch:

- [ ] Run a professional UK and target-market trade-mark clearance search for
      the word mark and logo in the relevant software/SaaS classes.
- [ ] Reserve the final App Store and Play Console listing names.
- [ ] Decide whether the store-facing title should be the more distinctive
      `Workloop: Solo Business OS` while preserving the product name Workloop.

Do not rename the product from an engineering task without an explicit product
decision.

### 2. Public domain and support operation

On 2026-08-10 the public Sites deployment was published at
`https://workloop-os.ismaeelsmiley.chatgpt.site`. It serves customer booking
pages and the exact public legal endpoints below without Workloop or Sites
authentication. A non-persisting honeypot request also reached the production
booking Edge Function and returned its expected accepted response. On
2026-08-11 the owner registered `workloop.uk`, attached the apex and `www`
hostnames, and published the required routing and validation DNS records. TLS
is active on both hosts and the canonical routes respond over HTTPS. Publication
of the saved `workloop.uk` legal, support, current-navigation and payment-data
copy remains pending explicit approval. The deployed 10 August pages still
contain the previous `workloop.app` support identity and navigation wording.

- `/privacy.html`
- `/terms.html`
- `/delete-account.html`

Before submission:

- [x] Deploy the release web artifact and make the hosted legal URLs public and
      accessible without signing in.
- [ ] Publish the current reviewed local legal artifact, then verify the live
      content, dates, support identity and deletion navigation match the app.
- [x] Apply the supplied apex, `www` CNAME, and validation DNS records, then
      prove those exact custom-domain legal and booking URLs over HTTPS.
- [ ] Redirect the apex and `www` hosts consistently.
- [ ] Create and actively monitor `support@workloop.uk`.
- [ ] Replace generic operator wording in the policies with the legal
      controller/business name, contact address, and any company number.
- [ ] Have the privacy policy and terms reviewed for the launch markets.

### 3. Signing and store accounts

- [ ] Create the Android upload key, keep two encrypted backups, and enable Play
      App Signing. Never commit `android/key.properties` or a keystore.
- [ ] Create the Play Console app with package `com.ismaeel.workloop`.
- [x] Connect the Apple Developer team, allow Xcode-managed App Store signing
      for `com.ismaeel.workloop`, accept the required App Store Connect
      agreement, and export the 1.0.0 (1) App Store IPA successfully.
- [ ] Use the same public version on both stores; build numbers may differ but
      must always increase.

### 4. Store declarations and review access

- [ ] Complete Apple App Privacy from the actual data map.
- [ ] Complete Google Play Data safety and the account-deletion URL.
- [ ] Declare contact, calendar, file, and notification permissions accurately,
      including Android's calendar read/write permission pair and Workloop's
      read-only launch behavior.
- [ ] Supply a dedicated review account with realistic, non-personal sample
      data and working public-profile/booking flows.
- [ ] Add review notes explaining why contacts/calendar are optional imports,
      that Money always supports manual operational records, and whether the
      exact submitted build has the default-off Stripe capability enabled.

## Release commands

Run from the repository root:

```bash
source scripts/dev_env.sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test --coverage \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=ci-public-anon-key
deno fmt --check supabase/functions quality/load
deno lint supabase/functions
deno check --config supabase/functions/complete-account-deletion/deno.json supabase/functions/complete-account-deletion/index.ts
deno check --config supabase/functions/create-booking-request/deno.json supabase/functions/create-booking-request/index.ts
deno check --config supabase/functions/get-public-profile/deno.json supabase/functions/get-public-profile/index.ts
deno check --config supabase/functions/places-address-search/deno.json supabase/functions/places-address-search/index.ts
deno check --config supabase/functions/request-account-deletion/deno.json supabase/functions/request-account-deletion/index.ts
deno check supabase/functions/workloop-ai-assistant/index.ts
deno test supabase/functions
scripts/qa_local_supabase.sh
QUALITY_DEVICE_ID=<simulator-or-emulator> scripts/qa_integration.sh
```

`scripts/qa_local_supabase.sh` requires Docker and must pass before promotion.
Run supported source builds with `RUN_BUILDS=true scripts/qa_all.sh`, or use the
individual build commands recorded in
[`docs/testing/TEST_RESULTS.md`](testing/TEST_RESULTS.md). After the Android
profile build, verify native-library packaging with the SDK's
`zipalign -c -P 16 -v 4` check.

For the signed store artifacts:

```bash
RUN_SIGNED_BUILDS=true RELEASE_EXPECTED_SHA=<reviewed-full-commit-sha> scripts/qa_all.sh
```

The signed-build path fails on every tracked or untracked worktree change,
rejects tracked Android signing material and stale target AAB/IPA files,
verifies the expected commit, and records commit/version/toolchain plus each
new artifact's byte size and SHA-256 under `build/release/`. Keep that
provenance beside the candidate artifacts and store-upload record.

The Android release command is expected to fail immediately until a valid
production keystore is configured. Never work around that guard with a debug or
temporary key for a store upload.

## Manual release matrix

Test at minimum:

- Latest public iOS on a physical iPhone.
- Oldest supported iOS or the closest available simulator.
- A current Google Pixel-class Android device.
- A smaller Android phone at large text size.
- Portrait layout on every launch device. iPad is excluded by the iOS target
  family; Android tablet compatibility needs an explicit Play/device decision.
  Landscape must not be implied by store media.
- System, Light, and Dark appearances, reduced motion, VoiceOver, and TalkBack.
- Fresh install, sign-up, password recovery, interrupted onboarding, sign-out,
  returning session, and offline/error recovery.
- Empty, realistic, and high-volume workspaces.
- UK daylight-saving transition and cross-midnight bookings, plus read-only
  rendering of any legacy recurring records.
- Contacts/calendar permission accepted, denied, and later revoked.
- Task and booking reminder permission accepted, denied, later revoked,
  rescheduled after record changes, restored after app/device restart, and
  opened from a notification tap.
- Partial contacts, calendar, CSV, task-text, and note-text imports: retry only
  the failed records and confirm successful records are not duplicated.
- Booking/task workflow retries with a stable idempotency key and a simulated
  mid-request network interruption.
- Workspace export, deletion request, and support contact.

## Release decision

Ship only when every repository gate passes and every external blocker has a
named owner. A feature that is not operationally connected must be described
honestly or removed from the release surface.

## 2026-08-11 Stripe and TestFlight gates

- [x] Deploy authenticated `stripe-payments` v3 in Stripe test mode.
- [x] Verify Flutter analysis, 359 Flutter tests, Stripe Deno checks, Android
      native compilation, and unauthenticated Edge Function rejection.
- [x] Enable Sign in with Apple for the Workloop App ID.
- [x] Enable Supabase breached-password checks, strong password policy, TOTP,
      bounded sessions, refresh-token replay detection, MFA-aware RLS and
      mandatory database SSL; security advisor is clear.
- [x] Create the App Store Connect Workloop record for `com.ismaeel.workloop`
      (Apple app ID `6800472527`).
- [x] Add the Apple Developer account to Xcode, regenerate signing profiles and
      export a valid 34.3 MB App Store/TestFlight IPA.
- [x] Create the automatically distributed `Workloop Internal Beta` TestFlight
      group. Build 1's upload exposed missing camera/photo-library purpose
      strings from the file-import dependency; build 2 includes the fix, passed
      processing, and is attached to the group as `Ready to Submit`.
- [ ] Build 3 is a locally archived and signature-verified owned-domain
      candidate. Its upload was stopped before acceptance at the owner's request;
      App Store Connect still lists only builds 1 and 2. Do not upload another
      build until the remaining app work is complete and the owner explicitly
      approves it.
- [ ] Google OAuth is configured, enabled and redirect-tested for the owner in
      consent-screen testing mode. Test existing-email identity linking and
      publish the consent screen before a wider external cohort.
- [ ] Verified custom SMTP delivered a real Supabase password-recovery email.
      Confirm fresh signup, confirmation and secure password-change delivery
      with an external beta address before invitations begin.
- [ ] Confirm a fresh Pro scheduled backup appears after 8 August 2026. Decide
      separately whether the paid point-in-time recovery add-on is justified.
- [x] Review and submit the Apple Tap to Pay entitlement request.
- [ ] Await Apple approval, then obtain both development and distribution
      entitlement support before adding the proximity-reader entitlement.
- [x] Complete Stripe platform identity verification; the dashboard also
      confirms business verification complete.
- [x] Review and submit the public `@workloopapp` Stripe profile, including the
      public business contact details.
- [x] Confirm the direct-charge Connect model and Stripe Connect Platform
      Agreement in the dashboard.
- [x] Deploy and verify the public payment setup, success and cancellation
      handoff routes; all four production URLs return HTTP 200.
- [x] Configure the production connected-account webhook and store its signing
      secret plus all four public handoff URLs in Supabase.
- [x] Remove the approved test-only Stripe state, install the authenticated live
      Stripe API key and set `STRIPE_LIVE_MODE_ALLOWED=true` during an explicit,
      supervised cutover. The payment tables are empty after cleanup.
- [x] Verify the live credential against the expected Stripe platform account
      and prove the payment function reaches its HTTP 401 authentication
      boundary rather than the HTTP 503 live-mode block.
- [x] Deploy `stripe-payments` v8 so Stripe platform-profile failures return a
      stable, non-sensitive public error; normalize Edge Function failures in
      Flutter and render them with the shared inline error component. The live
      platform's account creation and onboarding path now uses Accounts v2 with
      the Merchant configuration rather than deprecated v1 account types.
- [x] Retry the deployed Accounts v2 onboarding path from the authenticated app
      and verify the live connected-account row. The account is pending hosted
      onboarding with charges and payouts disabled until requirements are met.
- [ ] Complete Stripe-hosted onboarding, refresh Workloop status and verify the
      connected-account webhook before treating collection as operational.
- [x] Owner reviewed and accepted Stripe's negative-balance liability and ongoing
      seller-compliance acknowledgements. These create financial, reserve,
      risk-monitoring and connected-account communication responsibilities;
      Stripe records both as completed on 12 August 2026.
- [ ] Perform a real-device test-mode matrix: onboarding, payment link success
      and cancel, Tap to Pay, receipt delivery, full/partial refund, dispute and
      interrupted-network retry.
- [ ] Perform one tightly bounded live-money smoke payment and refund after all
      preceding gates pass.

## 2026-08-12 release-candidate audit gate

- Local static analysis and all 360 Flutter unit/widget tests passed before this
  documentation/QA remediation. `git diff --check` was also clean.
- The current signed-out iOS simulator integration journey is **red**: on the
  402 x 874 iPhone 17 Pro simulator the Auth mode toggle is below the tappable
  viewport, so the tap misses and the expected Create-account state never
  appears. This is a beta blocker until fixed and rerun on the exact candidate.
- The current database inventory contains 51 schema/security, 16 isolation and
  15 privileged-MFA/payment-retention assertions (82 total). They are authored,
  not passed: Docker, Supabase CLI and
  a clean replay result were unavailable in this local audit.
- The guarded two-account staging test now attempts read, insert, update and
  delete isolation across contacts, services, appointments, invoices and line
  items, expenses, tasks and checklists, notes, notifications, booking requests,
  push tokens and calendar-sync accounts, while recording owner-cleanup rows
  and refusing production/write execution by default. It still needs a passing
  disposable-staging run on the release SHA.
- `scripts/qa_release_candidate.sh` is now the signed-artifact boundary. The
  signed-build path also rejects stale target AAB/IPA files and records the
  size and SHA-256 of each artifact produced after the clean-SHA preflight. The
  present working tree is intentionally dirty with in-progress owner work, so
  that preflight must fail and no signed artifact from this tree is a candidate.
- Build 3 remains locally archived/signature-verified but was not accepted by
  App Store Connect. It also predates current source/backend payment changes and
  must not be uploaded as the beta candidate.

Release position: source confidence is strong enough for continued developer
testing only. A small invitation-only beta should wait for the red Auth journey,
clean replay/82 pgTAP checks, disposable staging E2E/isolation, fresh external
Auth lifecycle, support/legal operation and current signed-artifact provenance.
Physical Android, accessibility, performance/load, crash observability, Stripe
onboarding/payment/refund and full store operation remain public-launch gates.

## 2026-08-12 remediation verification gate

The current local remediation supersedes the failed signed-out Auth result in
the preceding audit section:

- [x] The first-run Create account action is visible without scrolling and the
      signed-out iPhone 17 Pro simulator journey passes.
- [x] Formatting is clean across 220 Dart files, analysis is clean, and all
      371 Flutter unit/widget/golden tests pass with 52.84% line coverage.
- [x] The 27 protected golden scenarios pass after visual review of the
      intentional Auth and Business compact-layout changes.
- [x] Deno formatting/lint, all eight Edge entry-point checks, and 30/30 Deno
      tests pass using Deno 2.9.5.
- [x] Four deterministic data profiles pass in dry-run mode.
- [x] The signed iOS profile build passes at 71.3 MB and strict code-sign
      verification succeeds.
- [x] The same signed profile installs and launches on the paired iPhone 15 Pro
      Max; CoreDevice confirms the running process. Manual workflow and
      VoiceOver coverage remain open.
- [x] The Android profile APK passes at 158.7 MB, 16 KB alignment, and v2
      signature verification. The profile signature is intentionally a debug
      certificate and is not a store credential.
- [x] The web release build passes.
- [ ] Run the clean migration replay and all 82 pgTAP assertions. No local
      Docker, Postgres, or Supabase CLI runtime is available.
- [ ] Run core, public-booking, expanded two-user isolation, Stripe test-mode
      offboarding, and deletion journeys against a disposable non-production
      project. The connected Supabase account exposes production only.
- [ ] Freeze the reviewed work in a clean commit/tag, rerun this gate against
      that SHA, produce a fresh IPA, upload it, and install the TestFlight copy.

Production migrations and Edge Functions were deliberately not changed from a
dirty local tree. The release-candidate preflight exits 78 until every tracked
and untracked change is intentionally resolved.

## 2026-08-13 exact candidate gate

| Gate | Current exact-tag result | Remaining boundary |
| --- | --- | --- |
| Release identity | Clean `81673f6e5f67b11a5c4f2697e51477d95811ab4f`, local `v1.0.0-beta.4`, `1.0.0+4` | Branch/tag are local-only; no exact-SHA hosted CI evidence |
| Flutter | 222 files formatted, analysis clean, 375/375 tests, 52.86% line coverage, protected goldens pass | Automation is not physical/manual workflow proof |
| Edge | Format/lint/type checks pass; 32/32 Deno tests | Candidate functions are not deployed to staging or production |
| Database | Empty local rebuild applies all 52 migrations; 83/83 pgTAP pass; lint clean | Hosted live-derived staging and safe production promotion remain open |
| Auth | Local confirmation, recovery/password update, token revocation and TOTP/AAL2 pass | Fresh external email/provider/linking and restart/expiry evidence remain open |
| Integration | Signed-out simulator journey passes; three staging suites compile and safely skip | Core, isolation, public booking and deletion require hosted staging |
| iOS artifact | Distribution-signed App Store IPA, strict-valid, `1.0.0 (4)`, 33,854,083 bytes, SHA-256 `2dc632e23f5ea00a54df57405d9b675fb8ca33b749310ba4df5c461a0ca3c6fa` | Not uploaded; no TestFlight install/manual VoiceOver matrix |
| Android | Profile APK builds, is 16 KB aligned and v2-signed for QA | No upload key, release AAB, physical Android or TalkBack evidence |
| Payments | Flutter and candidate Edge gates default false | Production Edge is behind candidate; merchant restricted; no payment/refund evidence |
| Public/legal | Live apex, privacy, terms and deletion return 200 and use `support@workloop.uk`; deletion navigation is current | Live 12 August copy trails the tagged fuller copy; controller details, monitoring and legal review remain open |

Verdict: **not ready to upload**. A valid exact-tag IPA exists, but the strict
definition also requires hosted staging, external Auth and manual exact-build
device evidence. The required Supabase preview branch begins at $0.01344/hour
plus metered usage and needs explicit owner approval. Uploading remains a
separate prohibited boundary until final approval.

## 2026-08-13 Build 5 booking-email gate

- [x] New public requests capture a required normalized customer email; legacy
      rows remain nullable and confirmable.
- [x] Booking confirmation and one private outbox intent commit atomically;
      retries cannot duplicate the request, booking or email intent.
- [x] The stored request email is the immutable delivery address during owner
      confirmation; provider content is escaped and uses a fixed verified
      sender plus a stable idempotency key.
- [x] Delivery has stale-lease recovery, capped exponential retry, an
      eight-attempt/24-hour terminal boundary and honest sent/queued/failed UI.
- [x] Local proof passes all 55 migrations, 111/111 pgTAP assertions, database
      lint, 38/38 Deno tests, both new handler type checks, focused Flutter
      tests, the full 383/383 Flutter suite and Flutter analysis.
- [x] An iOS profile build compiles and signs as `1.0.0 (5)` at 71.2 MB and
      passes strict code-sign verification. It is working-tree evidence, not a
      distribution candidate.
- [x] Rehearse all 55 migrations without a blanket production push, then deploy
      `create-booking-request`,
      `confirm-booking-request`, and `drain-booking-confirmation-emails` in that
      order on a disposable preview branch. Production remains unchanged.
- [x] Configure `RESEND_API_KEY`, verified
      `BOOKING_CONFIRMATION_EMAIL_FROM`, and a random 32+ character
      `BOOKING_CONFIRMATION_DRAIN_TOKEN`. Deploy only the drain with
      `--no-verify-jwt`, then schedule its token-authenticated POST every minute.
- [x] In disposable staging, prove a controlled Resend inbox receives one
      correctly timed confirmation after owner acceptance; exercise duplicate
      submission, honeypot, invalid service, atomic conversion and a real
      provider 401/retry/recovery. Resend reports delivered, verified DKIM/SPF,
      and a valid DMARC record.
- [ ] Exercise bounced/suppressed recipients and deletion/export behaviour in
      disposable staging; keep operational bounce monitoring explicit.
- [ ] Monitor terminal failures and oldest pending age, with a documented owner
      response to contact the customer directly.
- [x] Freeze the fully verified `1.0.0+5` source as a new immutable local
      `v1.0.0-beta.5` tag.
- [ ] Build/sign a new distribution IPA from that exact tag, then repeat the
      artifact signature/provenance and TestFlight-install gates.

A metered preview branch was created with owner approval at $0.01344/hour,
rehearsed, cleaned and deleted after evidence capture. Build 4 must not be
reused or retagged for this changed public data and transactional-email
contract. Production promotion and Apple upload remain separate approval
boundaries.

## 2026-08-15 TestFlight distribution status

- [x] Promote the reviewed booking-email schema, functions, secrets and
      minute-by-minute retry worker to production in the rehearsed order.
- [x] Verify production is healthy, current migrations/functions are present,
      the retry job is active, no paid preview branch remains, and payments are
      still closed by default.
- [x] Export and strictly verify the exact-tag `1.0.0 (5)` App Store IPA; retain
      its immutable SHA/tag provenance.
- [x] Upload Build 5 and confirm App Store Connect reports the upload complete.
- [x] Add accurate What to Test, beta description, URLs, feedback contact and
      review notes, and create `Workloop Private Beta` as the external group.
- [x] Correct the production Auth site URL and web redirect allow-list from the
      retired third-party-owned domain to `workloop.uk`; confirm a dedicated
      reviewer account and verify password sign-in without storing credentials
      in the repository.
- [x] Save the owner's monitored reviewer phone number, attach Build 5 to the
      external group, submit it for Beta App Review, and create the controlled
      50-tester public link. Build 5 is `Waiting for Review`; Apple keeps the
      link closed until approval.
- [ ] Share `https://testflight.apple.com/join/1ycJPHWx` after approval, then record
      one real TestFlight install/launch and the short physical-device smoke.

## 2026-08-15 account email pack

- [x] Author consistent Workloop templates for confirmation, invitation,
      magic-link, email change, recovery, reauthentication and all seven
      enabled Auth security notifications.
- [x] Add a private one-per-user post-verification welcome outbox, service-only
      claim/finish boundaries, bounded retry and shared scheduled delivery.
- [x] Prove a clean 56-migration replay, 156 pgTAP assertions, zero database
      lint findings, and the 48-test Edge suite locally.
- [x] Confirm every reviewed template is saved in hosted Auth settings.
- [x] Promote the new migration and scheduled-worker version 8; verify the live
      trigger, private grants and empty initial queue.
- [ ] Complete one fresh external signup: branded verification received, link
      opens the app, one welcome received after confirmation, no duplicate
      welcome on retry.

## 2026-08-15 account deletion email receipts

- [x] Queue a request-received email only after the protected deletion request
      is recorded, with explicit copy that deletion is not yet complete.
- [x] Queue a separate completion email only on the authoritative transition to
      `completed`, after workspace and Auth deletion.
- [x] Keep recipients/events private and fixed, with unique jobs, leases,
      provider idempotency and bounded retry.
- [ ] Exercise both messages with a disposable deletion account and controlled
      inbox before calling the destructive production journey externally proven.

## 2026-08-15 lifecycle and operating automation gates

- [x] Block pending/deleted identities before workspace resolution and prevent
      them from re-entering onboarding with a cached local session.
- [x] Revoke refresh sessions and ban the identity when deletion is requested;
      complete requests through a bounded protected scheduled worker.
- [x] Make deletion independent from transactional-email failures and support
      only the unambiguous zero-membership orphan recovery case.
- [x] Add preference-aware waiting-booking, overdue-payment and daily-brief
      attention with stable deduplication; retain the existing appointment and
      task device reminder scheduler.
- [x] Add private stuck-deletion/email-health alerts and scheduled minimisation
      for notification, token, rate-limit, webhook and deletion metadata.
- [x] Add an opt-in weekly completed-backup freshness check using a read-only
      Management API credential.
- [x] Replay the new migrations and pgTAP suite on a disposable Supabase branch;
      the hosted operational suite passed all 20 assertions and the branch was
      deleted.
- [x] Promote migrations and the scheduled worker in reviewed order, configure
      `OPERATIONS_ALERT_EMAIL`, and verify the existing minute schedule invokes
      the new worker version successfully.
- [x] Configure `ENABLE_BACKUP_HEALTH`, `SUPABASE_PROJECT_REF` and a 90-day,
      single-project, backup-read-only token in GitHub. A direct check passed
      against a completed 15 August backup; the first scheduled GitHub run
      still depends on committing this workflow and script to the default branch.
- [ ] Prove request, forced sign-out, completion, both emails, fresh re-signup,
      alert delivery and retention with a disposable account before calling the
      production lifecycle automated.

## 2026-08-31 Build 6 push and TestFlight gates

- [x] Advance the app to `1.0.0+6` without changing its bundle ID or Supabase
      workspace identity, so Build 5 testers update in place and keep data.
- [x] Add FCM/APNs client registration, refresh, sign-out cleanup, foreground
      refresh and allow-listed notification routing.
- [x] Add a private durable push outbox, preference/quiet-hour enforcement,
      leased claim/finish RPCs, bounded retries, dead-token disabling and
      privacy-safe lock-screen copy.
- [x] Pass Flutter analysis, all 386 Flutter tests, focused golden/push tests,
      Edge format/type-check/tests, database lint, plist lint, diff check and
      the `1.0.0 (6)` iOS profile build.
- [x] Attach Firebase to billed project `workloop-502614`, register the iOS app,
      enable Push Notifications for `com.ismaeel.workloop`, create one APNs
      authentication key, and configure both Apple environments in Firebase.
- [x] Store the APNs provider fields as Supabase Edge secrets; never commit the
      private key. `GoogleService-Info.plist` is Firebase's client-safe app
      configuration file.
- [x] Apply migration `20260831165521`, deploy the reviewed scheduled worker,
      and verify security/performance advisors plus an empty healthy outbox.
- [x] Install a development-signed Build 6 profile on a physical iPhone, grant
      notification permission, register a live APNs token and visibly receive
      controlled privacy-safe sandbox alerts, including after termination.
- [ ] Complete the remaining physical-device matrix for foreground duplicate
      suppression, tap/deep-link routing, quiet hours and sign-out/re-sign-in
      token reassignment.
- [x] Produce and strictly verify a distribution-signed Build 6 IPA with
      production APNs entitlement, upload it, and attach the same processed
      build to `Workloop Internal Beta` and `Workloop Private Beta`.
- [x] Keep the existing public link and tester membership. Publish the update
      instruction after processing; TestFlight will offer Build 6 as the normal
      update to the existing Workloop app.
- [x] Confirm App Store Connect reports Build 6 as `Testing` in both groups,
      with all 9 private-beta testers invited and automatic notification
      enabled. An unrelated Build 7 upload remains `Ready to Submit` and is not
      attached to the external group; Build 6 is the active beta release.

## 2026-09-01 Build 8 feedback gates

- [x] Refresh expired Auth access tokens before treating a session as terminal;
      clear user-scoped providers before revealing another workspace.
- [x] Keep standard-iPhone sign-in visible, preserve small-phone/keyboard/large-
      text scrolling, and hold dashboard reveal for one coherent data snapshot.
- [x] Route booking, booking-request, payment, task and note notifications to
      exact allow-listed UUID entities; fall back safely for malformed routes.
- [x] Add a booking-request push route and exact routes for local booking/task
      reminders without exposing customer detail on the lock screen.
- [x] Let owners explicitly accept overlaps and outside-hours work after a calm
      warning while keeping server conflict rejection as the default.
- [x] Preserve public request date/time as `timestamptz` plus the verified
      workspace timezone, with DST-invalid wall times rejected.
- [x] Keep the booking Edge endpoint backward compatible with Build 6 payloads
      during staged backend promotion.
- [x] Make public services selectable, show friendly durations and 12-hour
      opening times, anchor preview navigation, and accept service hours/minutes.
- [x] Pass Flutter analysis, all 406 Flutter tests, auth/public golden review,
      Edge format/lint/type-check, all 65 Edge tests, diff hygiene and a signed
      `1.0.0 (8)` iOS profile build with development APNs entitlement.
- [x] Make request-time availability guidance use the workspace wall clock and
      selected service duration without exposing existing bookings or implying
      that a request is confirmed.
- [x] Add the APNs message identifier required by FlutterFire tap callbacks,
      route from the app router rather than an inherited context above it and
      defer an exact route safely through sign-in.
- [x] Guard async saves, navigation refreshes and push registration against
      disposal, sign-out and superseded user/workspace context.
- [x] Require a current workspace member at both public service-role endpoints
      and at booking-request insert time. Production still has 8 ownerless
      public profiles exposing 29 active services until this is promoted.
- [ ] Replay and lint the three new migrations on an isolated Supabase branch;
      run the expanded pgTAP push/scheduling/public-boundary assertions. The
      production project currently has no preview branch and local
      Docker/Podman is unavailable, so this evidence is not yet captured.
- [ ] Promote migrations and the backward-compatible Edge Functions in reviewed
      order, then verify production function versions, grants and outbox health.
- [ ] On a physical iPhone, prove background/terminated/foreground push taps to
      each entity type, expired-session resume, no dashboard data flash, exact
      booking-request wall time, and both schedule-exception confirmation paths.
- [ ] Produce an immutable distribution-signed Build 8 archive, upload it and
      assign it to the intended TestFlight groups. Build 6 remains active until
      those release-specific gates pass.

## 2026-09-01 Build 9 booking and interface gates

- [x] Replace the Auth loop mark with the canonical app icon and remove the
      standard-iPhone crowding without breaking compact-height scrolling.
- [x] Replace underline-led navigation with restrained filled selection states,
      align root create actions and normalize shared header colour hierarchy.
- [x] Standardize all feature and Settings bottom sheets on one theme-owned
      handle, radius, surface and padding system.
- [x] Remove decorative service icons and add parent-scoped owner extras with
      bounded price/duration inputs.
- [x] Add immutable request/appointment item snapshots, including automatic
      trusted base snapshots for requests created by legacy intake clients.
- [x] Add privacy-safe suggested public times and recalculate them from trusted
      selected-extra duration while retaining manual exceptional requests.
- [x] Pass format, analysis, 432 Flutter tests, refreshed light/dark golden
      review, all configured Edge type-checks and 71 Edge tests.
- [x] Keep the candidate operational against the current production schema by
      retrying legacy projections only when the new snapshot/add-on relations
      are specifically absent.
- [ ] Replay the availability/add-on migrations and pgTAP 011/012 on isolated
      PostgreSQL, including legacy confirmation, appointment snapshot and email
      outbox assertions. Local Docker/Postgres is unavailable.
- [ ] Promote migrations in order and deploy `get-public-profile`,
      `create-booking-request` and `get-public-booking-availability`; then run
      security/performance advisors and controlled public-flow smoke tests.
- [x] Build, strictly verify, install and launch the development-signed
      `1.0.0 (9)` profile on the paired physical iPhone.
- [ ] Exercise light/dark, keyboard sheets, overlap, outside-hours, extras,
      suggested times and notification route lifecycles after backend staging.
- [x] Produce and strictly verify the 34,770,219-byte distribution-signed
      Build 9 IPA with production APNs and App Store beta entitlements.
- [ ] Upload Build 9 and attach the processed build to the intended TestFlight
      groups after backend promotion and the physical feature matrix.

## 2026-09-02 Build 9 promotion evidence and remaining release gates

- [x] Replay all five booking migrations on a disposable hosted branch and run
      controlled exact-time, duplicate, snapshot, route, availability,
      overlap, outside-hours, retry and orphan-workspace smoke checks.
- [x] Correct the two rehearsal failures, add the four missing composite
      foreign-key indexes and re-run RLS, ACL, trigger and advisor checks.
- [x] Delete the paid preview branch after the final evidence was captured.
- [x] Promote production migrations `20260902172036` through
      `20260902172046` in order and deploy the four matching Edge bundles.
- [x] Verify production function versions and file equality, service-role-only
      RPC execution, new-table RLS/grants, required triggers and absence of new
      migration-specific security or unindexed-foreign-key findings.
- [x] Confirm the live public-profile and bounded suggested-availability flows
      return HTTP 200 against a published production service.
- [x] Confirm the protected minute worker returns HTTP 200 after the v21 push
      bundle deployment and dead provider tokens remain disabled.
- [x] Re-run the complete local gate: formatting, analysis, 435 Flutter tests,
      71 Edge tests, configured type-checks, diff hygiene and signed iOS profile
      build.
- [x] Produce and strictly verify a fresh distribution-signed `1.0.0 (9)` IPA:
      34,766,683 bytes, SHA-256
      `2d4179b6043cd241ee1365fa03d173918ed8497f553c3775644fd5d14f6128a4`,
      production APNs, Store profile, `get-task-allow=false` and
      `beta-reports-active=true`.
- [ ] Correct or unpublish the two active public services whose stored duration
      is zero or 9,999,999 minutes after the owner supplies their real values.
- [ ] Connect and unlock the paired iPhone, install this post-promotion source,
      and exercise light/dark, keyboard sheets, add-ons, suggestions, overlap,
      outside-hours, exact request time, session resume and notification taps.
- [ ] Launch the TestFlight-signed build with notification permission and
      confirm it replaces the disabled development APNs token with an active
      production token before sending the tap-routing matrix.
- [ ] Upload Build 9, wait for processing, attach that exact build to the
      intended TestFlight groups and verify the existing public link offers the
      update. Build 6 remains the tester-visible release until then.

## 2026-09-02 service duration production guard

- [x] Quarantine the two invalid public services without deleting owner data or
      altering booking history; both are inactive and hidden pending review.
- [x] Validate `services_duration_mins_check` in production at 5-1,440 minutes
      and prove an attempted 9,999,999-minute update is rejected.
- [x] Deploy `get-public-profile` v26 with matching duration filters and verify
      both affected public profiles omit their quarantined service.
- [x] Add repository, migration, Edge and pgTAP regression coverage.
- [x] Re-run analysis, 438 Flutter tests, 71 Edge tests, Edge format/lint/check,
      hosted pgTAP and the signed iOS profile build.
- [x] Rebuild and strictly verify the App Store `1.0.0 (9)` IPA: 34,766,747
      bytes, SHA-256
      `e8e0df6a5b657a8043049503cf5f33d7b68d760120da92eddeeff59d16145006`,
      production APNs, Store profile, `get-task-allow=false` and
      `beta-reports-active=true`.

## 2026-09-04 Quiet + Warm Build 11 superseding release status

- [x] Implement and review the approved full visual identity across app, native
      assets, public/private websites, hosted emails and Stripe platform branding.
- [x] Pass analysis, 485 Flutter tests and the separate enabled-payment flag suite.
- [x] Produce strictly verified signed iOS and Android Build 11 artifacts.
- [x] Install and launch the signed iOS profile on the physical iPhone; derive,
      install and inspect Android APKs from the exact signed release bundle.
- [x] Upload iOS Build 11, obtain external beta approval and assign it to the
      existing 13 private beta testers. It is now available to update.
- [x] Create editable Canva masters and a reproducible brand export kit.
- [x] Apply and visually verify the new Instagram avatar.
- [ ] Apply the prepared TikTok avatar after completion of sign-in.
- [ ] Complete Google Play registration, verification and required testing.
- [ ] Validate real merchant card collection/refund after genuine onboarding;
      the only connected sample company is fictional and must not be activated.
- [ ] Complete remaining physical workflow and production notification checks.
- [ ] Complete public store review and approval for both platforms.

See `docs/releases/2026-09-04-quiet-warm-rollout.md` for exact artifacts, coverage
and evidence limits. Earlier build entries remain historical records.


## Launch gate update — 7 September 2026

See [the overnight release record](releases/2026-09-07-launch-preparation.md) for current source/backend/site evidence, lifetime beta access and new pricing. Older brand/build/pricing descriptions above are historical. Public iOS launch remains gated on verified store purchases, public review and genuine merchant payment testing; Android additionally requires external account/push setup.
