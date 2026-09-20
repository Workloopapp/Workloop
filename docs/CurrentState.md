# Workloop Current State

## Current verification — 4 September 2026

**Build 10 is now externally available in TestFlight.** The signed Android Build 10 is built and emulator-verified, but Play registration/distribution is incomplete. Hosted card collection is enabled; real-money verification remains blocked on a genuine merchant. Clearview is a fictional demo.

See [the authoritative dated audit](releases/2026-09-04-launch-audit.md) for source/artifact identities, deployed website/backend changes, completed checks and remaining launch gates. The older sections below describe historical candidates and must not be read as current distribution status.

---

Last updated: 2026-09-01

## 2026-09-01 beta feedback implementation candidate

- Source identity is now `Workloop 1.0.0 (8)`. Build 7 already exists in App
  Store Connect and predates this feedback, so these changes must not be
  distributed under that build number. Build 6 remains the current TestFlight
  beta until a separately verified Build 8 is uploaded and assigned.
- Expired access tokens are refreshed and retried instead of being treated as
  an automatic sign-out. Only explicit terminal session/user conditions clear
  local account state. User-scoped providers are reset before a new workspace
  is revealed, and the dashboard waits for its first coherent data snapshot.
- The auth surface uses a compact phone layout that keeps sign-in visible on a
  standard iPhone while retaining scrolling for keyboards, small phones and
  larger accessibility text. The owner booking-page preview back control is
  anchored to the top safe area.
- Notification routes are allow-listed to exact bookings, booking requests,
  payments, tasks and notes. Local reminders and remote pushes carry the exact
  entity route, including new booking-request notifications.
- Owners can explicitly save overlapping or outside-hours bookings after a
  calm warning. Conflict rejection remains the server default when consent is
  absent. Public requests now persist the exact requested instant and workspace
  timezone; legacy Build 6 payloads remain accepted during the staged rollout.
- Public services are directly selectable, opening hours use a 12-hour display,
  service durations use friendly hours/minutes, and service setup accepts
  separate hour/minute fields with an immediately editable name.

This section describes verified source, not a live backend deployment or a
TestFlight Build 8. The two migrations and updated public-profile/booking Edge
Functions must be promoted in release order, followed by physical-iPhone push,
resume, booking-time and schedule-exception checks.

## 2026-08-31 TestFlight beta 6 handoff

- `Workloop 1.0.0 (6)` is processed and `Testing` in both `Workloop Internal
  Beta` and `Workloop Private Beta`. The private group retains its existing 9
  testers and automatic tester notification is enabled, so Build 5 installs
  update in place through TestFlight without changing account or workspace
  identity. The existing public invitation remains
  `https://testflight.apple.com/join/1ycJPHWx`.
- The uploaded App Store IPA is 34,619,970 bytes with SHA-256
  `bf109d03084ece3bffec358abf8aba0549a2fd4da92d84efd56cc86a0bd088d1`.
  It is Apple Distribution signed, strict-valid, uses the Store profile, has
  `get-task-allow=false`, `beta-reports-active=true`, and carries the production
  APNs entitlement. Upload processing warned that `StripeTerminal.framework`
  has no matching dSYM; this limits symbolication for that framework but did not
  block testing or push delivery.
- Firebase is attached to existing billed Google project `workloop-502614` and
  the iOS app uses the shared sandbox/production APNs authentication key. The
  provider private key remains outside the repository. Supabase stores the APNs
  provider fields as Edge secrets and the scheduled delivery worker sends
  privacy-safe alerts directly through APNs without weakening Google's
  service-account-key organisation policy.
- A development-signed Build 6 profile registered a real iPhone APNs token and
  a controlled sandbox alert was accepted by Apple in one attempt and visibly
  received by the user, including a terminated-app check. Foreground duplicate
  suppression, tap/deep-link routing, quiet hours and two-account token
  reassignment remain explicit manual-beta checks.
- App Store Connect also contains a separate Build 7 upload in `Ready to
  Submit`; it is not attached to the external group. Build 6 remains the active
  beta release.

## 2026-08-15 TestFlight beta 5 handoff

- Apple has processed `Workloop 1.0.0 (5)` successfully. The upload is complete,
  the build is attached to `Workloop Internal Beta`, and the exact local
  distribution IPA still matches immutable tag `v1.0.0-beta.5` at commit
  `6ae85c8fff5e523b83b47f357d2d9b4ac4bceede` with SHA-256
  `d01e8aa70cac321f5b2b9f7780704d4f4cb7e341c4f8111534cb70fa64d2787f`.
- App Store Connect now has tester-facing What to Test notes, a concise beta
  description, the Workloop marketing and privacy URLs, feedback email, and
  reviewer notes that describe optional permissions, request-only public
  booking, portrait scope, and the payments-off boundary. A dedicated
  fictional-data reviewer login is confirmed and its credentials are stored in
  App Store Connect and the owner's local Keychain, not in source control.
- The external `Workloop Private Beta` group contains Build 5. Reviewer contact
  and dedicated sign-in details are saved, Apple accepted the Beta App Review
  submission, and the build is `Waiting for Review`.
- A public invitation URL is created with a controlled 50-tester limit:
  `https://testflight.apple.com/join/1ycJPHWx`. Apple keeps the link closed until
  the build is approved; the first tester install and physical-device smoke
  remain pending.
- Production Supabase is healthy and now contains the booking-email migrations,
  the three current booking functions, the minute-by-minute Vault-backed drain,
  and the independently deployed private launch waitlist. No paid preview
  branch remains active. Payment collection remains disabled in both the app
  and Edge Function boundary.
- The release handoff found and corrected a stale Auth default redirect:
  production now uses `https://workloop.uk`, explicitly allows
  `https://workloop.uk/**`, retains the two mobile deep links, and no longer
  allows the third-party-owned `workloop.app` origin. A resent confirmation
  reached the verified sender path, the reviewer account confirmed, and a
  password sign-in succeeds.
- Fresh handoff checks pass: 222 Dart files are format-clean, Flutter analysis
  is clean, 383/383 Flutter tests pass, all 11 Edge entry points type-check,
  Deno formatting/lint pass, and 42/42 Edge tests pass. Strict IPA code-sign
  verification passes with the App Store profile, `get-task-allow=false`,
  `beta-reports-active=true`, and Sign in with Apple.

## 2026-08-15 public-launch waitlist boundary

- The marketing funnel can collect explicit early-access consent through a new
  `join-waitlist` Edge Function and private `app_private.launch_waitlist`
  table. Email is normalized, direct client table access is denied, duplicate
  responses are non-disclosing, and abuse throttling uses only a salted email
  hash rather than a stored IP address.
- The migration, function, tests and production deployment evidence must be
  verified independently from the immutable `v1.0.0-beta.5` mobile candidate;
  the website capability does not change that signed Build 5 binary.
- Every accepted signup now creates one private welcome-email outbox record in
  the same transaction. Resend delivery uses a stable idempotency key, immediate
  delivery when available, and the existing scheduled retry boundary. The
  receipt explains what Workloop does, what happens next, beta payment terms,
  planned pricing, support and how to unsubscribe.

## Completed / Mostly Working Features

### 2026-08-11 production identity, email and owned-domain cutover

- `workloop.uk` is registered to the owner and is now the canonical Workloop
  web, booking-page, legal and support origin. The previous `workloop.app`
  assumption is retired because that domain is owned by a third party.
- Google and native Apple sign-in are enabled in the hosted Supabase project.
  Google remains in OAuth testing mode for the owner account until the public
  consent-screen requirements and external beta cohort are ready.
- Resend verified `workloop.uk` in Ireland with isolated DKIM and SPF records.
  Supabase Auth uses an encrypted, sending-only API key scoped to that domain,
  sends as `auth@workloop.uk`, and delivered a real password-recovery message.
- Auth email capacity is 30 messages per hour and all seven security-change
  notifications are enabled. UK2 has email two-factor authentication and an
  independent recovery email. DMARC rejects unauthenticated apex and subdomain
  mail after the verified delivery path proved healthy.
- The public Sites deployment has active TLS on both the apex and `www` custom
  domains, and the canonical legal routes respond over HTTPS. Publishing the
  saved legal-contact update is the final web-content handoff.

### 2026-08-11 stable cold-start dashboard reveal

- A cold authenticated launch now keeps the intentional `Opening Workloop`
  state visible until the Today schedule and dashboard-attention calculation
  have either loaded or failed. The ready dashboard then enters with one short,
  reduced-motion-aware crossfade instead of briefly rendering an empty purple
  Today panel and allowing later sections to jump position.
- The opening gate latches after its first successful reveal. Pull-to-refresh,
  workspace refreshes, and provider refreshes keep the dashboard mounted and
  cannot replay the app-opening state.
- Finance and Notes visual fixtures now use explicit reference dates, removing
  day-boundary drift from the protected Money chart and note-date goldens.
- Analysis is clean and the complete Flutter suite passes 353/353 tests,
  including dedicated cold-start/reveal and refresh regression coverage.

### 2026-08-10 operating-loop navigation and Business workspace

- The primary shell now follows the owner's operating loop: Today, Clients,
  Work, Money, and Business. Money is one tap away rather than hidden in an
  overflow page, and the former Tools destination is no longer part of the
  user-facing shell.
- Work is one retained workspace with Schedule, Tasks, and Notes as peer views.
  Each view keeps its existing provider, editor, draft, filters, routes, and
  data contracts; the shared selector changes only information architecture.
- Business now leads with a computed Booking page status, public link, waiting
  request count, and one Manage booking page action. Services, Working hours,
  and Business profile follow as the customer-facing business essentials.
  Settings is reduced to a compact secondary header action.
- The former Tools quick-capture grid is not repeated in the new hierarchy.
  Each feature retains its own contextual `+` action, keeping creation close
  to the destination where the resulting record will live.
- Light and Dark protected visuals cover the five-item navigation, Work
  schedule hierarchy, and Business landing page. The complete Flutter suite
  passes 352/352 tests and analysis is clean. The iOS profile build succeeds at
  70.9 MB, installs on the paired physical iPhone, and launches successfully
  after the device was unlocked. This proves install and launch, not a full
  signed manual workflow or accessibility walkthrough.

### 2026-08-10 muted Dark mode and active-job orientation

- Bookings now prioritises operational work over view controls. Its header copy
  stays on one line and root gaps are tighter. Today, Upcoming, Past and
  Calendar now form one full-width navigation rail; the redundant List label
  and second control are removed. The low-action seven-day load graphic and
  full-width Schedule/Requests switch remain absent, bringing the first booking
  materially higher in the initial viewport. Booking requests remain visibly
  owned by Bookings through a counted inbox action that opens the dedicated
  Active/New/Closed request workspace.
- Calendar mode now uses fixed-height date cells and places the selected-day
  agenda directly beneath the month grid. Calendar and Schedule now render the
  same shared booking-record row: start and end time, slim status marker,
  client, service/location, price, state metadata and divider rhythm. Calendar
  retains its continuous time rail; Schedule retains its time filters and
  grouping.
- Notes now renders pinned and dated collections as flat divider-led rows
  rather than individual rounded cards. Search, filters, imports, editor flows,
  linked-client context and deletion safety are unchanged.
- Dark appearance now uses neutral graphite and slate canvas layers instead of
  violet-tinted surfaces. Periwinkle remains a controlled action, focus and
  selection signal; it no longer colours the entire atmosphere of the app.
- Home's Dark hero uses a deep desaturated indigo field with high-contrast
  white hierarchy. The surrounding backdrop texture is quieter, while cards,
  dividers and secondary copy separate more clearly from the canvas.
- The Home schedule path now distinguishes the current-time tick from the
  selected booking. The selected booking has a larger halo and travels to the
  next booking position with a restrained 280 ms settling bounce when the
  owner swipes the Today carousel. Reduced Motion jumps directly to the stable
  selected state.
- Verification passes formatting across 208 Dart files, clean analysis,
  347/347 Flutter tests, 25/25 Deno tests, the responsive/text-scale checks and
  25/25 protected golden scenarios. Fresh profile builds pass for iOS (70.3
  MB) and universal Android (156.7 MB). The signed build was installed and
  launched on the paired iPhone; the final Notes-list revision was subsequently
  installed and CoreDevice confirmed PID 84974. This proves
  install and launch, not a completed interactive accessibility walkthrough.

### 2026-08-08 command-centre UI polish

- Home keeps the purple Today command panel, while its supporting content is
  calmer and easier to scan. Worth-a-look and feed rows have consistent icon
  insets, Business feed is promoted above Coming up, and Money, Tasks and Notes
  share one divider-led At a glance workspace.
- The Money summary uses real paid-this-month and monthly-target values in a
  compact progress dial. It intentionally lives in At a glance rather than the
  Today panel so financial context does not compete with the owner's immediate
  daily action.
- Bookings now labels its List and Calendar view choice instead of placing a
  detached calendar icon beside Today, Upcoming and Past. The control adapts on
  narrow phones, calendar-to-agenda spacing is reduced, and booking and request
  results render as lists rather than repeated cards.
- Clients also uses a divider-led list. Tools groups Money, Tasks and Notes in
  the same shared row language as Home, without the previous nested border.
- Shared navigation, segmented controls, buttons and selected states use softer
  corner geometry. List-row defaults and explicit legacy call sites provide a
  consistent 18-point horizontal inset so icons no longer touch card edges.
- Verification passes formatting across 208 Dart files, clean analysis,
  347/347 Flutter tests, 25/25 Deno tests and 25/25 protected golden scenarios.
  Fresh profile builds pass for iOS (70.3 MB) and universal Android (156.7 MB).
  The signed candidate was installed and launched on the paired iPhone;
  CoreDevice confirmed the live process as PID 78739. This proves install and
  launch, not a completed interactive or assistive-technology walkthrough.

### 2026-08-08 completion evidence and staging-E2E harness

- Tools now presents Money, Tasks and Notes as one calm, consistent workspace
  group rather than three competing nested colour cards. Module colour is
  limited to useful icon signals; spacing, dividers, typography and tap targets
  follow the shared Workloop surface and list-row system.
- The reviewed visual baseline now includes populated Money, Tasks, Notes,
  booking-request inbox/detail and Profile states. The protected golden suite
  passes 25/25 tests and covers 29 image files in Light/Dark where relevant.
- Three production-safe staging journeys are now implemented: the connected
  client-to-booking-to-work-to-payment/export loop, two-account SDK isolation,
  and signed-out public booking idempotency/owner conversion. They refuse to
  write unless explicit staging credentials and `E2E_ALLOW_WRITES=true` are
  supplied; the runner also rejects the production project URL.
- The complete local suite passes formatting, clean Flutter analysis, 346/346
  Flutter tests, 25/25 Deno tests and deterministic data profiles. The iOS
  simulator launch/Auth journey passes; all three staging journeys compile and
  are safely skipped without staging configuration.
- Fresh profile builds pass for iOS (70.2 MB) and universal Android (156.6 MB).
  The exact iOS profile candidate was subsequently installed and launched on
  the paired iPhone over wireless deployment; CoreDevice confirmed its live
  process as PID 78555. Flutter's wireless Dart VM service did not reconnect,
  so this proves install/launch rather than interactive workflow QA.
- Executing the new write-capable journeys remains gated on approval for a
  disposable Supabase branch at the quoted $0.01344/hour plus two disposable
  accounts. Production data will not be used for destructive or isolation QA.

### 2026-08-08 final completion and release-candidate sweep

- The unfinished recurring-series control is no longer exposed in New booking.
  V1 creates one booking at a time until series editing, exception handling and
  series-level conflict recovery can be completed safely. Existing recurrence
  fields, payload support and read-only labels remain compatible so historic
  records are not rewritten or hidden.
- Current verification passes formatting across 205 Dart files, clean Flutter
  analysis, 340/340 Flutter tests, 49.68% line coverage, 19/19 protected golden
  tests covering 23 image files, and the signed-out iOS simulator journey 1/1.
- Edge verification passes formatting and lint, all eight checked entry points,
  and 25/25 Deno tests. The four deterministic data profiles pass in dry-run
  mode. No migration or Edge deployment was changed during this sweep.
- Profile builds pass for iOS (70.7 MB), universal Android (155.6 MB), Android
  arm64 (129.4 MB), and web release (43 MB). The arm64 APK passes 16 KB
  alignment and v2 signature checks; the iOS app passes strict code-signature
  verification.
- The exact iOS candidate installed and launched on the paired iPhone 15 Pro
  Max after an initial locked-device denial. CoreDevice confirmed the running
  process. This proves install/launch, not a completed interactive workflow or
  assistive-technology pass.
- Read-only live Supabase inspection reports an active healthy Postgres 17.6.1
  project. All 23 public and all four private application tables have RLS;
  anonymous application-table grants are zero; private tables have no client
  grants; and `account_deletion_audit` remains the only public table without an
  authenticated client grant. The sole security-advisor warning remains leaked
  password protection. Clean local replay and pgTAP remain unexecuted because
  this machine has no Docker engine.

### 2026-08-07 app-wide uniformity, booking browse and data graphics

- Root workspaces now use one 18-point page inset, 12-point safe-area top
  inset, 20-point header-to-control gap and 24-point major-section rhythm.
  Clients no longer double-applies its horizontal inset, and Clients, Bookings
  and Money no longer place their page headers inside competing tinted cards.
- Every two-to-four option peer control now resolves through the same shared
  navigation renderer. Bookings Today/Upcoming/Past intentionally no longer
  looks like a separate control family from List/Calendar, Tasks, Notes or
  Money.
- Home's Today booking is a horizontal carousel when multiple bookings remain.
  It exposes booking position, a next-card preview, haptic page changes and an
  accessible swipe instruction while preserving direct booking actions.
- Money adds a compact cash-movement strip calculated from paid records in the
  selected period. Bookings intentionally avoids a second schedule summary and
  leads directly into its actionable list or calendar.
- The launch wordmark assets are transparent on one native `#6362EB`
  background, removing the differently rendered purple square while retaining
  the supplied solid-purple app icon.
- Verification passes clean analysis, 337/337 Flutter tests, 17/17 protected
  golden scenarios after visual review, `git diff --check`, a 70.7 MB iOS
  profile build and a 155.6 MB Android profile APK. The exact iOS artifact was
  installed and launched on the paired iPhone 15 Pro Max; CoreDevice confirmed
  launch before its intermittent device tunnel dropped again.

### 2026-08-06 Studio composition and native-brand refinement

- The approved purple Home command panel remains the defining Home moment but
  is materially tighter: greeting utilities adapt at compact widths and large
  text, the daily card uses explicit on-hero contrast roles, and the schedule,
  supporting copy and action have a more compact rhythm.
- Root and retained shell workspaces now share one calculated bottom-clearance
  contract: 72-point dock + 12-point offset + the real device bottom safe area
  + 22 points of breathing room. Home, Clients, Bookings, Tools, Money, Tasks
  and Notes no longer rely on a fixed device-specific padding guess.
- Home's accumulated double section gaps are removed. Bookings has a shorter
  header, a quieter compact time filter, a counted request inbox and an inset
  booking time rail.
- The supplied `W` artwork is now the complete iOS and Android launcher-icon
  set. The supplied `workloop` artwork is the native launch image, with its
  exact `#6362EB` background used on both platforms to avoid a visible seam.
- Verification passes clean analysis, 336/336 Flutter tests, 17/17 protected
  goldens after manual review, the full six-device Light/Dark and 100%/200%
  text matrix, a 70.7 MB iOS profile build and a 155.6 MB Android profile APK.
  The exact iOS build is installed and running on the paired iPhone 15 Pro Max
  with CoreDevice process confirmation.

### 2026-08-06 Workloop Studio complete visual reset

- Workloop Studio supersedes Loopline and the previous lime/graphite identity.
  The active system uses a porcelain `#F6F4EF` Light canvas, midnight
  `#10131E` Dark canvas, confident indigo actions, relationship teal, selective
  module signals and bundled Manrope Variable typography.
- The reset is structural rather than token-only: Home has a deep indigo daily
  command composition; Clients has an integrated relationship/search header;
  Bookings is timeline-led; Money uses outcome cards and a real target arc;
  Tools has expressive live module launchers; Auth and onboarding use the
  operating-loop graphic; Settings and Notifications use calm grouped/list
  hierarchies.
- The root shell is again a floating four-destination dock, but with a compact
  contained active state rather than the previous glass pill or edge bar.
  Shared buttons, fields, lists, headers, navigation rails, sheets, empty
  states, motion, shadows and backdrop drawing now come from one central Studio
  system.
- Notifications remains one chronological list with Today/Earlier anchors and
  no redundant All/Unread sections. Purposeful graphics use native Flutter
  drawing and real or explanatory state; no decorative analytics or invented
  business data were introduced.
- Native startup backgrounds now use Studio indigo and no longer flash the
  retired lime launch artwork. Routes, retained workspaces, native back
  behaviour, draft guards, providers, repositories, Supabase contracts and
  operational workflows are unchanged.
- Verification passes `flutter analyze`, 334/334 Flutter tests, 17/17 golden
  scenarios with 21 manually inspected images, the complete phone/text-scale
  matrix, a 70.7 MB iOS profile build and a 155.5 MB Android profile APK. The
  exact iOS artifact is installed and launched on the paired iPhone 15 Pro Max,
  with the running process confirmed through CoreDevice.

### 2026-08-06 Loopline app-wide UI reset

- Workloop now uses one coherent geometry system across every shared control:
  soft-square functional controls, circular icon utilities, status-only
  capsules, line-led peer navigation and a docked edge-to-edge bottom bar.
- Light has a new mineral `#F4F5F2` canvas, stronger white/neutral layer
  separation and ink primary actions. Dark keeps its established graphite and
  lime personality.
- The floating pill dock, selected navigation plates, pill segmented rails,
  `StadiumBorder`, literal `999` control radii and the legacy pill radius have
  been removed. A source contract prevents them returning.
- Auth is open and wordmark-led, Home uses one restrained real schedule focus,
  Tools uses a flat capture grid, Settings is fully list-led, Client portfolio
  and client workspace navigation share the line system, and public-profile
  sections no longer stack generic cards.
- Existing routes, retained workspaces, native back behaviour, draft guards,
  providers, repositories, Supabase contracts and operational workflows remain
  unchanged.
- Verification is clean: `flutter analyze`, 334/334 Flutter tests, 17/17
  protected golden tests, the complete phone/text-scale matrix,
  `git diff --check`, and the 70.7 MB iOS profile build all pass. The paired
  iPhone is currently reported offline by CoreDevice despite the saved pairing,
  so install and interactive launch remain a separate device-state check.

### 2026-08-06 soft-editorial UI replacement

- The rejected graphite-frame direction has been superseded. Light is now an
  open `#F7F7F4` canvas with white content surfaces, quiet neutral controls,
  crisp ink typography, and no large black structural panels.
- Root and route headers are typographic rather than logo-led, section chrome
  is reduced, and the floating four-destination dock uses a light neutral rail,
  a quiet active surface, visible labels, and a small lime position marker.
- Home, Money, Tools, Auth, onboarding, public profile, filters, empty states,
  forms, notifications, and settings share the softer system. The real daily
  schedule path and onboarding operating loop remain the purposeful graphics;
  no decorative analytics or invented data were added.
- Dark keeps its established lifted graphite palette but replaces harsh inner
  black frames and bright white selected plates with quieter semantic layers.
- Routes, navigation behaviour, state retention, Riverpod providers,
  repositories, Supabase contracts, and durable workflows remain unchanged.
- Verification is clean: `flutter analyze`, 333/333 Flutter tests, 17/17
  protected golden tests with 21 manually reviewed images, the full primary
  and secondary responsive matrices, a 70.7 MB iOS profile build, and a
  155.4 MB Android profile APK. No physical iPhone was connected for this pass.

### 2026-08-05 graphite-frame UI revamp

- Workloop now has a visibly new app-wide interface rather than a token-only
  refinement: a shared graphite frame, lime signal, two-line operating-loop
  mark, editorial header rules, square action geometry, and a cool-chalk Light
  canvas connect the application.
- The floating shell navigation is graphite in both appearances, keeps all four
  destination labels visible, and uses a lime active plate. Peer navigation and
  compact segmented controls follow the same hierarchy without changing any
  destination, route, retained state, or back behaviour.
- Home's real schedule path and Money's real period total use strong graphite
  focus panels. Tools has a dedicated quick-capture command panel. Auth,
  onboarding, public profile, search, empty states, settings, notifications,
  and pushed-route headers share the new graphic language.
- Light uses `#F3F4F0` chalk, `#FCFDF9` content surfaces, stronger neutral
  interaction layers, and the same graphite anchors as Dark. No invented
  charts, analytics, packages, providers, repositories, schema, or workflow
  changes were introduced.
- Verification is clean: `flutter analyze`, 332/332 Flutter tests, 16/16
  protected golden tests with 19 reviewed images, the full primary and
  secondary responsive matrices, a 70.7 MB iOS profile build, and a 155.4 MB
  Android profile APK. The exact iOS artifact installed on the paired iPhone;
  automatic launch was denied only because the phone was locked.

### 2026-08-05 free launch-hardening sweep

- Home now exposes the notification inbox with an unread count, includes real
  pending booking requests in its attention queue, and routes client follow-up
  prompts to the exact client. The retired `pending`/`unconfirmed` appointment
  assumption is gone; active clients without activity for 42 days become calm
  follow-up prompts unless they already have an upcoming booking.
- Home Money, Coming up, Recent activity, and Business settings failures now
  remain honest and retryable. Money date/mode/payment-row interactions use
  labelled 44-point controls, and deleting income is discoverable without a
  hidden long press.
- Business Feed now starts concurrent, date-bounded and row-limited repository
  reads instead of materialising every feature table. The booking look-ahead is
  bounded to 90 days / 80 rows, which is an intentional dense-workspace limit.
- Sign-up, recovery, and in-app password changes share a 12-character minimum.
  This reduces weak-password risk but does not replace Supabase breached-
  password protection.
- Stripe payment-link, Terminal, refund, and webhook retries retain a stable
  operation key. Failed and stale webhook deliveries are reclaimable; completed
  events remain final; refund reconciliation is computed from succeeded rows.
- Live test-mode Supabase now contains migrations
  `20260805210418_harden_stripe_retries_and_private_rls` and
  `20260805210559_document_private_ledger_deny_policies`.
  `stripe-payments` v2 and `stripe-webhook` v2 are active. Client roles have no
  private-ledger DML, the security advisor reports only the paid leaked-password
  warning, and unsigned/unauthenticated smoke requests are rejected.
- Combined evidence: clean formatting and analysis; 324/324 Flutter tests;
  14/14 reviewed goldens; 25/25 Deno tests; 47.15% line coverage; live
  transaction-wrapped 47-assertion schema and 14-assertion tenant-isolation
  scripts; 70.7 MB iOS, 155.0 MB universal Android, and 69.9 MB arm64 Android
  profile builds; APK alignment and signature checks; physical iPhone install
  and CoreDevice launch.
- No live Stripe key, platform fee, Apple proximity-reader entitlement, paid
  Supabase control, store signing, or public legal/support service was enabled.

### 2026-08-05 editorial UI sweep

- Shared typography, spacing, radii, fields, buttons, navigation, surfaces, and
  list rows are denser across the entire app while retaining 44-point minimum
  interaction targets.
- Light now uses a crisp `#F7F7F4` canvas, pure-white surfaces, neutral grey
  hierarchy, and restrained lime. Dark retains its established graphite and
  lime colour personality with the same more compact geometry.
- Notifications are one chronological divider-led list. Unread state uses a
  small lime dot and stronger title weight; redundant All and Unread sections
  are removed.
- Home's daily-focus surface includes a native schedule path based on the real
  current time and remaining booking positions. Existing Money target and
  category visuals remain the purposeful reporting layer; no invented trends
  or analytics were added.
- Tools quick capture is tighter and its Money, Tasks, and Notes destinations
  now use list rhythm instead of three large cards.
- Verification is clean: `flutter analyze`, 325/325 Flutter tests, the 15/15
  golden suite (18 reviewed images), the full responsive appearance matrix, and
  a 70.7 MB iOS profile build all passed. The exact app installed on the paired
  iPhone 15 Pro Max; automatic launch was denied because the development profile
  is not currently trusted on the device, so interactive phone review remains
  open.

### 2026-08-05 final visual-system acceptance pass

- The final route inventory covered authentication, recovery, onboarding,
  Home, Clients, Bookings, Money, Tasks, Notes, Tools, Business Feed,
  Notifications, Profile, Settings, calendar/import tools, legal/support,
  public profile, booking requests, and the main create/edit flows.
- Page-level content, onboarding steps, secondary workspaces, public surfaces,
  and modal forms now share the canonical 18-point horizontal grid. Existing
  routes, repositories, providers, Supabase contracts, retained state, and
  draft safeguards are unchanged.
- Feature selection, keyboard, calendar, client workspace, progress, sheet
  cleanup, and expand/collapse animations now honour reduced-motion settings.
  A source contract prevents raw feature colours, weights above 600, and
  unguarded canonical motion durations from reappearing.
- Onboarding now contains one restrained Flutter-native operating-loop visual:
  Client to Booking to Work to Payment to Repeat. It is orientation, not
  analytics, and remains semantic and scrollable at 200% text.
- Final evidence: clean analysis; 331/331 Flutter tests; 16/16 golden tests with
  19 reviewed images; the six-device primary responsive matrix plus an
  18-combination secondary-route Light/Dark, 200%-text, reduced-motion matrix;
  70.7 MB iOS and 129.4 MB Android profile builds; exact iOS artifact installed
  and launched on the unlocked paired iPhone 15 Pro Max with the Workloop
  process confirmed running.
- Manual VoiceOver/TalkBack traversal, a physical Android run, authenticated
  staging journeys, and store-distribution signing remain release QA rather
  than visual-system implementation gaps.

### 2026-07-31 appearance and Tools workflow pass

- Workloop supports persisted System, Light, and Dark appearances from a
  dedicated Settings destination. System follows the phone; manual choices
  apply immediately and survive relaunch.
- Light uses a low-glare warm-stone `#EEEDE8` canvas, ivory content surfaces,
  neutral grey interaction layers, dark operational text, and the exact
  `#C1FF72` neon only for confident fills and selected states. Accent-filled
  controls have a quiet one-pixel sage edge; neutral cards stay neutral. Dark
  retains the existing lifted graphite palette.
- Legacy screen colours now resolve through the effective appearance while
  current shared components continue to use semantic tokens. Native iOS and
  Android startup configuration no longer forces Dark when the system is Light.
- Tools now leads with Record money, New task, and New note capture actions.
  These open the existing canonical creation flows directly, while the three
  workspace rows retain equal hierarchy and add live money/task/note context.
- Theme tests protect text, status, module-icon, focus, button, navigation, and
  disabled-state contrast in both appearances. The responsive launch matrix
  now renders Light and Dark across six phone sizes and two text scales.

### 2026-07-30 visual hierarchy and daily-focus pass

- Root workspaces now separate three attention levels: one semantic primary
  create action, one contextual focus area where the feature needs it, and
  quieter filters/content. Clients, Bookings, Money, Tasks, and Notes use a
  visible `+` with a feature-specific accessibility label.
- Home now leads with a state-driven daily-focus surface for an in-progress
  booking, the next booking today, or a clear day. The greeting is quieter,
  the focus action is explicit, and in-progress bookings remain visible until
  their end time.
- Dashboard attention uses the existing actionable copy and prioritises an
  imminent unconfirmed booking, then overdue work, overdue payment follow-up,
  and stale leads. Task and note shortcuts show live counts when available.
- Bookings is schedule-first. Today/Upcoming/Past/Calendar use one quiet
  graphite navigation rail, while the counted request inbox opens the
  dedicated triage workspace. Client, task, note, and other filter states use
  the same subordinate hierarchy.
- Shared section headings now form visible sentence-case divisions; dense
  chronological groups use a quiet variant. Empty states are inline by default
  so whitespace and typography carry hierarchy without another bordered card.
- Booking completion/cancellation decisions sit directly below the booking
  hero and time context rather than after every disclosure. Public profiles
  expose a prominent booking-request action beside the business proposition.
- Tools replaces the generic More label and presents Money, Tasks, and Notes as
  three equal full-width workspace rows. Profile and Settings move to compact
  direct controls beside the Home greeting.
- Root empty states no longer repeat the same neon create action already
  present in the header. Imports remain available as quiet secondary paths.
- Bookings keeps Today/Upcoming/Past/Calendar in one compact rail. Requests use
  a counted header inbox rather than consuming a full-width workspace decision.
- Pushed detail, editor, import, support, legal, calendar, task, note, client,
  booking, income, and expense screens now share `WorkloopRouteHeader`.
- Settings makes the identity surface the Account destination, Profile removes
  duplicated snapshot links, Booking Requests uses Active/New/Closed, and
  import screens use one route title instead of competing headlines.

### Final application foundation

- Workloop ships coordinated System, Light, and Dark appearances. Dark uses the
  lifted `#151A16` graphite canvas; Light uses cool `#F3F4F0` chalk. The
  exact icon and launch-artwork neon `#C1FF72` remains the restrained brand
  accent, with dark `#17200D` content on neon fills and tested contrast pairs.
- Instrument Sans is bundled with its licence so launch typography does not
  depend on a runtime font download. The app-wide weight scale is capped at
  semibold, with regular-weight body copy for a calmer, more minimal hierarchy.
- A shared, restrained textured backdrop now connects the main application, onboarding, profile, settings, support, calendar tools, notifications, and import flows.
- Shared fields, search, pickers, sheets, dialogs, buttons, switches, haptics, motion, loading, empty, error, and success states form the canonical interaction system.
- A resumable onboarding preferences step, real-record dashboard setup checklist, and action-led empty states guide first value without inserting demo data.
- Privacy-first import supports selected contacts, one-time calendar events, client CSV, task text, and note text/Markdown. Partial attempts retain only failed records for retry so already-created records are not duplicated. Unsupported private stores are labelled honestly.
- In-app notifications and on-device task/booking reminders are supported on
  iOS and Android. Task reminders follow the selected timing; opted-in booking
  reminders are scheduled about 15 minutes before the booking. Tapping a
  reminder routes back into Workloop. Build 6 additionally provides optional
  privacy-safe business-activity push on iOS through APNs; Android remote push
  delivery is not yet claimed.
- See `docs/LaunchReadiness.md` for the current release gate. `docs/FinalPolishAudit.md` remains a historical snapshot of the earlier July polish pass.

### 2026-07-28 final UI/UX refinement

- The four-destination shell remains Home, Clients, Bookings, and Tools. Root
  screens keep one measured header grid, while pushed Profile, Settings, and
  Notifications routes now use one responsive route-header primitive.
- Bookings now opens directly into the schedule, separates display controls
  (List and Calendar) from time filters, and exposes Booking Requests through
  a compact counted inbox action. The next booking is not repeated in list
  mode, and failed schedule/request loads offer a specific retry in their
  respective workspaces.
- Booking creation and request conversion retain entered context through
  recoverable failures. Public requests use persistent labels and inline
  validation; conversion keeps its sheet and draft open, checks conflicts and
  working hours, and reports the exact recovery action. Booking-to-client
  navigation resolves the canonical client instead of constructing a partial
  record.
- Money renders each operating section from its own provider state, so a
  target, invoice, or expense failure does not hide unrelated financial
  information. Tasks, Business Feed, Notifications, deletion, onboarding
  handle checks, and calendar import now expose bounded retry paths.
- Calendar imports use the same validated, atomic, idempotent booking workflow
  as manual creation. Failed events remain selected with their exact reason.
- Bottom navigation and Tools launchers expose invokable semantic actions;
  checklist controls keep a compact appearance with 44-point targets; success
  and error feedback use live regions where appropriate; reduced-motion and
  large-text layouts are protected by responsive tests.
- Final local UI evidence: formatting is clean, Flutter analysis reports no
  issues, all 285 Flutter tests pass, the 11-test golden suite passes in
  non-update mode, iOS and Android profile artifacts compile, and the current
  iOS profile launched on the physical iPhone with a Dart VM Service and a
  confirmed running process. Manual VoiceOver, TalkBack, permission, offline,
  lifecycle, and physical Android coverage remain launch gates.

### 2026-07-28 dark-only usability and edge-case pass

- System and Light appearance selection, persisted theme preference logic, and
  the Settings appearance destination were removed. Native iOS and Android
  launch windows now use the same graphite background, preventing a white
  startup flash before Flutter paints.
- The responsive matrix now renders 11 launch surfaces across six phone
  viewports and two text scales: 132 combinations plus keyboard reachability.
  Settings and the booking-request inbox are included.
- A booking-request empty state that overflowed by 337 logical pixels on a
  320x568 phone at 200% text now scrolls and remains centred when space allows.
- Dark-only theme contracts, native startup colour, Settings ownership, and
  feature-action geometry are protected by targeted regression tests.
- The focused usability suite passes 86/86 tests, the full Flutter suite passes
  280/280, formatting and static analysis are clean, and iOS/Android profile
  builds pass. The signed-out simulator integration journey passes and the
  physical iPhone profile exposed a Dart VM Service with a confirmed running
  process.

### Auth

- Email/password sign up.
- Email/password sign in.
- Sign out.
- Password update from settings.
- Password recovery through the `workloop://reset-password` deep link, subject to the production Supabase redirect and email-delivery configuration.
- Session-based auth gate.
- Workspace gate.

### Onboarding

- Multi-step onboarding.
- Captures business profile basics.
- Persists the owner's preferred first name in Supabase Auth metadata for personalised app greetings.
- Captures public handle.
- Captures services.
- Captures working hours, including split working blocks with breaks.
- Captures monthly revenue target, used as weekly finance target.
- Optional first booking.
- Creates workspace, member, settings, business profile, services, and first booking.

### Navigation

- GoRouter top-level routes.
- Main shell with a docked four-item bottom system bar: Home, Clients,
  Bookings, Tools.
- Tools presents Money, Tasks, and Notes as equal, full-width operating
  workspaces with live orientation text, plus direct Record money, New task,
  and New note capture. Profile and Settings are direct secondary controls in
  the Home header rather than content sections in the daily dashboard.
- Clients, Bookings, Money, Tasks, and Notes expose the same circular `+`
  create action in each feature header, with the specific action retained as
  its accessibility label. Money opens a two-choice sheet for income or expense
  instead of mixing unrelated controls.
- Shell headers share one safe-area top grid, header type treatment, 24-point
  header-to-content rhythm, and bottom-navigation clearance.
- Tasks, Notes, Work/Bookings, and Payments routes can deep-link to their shell
  screens while Tools remains the active navigation destination for secondary
  modules.
- Business Feed route opens from Home without adding a bottom navigation tab.
- Tapping outside an active text field dismisses the keyboard consistently across every route while taps within the field keep editing active.
- Tapping the native iOS status bar or the app's top edge returns the visible
  vertical screen to its beginning. Every vertical scroll view is discovered
  centrally, including implicit and nested controllers. Render visibility and
  hit testing exclude hidden PageView/TabBarView children. One tap across the
  non-interactive top/header zone resets every visible vertical layer with a
  distance-aware animation while leaving header buttons to perform only their
  own actions. Home, Clients, Bookings, Money, Tasks, Notes, and Tools retain
  independent scroll targets rather than resetting an offstage tab.
- Clean pushed routes retain native iOS interactive back swipes and Android
  system back gestures, including finger-tracked reveal and cancellation. A
  route-aware fallback is reserved for direct routes and draft-protected
  editors; it acts only after pointer-up and still invokes the same
  Save/Discard/Keep editing decision. Reminder navigation pushes onto the
  current history instead of replacing it.
- Money, Tasks, and Notes also retain the shell workspace that launched them.
  Their iOS back swipe now moves with the finger, reveals that workspace with
  Cupertino-style parallax, and can be cancelled before returning—normally to
  Tools, or Home when Money was opened from a Home follow-up.
- Every programmatic shell destination change now uses the same restrained
  240ms fade-through and directional offset. This covers Home, Clients,
  Bookings, Tools, and forward entry into Money, Tasks, and Notes while
  preserving each destination's mounted state and scroll position. Reduced
  motion switches immediately. Retained destinations keep a stable keyed layer
  through every animation phase, and Tools create requests are cleared after
  their first delivery so Money, Task, or Note creation cannot replay later.
- Clients gives the top shortcut precedence over a tappable client row occupying
  the top zone after scrolling. Filter changes remain explicit through the
  visible filter rail rather than a competing full-screen horizontal gesture.

### Dashboard

- Calm daily overview ordered around Today, Worth a look, Money, quick access,
  Coming up, and Recent activity.
- Today is the single focal surface. It distinguishes an in-progress booking,
  the next booking, and a clear day, then exposes one explicit action.
- Time-aware personalised greeting includes the current date.
- Today keeps an in-progress booking visible until its end time and adds a quiet
  count of later bookings; Coming up excludes today and is capped at three rows.
- Worth a look is optional, capped at two rows, and keeps direct action-led copy
  without alarm-heavy colour.
- Money is a compact received-this-month row rather than a dominant hero card.
- Tasks and Notes use two small, low-contrast utility cards with live counts so
  they read separately from Money without adding visual noise.
- Recent activity is capped at three calm items and excludes attention/overdue/unpaid warning states.
- Dashboard rows and section actions open the related booking detail or owning feature.
- Pull-to-refresh.
- Navigation callbacks into core modules.

### Business Feed

- Computed feed generated from existing bookings, clients, payments, expenses, tasks, notes, booking requests, and weekly target progress.
- Feed item types include today's bookings, upcoming bookings, payment received, unpaid/overdue invoices, expenses, due/overdue tasks, notes, client follow-ups, booking requests, quiet-day detection, daily summary, and weekly target progress.
- Home preview appears inside Daily Command with a View all action.
- Full Business Feed screen includes All, Needs attention, Money, Bookings, Tasks, and Clients filters.
- Feed row taps route to the most useful existing module or booking request screen where exact detail routes do not yet exist.
- No persisted feed table or AI dependency has been introduced.

### Clients / CRM

- Calm, whitespace-first client list aligned with the dashboard's title scale, top spacing, paper-like backdrop, text hierarchy, and continuous divider-led rows.
- Client sorting supports Next booking, A–Z, Recently booked, Recently added, and Most booked without additional database queries.
- Client sorting is presented as a compact single-line choice menu with a quiet selected state rather than a second list of full record-style rows.
- Search across client names, contact details, and tags, with line-led
  All/Active/Leads/Inactive views that can be changed by tapping or dragging
  across the selector.
- Active and Inactive remain distinct status views; inactive contacts also carry a quiet neutral label inside All.
- Changing client views returns the portfolio to the top, and each empty category has calm, contextual guidance.
- Add and Edit client use one canonical form with the dashboard/client textured shell, shared field styling, and identical Contact information, Client settings, Booking address, Client notes, and Additional information sections.
- The shared Booking address field supports debounced UK Google Places autocomplete through an authenticated Supabase Edge Function, suggestions that remain visible while the surrounding form is repositioned, and an independently scrollable and explicitly dismissible result list. It deliberately stays as one field: users start with the first line of an address for suggestions, or keep any manually typed value such as a postcode. Building-level matches preserve typed flat/unit labels, selection remains immediate with manual fallback, and the Google key stays out of the mobile app.
- Saved client booking addresses open driving directions in Apple Maps or Google Maps. Users can choose per launch, remember a choice from the directions sheet, or change the device-level default under App settings.
- Client entry validates optional email addresses, explains relationship statuses, warns when the selected contact channel has no matching detail, and blocks duplicate phone/email records before saving.
- Lead source, tags, and birthday remain progressively disclosed; destructive deletion stays separate from Save, and backing out of an edited client offers to preserve or discard the draft.
- Delete client with confirmation.
- Client workspace with a compact relationship header, call/email actions, textured backdrop, and draggable Overview/Bookings/Money/Tasks navigation aligned with the app shell.
- Notes and important notes.
- Status/source/tags/birthday/preferred contact method fields.
- Client overview prioritises the next booking, a restrained relationship snapshot, calm follow-up rows, useful context, and three recent activities rather than repeating full module histories.
- Client booking history is repository-backed, opens canonical booking details, and creates bookings with the client preselected.
- Client payment history is repository-backed, supports direct recording/editing, and distinguishes received, remaining, paid, part-paid, and unpaid amounts without alarm styling.
- Client task history uses the shared task repository and contact relationship, invalidates the main Tasks state, and links directly to the full Tasks workspace.

### Bookings

- User-facing Bookings built on `appointments`.
- Calm schedule-first workspace using the same textured backdrop, typography,
  spacing, controls, and feature-header action as Home and Clients. A counted
  inbox opens the dedicated Booking Requests workspace.
- List mode with Today / Upcoming / Past views and direct booking rows.
- Calendar mode uses an open Apple-inspired month grid with swipe and button
  navigation, a Today shortcut, clear selected/today circles, booking-density
  dots, and a selected-day time-rail agenda. Adding from the agenda continues
  to hand the selected date into the canonical New booking flow.
- Add and inline Edit booking forms share the client form visual language, keyboard dismissal, calm input surfaces, and progressive booking sections.
- Change date/time/duration/service/price/client/location/notes/status.
- Business/client/online location choices; physical locations use the shared Google Places address search and can reuse the selected client's saved booking address.
- Saved physical booking locations open directions using the shared Apple Maps / Google Maps device preference.
- Booking creation is routed through an authenticated, atomic, idempotent workflow that validates workspace relationships, serialises conflict checks, and can create an inline client, a linked payment, a follow-up task, request status, and in-app notification without exposing a partially-created workflow. Recurrence payload compatibility remains in the data layer, but series creation is not exposed in the V1 UI.
- Booking completion and its linked payment/notification handling use a separate atomic, idempotent workflow.
- Inline client creation in new booking.
- Custom service name, duration, and price.
- Working-hours exceptions show a calm confirmation and remain bookable by choice; real appointment conflicts remain blocked.
- New and edited clients and bookings protect changed drafts with Save, Discard, and Keep editing choices before leaving.
- Linked tasks in booking detail.
- Booking status controls: scheduled, completed, cancelled/no-show style workflows.
- Explicit calendar-event import and a point-in-time `.ics` file export. Workloop does not represent this as live or two-way calendar sync.
- Dashboard and client booking rows continue to open the canonical booking detail; booking detail links back to the canonical client workspace and shared Money and Tasks records.

### Tasks

- Calm Now/Later/Done workspace with Overdue, Today, Anytime, and future sections.
- Task rows open a dedicated detail screen while preserving deliberate completion actions.
- Add and Edit task use a full-screen form aligned with Client and Booking creation, including progressive options and Save/Discard/Keep editing protection.
- Delete task.
- Reopen task.
- Deliberate completion.
- Priority.
- Due date shortcuts/custom date.
- Reminder timing.
- Client and booking linking.
- Quick task templates.
- New task and initial checklist creation is one authenticated, atomic, idempotent workflow.
- Checklist item creation, editing, toggling, deletion.
- Real on-device reminders with permission-aware validation and safe reconciliation on app resume.
- Client task rows no longer complete instantly.

### Notes

- Calm searchable notes workspace with All, Pinned, Clients, and Bookings filters.
- Full-screen note editor aligned with the shared textured app shell and page hierarchy.
- First line acts as the note title while the remaining text supports paragraphs, checklists, and bullets.
- Pin remains a visible editor action; delete sits behind a secondary actions menu and retains confirmation.
- Compact labelled checklist and bullet controls remain available above the keyboard and preserve layout stability.

### Profile

- Business profile is a dedicated business-identity overview instead of an alias for the Business settings tab.
- The identity area stays business-focused and uses the shared textured workspace shell and Workloop typography. Personal account controls live only in Settings.
- Business details, Services, and Working hours use dedicated Profile-owned screens while reusing the established repositories and save logic.
- Public link setup, preview, sharing, readiness and booking-request access now live in the separate Booking page hub so owner identity and customer acquisition are not mixed together.
- Booking requests retain one canonical compact, filterable inbox. Each request opens a focused detail screen for calling, marking contacted, declining, or converting into a booking.
- Settings is intentionally separate and contains Account, Notifications, and
  App preferences. Appearance is a dedicated Settings destination rather than
  being mixed into general app connections.

### Money

- User-facing Money built partly on `invoices`.
- Calm three-section Money workspace aligned with Home, Clients, and Bookings: plain-language Made / Spent / Owed navigation, one primary figure per section, period controls for Made and Spent, period-aware target progress, category summaries, and one divider-led owed list.
- Compact top actions create income or expense entries without a floating action button.
- Record payment.
- Edit payment.
- Mark payment as received.
- Delete payment.
- Paid/unpaid tracking.
- Overdue refresh logic.
- Add expense.
- Edit expense.
- Delete expense.
- Expense category summary.
- Week/month/custom period switcher.
- Weekly target progress.
- Weekly/monthly target editing from Money.
- Comparisons vs last week/month/custom period foundation.
- Paid/unpaid/expenses/profit summary.
- Booking-linked payment rows through `appointment_id`.
- Supabase-backed `expenses` table with RLS.
- Add/Edit Income and Add/Edit Expense use the same Money form sections, amount field, picker treatment, date rows, page hierarchy, keyboard behaviour, and Save/Discard/Keep editing protection.

### Public Business Profile

- Owner preview route `/p/:handle`; the deployed customer route is `https://workloop.uk/:handle` once custom-domain SSL is active.
- Business info.
- Services.
- Working hours.
- Notice banner.
- Request-booking form.
- The customer page is a request experience, not instant slot booking. It asks for a real preferred date/time and repeatedly explains that the owner must confirm.
- Public request creation through the bounded `create-booking-request` Edge
  Function; anonymous clients do not write the table directly.
- The request path uses a stable client request token, bounded server validation, a honeypot, source/phone rate limits, profile/service ownership checks, and a server-created owner notification. Manual entry remains available if public booking is unavailable.

### Booking Requests

- In-app booking request triage.
- Status update.
- Manual confirmation flow that checks/edits client, phone, service, date, time, duration, price, location, private notes, and optional payment due before atomically creating the booking and updating the request.
- Decline confirmation before closing a request.
- Notification creation on request/confirmation paths.

### Notifications

- Notification centre.
- Read/unread state.
- Mark read/all read.
- Preferences screen.
- App-side notification records for selected events.
- On-device task and booking reminders with tap-through navigation.
- Push token table exists for future push delivery.

### Settings

- Calm Settings overview with account identity and dedicated Account,
  Notifications, and App preferences destinations.
- System, Light, and Dark appearance choice is stored locally and applied at
  the app boundary; no workspace schema or account data is involved.
- App preferences is reserved for maps, calendar, and Workloop information.
- Account owns preferred name, email, password, workspace export, account deletion request, and sign out.
- Notifications owns booking, payment, task, follow-up, digest, summary, and quiet-time preferences.
- App preferences owns the default maps choice, calendar connection entry point, and concise build information.
- Business details, services, and working hours remain in Business profile. Public link setup and booking requests live in Booking page. Neither is duplicated in Settings.
- Legacy tab navigation, nested settings cards, unfinished payment placeholders, and duplicate feature-directory links have been removed.

### Security / Foundation

- `.env`-based Supabase config.
- `.env.example`.
- RLS policy contract.
- Live RLS enabled on current public tables.
- Public profile and booking request access routed through Edge Functions.
- Account deletion request/completion Edge Functions exist; completion remains admin-token gated.
- Request and completion source independently require the requester to be the workspace's sole member before destructive deletion can proceed.
- Authenticated task and booking workflow RPCs use bounded public wrappers, private tenant-validating implementations, and per-user/workspace idempotency records.
- Public booking and Places Edge Function paths use private rate-limit state; direct anonymous table grants remain removed.
- Six launch migrations are live: `20260726000048`, `20260726000057`,
  `20260726000102`, `20260726000110`, `20260726000118`, and the explicit
  client-deny policy `20260726000520`. Current Edge deployments are
  `create-booking-request` v8, `places-address-search` v8,
  `get-public-profile` v6, `request-account-deletion` v6, and
  `complete-account-deletion` v9; structural, grant, and advisor smoke checks
  passed.
- The audit candidate additionally contains migration `20260726005736` and
  updated booking-request Edge source. Production was not changed during this
  audit; clean replay and isolated staging validation are required before
  promotion.
- Schema contract.
- GitHub remote connected.
- iOS launch scope is iPhone portrait on iOS 15+; Android is portrait with minimum API 26 and target/compile API 36. Tap to Pay has stricter runtime device requirements.
- CI is defined for Flutter 3.44.8 formatting, analysis, tests, Deno formatting/type checks/tests, Android profile and web builds, plus a separate unsigned iOS profile build on macOS. Android uses Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20, and Java 17.
- Model serialization tests.
- `flutter analyze` clean at latest verification.
- `flutter test --dart-define-from-file=.env` passing at latest verification.

### 2026-07-26 comprehensive-audit candidate evidence

- Dart formatting checked 186 files with no changes; `flutter analyze` reported
  no issues; all 249 Flutter tests passed in approximately 33 seconds with
  40.10% line coverage.
- Eleven launch-golden tests produced 13 reviewed images and passed again
  without updating expectations. The responsive harness passed 108 phone/text-scale
  renders plus keyboard safety.
- All 19 Edge Function unit tests passed, with Deno formatting, lint, and six
  entry-point type checks clean.
- OSV-Scanner 2.4.0 found no known issue in 132 resolved Dart packages. Deno
  and CocoaPods lock formats were unsupported by that scanner; six direct
  Flutter packages are behind latest and were reviewed without blind upgrades.
- Signed-out Auth/navigation integration passed on an iPhone 17 Pro simulator.
  iOS simulator debug plus unsigned device profile/release compilation passed,
  and the `workloop://` recovery scheme is registered.
- The current 34.8 MB profile installed and launched on the physical iPhone;
  the launch command completed successfully and the Workloop process was
  confirmed running through CoreDevice.
- Android debug/profile compilation passed with package
  `com.ismaeel.workloop`, minimum API 26, target/compile API 36, and portrait
  activity. The profile APK passed `zipalign -c -P 16 -v 4` and signature
  verification.
- The web release build passed. Android App Bundle release signing fails closed
  until the production upload keystore is supplied; no debug-signing fallback
  exists. iOS App Store export remains blocked by missing Distribution signing.
- Clean database replay, all 43 pgTAP assertions, authenticated/two-account
  staging E2E, public booking conversion, deletion completion, measured
  performance/load, physical Android, and full assistive-technology QA remain
  open. The evidence-based verdict is not public-launch ready.

## Partially Completed Features

- Money-to-booking workflow: new bookings and completed bookings use atomic linked-payment workflows; production-like end-to-end and real-device QA is still needed.
- Calendar integration: explicit event import and point-in-time `.ics` export exist; real external provider sync does not.
- Notifications: in-app centre/preferences and on-device task/booking reminders
  exist on iOS and Android. Optional business-activity APNs delivery is live for
  the iOS Build 6 beta; Android remote delivery and the full iOS lifecycle
  matrix remain incomplete.
- Recurring bookings: series creation is intentionally hidden from V1 until
  create/edit scope, exceptions and series-level conflict recovery can be
  completed. Existing recurrence data remains readable and compatible.
- Public profile: request-booking MVP exists; full slot-selection/self-booking/pay-now is not complete.
- Privacy: export and sole-owner-guarded account deletion request/completion are deployed; the production secret, destructive disposable-account test, and operational SLA still require release evidence.
- Security: RLS enabled, public profile/request tables are no longer directly
  public, and the security advisor now reports only the leaked-password
  protection warning. Low-traffic unused-index notices belong to the separate
  performance advisor.
- Typed models: main models exist; some features still pass raw maps.
- Navigation: GoRouter exists, but many flows still use `MaterialPageRoute`.
- Testing: 331 Flutter tests, 25 Deno tests, responsive/golden suites, a
  signed-out iOS integration smoke, database contracts, and generator/load
  harnesses exist; dynamic database, authenticated staging, repository-fake,
  load, and physical-device coverage is still thinner than the launch risk
  warrants.

## Planned Features

Near-term:

- QA Money daily-use workflow across real device and simulator.
- QA Money-to-Bookings across new booking, completed booking, paid/unpaid, and dashboard refresh.
- QA booking request confirmation on real device.
- Monitor Supabase advisors and enable leaked password protection before beta.
- Continue splitting oversized files.

V1 before beta:

- Production validation of on-device reminder behaviour across permission, reboot, timezone, daylight-saving, and notification-tap states.
- Optional remote push foundation only after APNs/FCM can be operated reliably.
- Calendar sync hardening.
- Data export/delete operational hardening.
- More robust QA around onboarding, auth, bookings, money, tasks, public profile.

Post-V1 / V2:

- Stripe payment collection is deployed in test mode: Connect uses direct
  merchant charges, the connected-account webhook and authenticated payment
  API are active, database/RLS tests pass, platform fees are disabled, and
  live keys remain blocked. Test connected-account onboarding, simulated and
  physical payment/refund QA, Apple entitlements, and explicit live-mode
  approval remain. Deposits remain future scope.
- Full public slot-selection booking engine.
- Reviews system.
- Intake forms.
- QR code export.
- Closure dates.
- Advanced analytics.
- Teams/staff.
- Marketplace/discovery only if product direction changes.

## Technical Debt

- UI system: the canonical `Workloop*` primitives now cover headers, metrics, rows, filters, segmented controls, empty states, buttons, bottom navigation, fields, search, sheets, dialogs, pickers, haptics, motion, texture, and theme semantics. System/Light/Dark modes are enabled. Some large legacy screens still mix shared primitives with local layout containers and should be migrated gradually when those screens next change.
- Large files:
  - `lib/features/tasks/tasks_screen.dart` ~946 lines after extracting task card, task logic, task detail, and task editor parts.
  - `lib/features/tasks/task_logic.dart` ~280 lines.
  - `lib/features/tasks/task_card.dart` ~259 lines.
  - `lib/features/tasks/task_detail_widgets.dart` ~320 lines.
  - `lib/features/tasks/task_editor_widgets.dart` ~497 lines.
  - `lib/features/appointments/add_appointment_screen.dart` ~1200 lines after extracting appointment logic and reusable booking form widgets.
  - `lib/features/appointments/add_appointment_logic.dart` ~45 lines.
  - `lib/features/appointments/add_appointment_widgets.dart` ~328 lines.
  - `lib/features/appointments/appointment_detail_screen.dart` ~1217 lines after extracting private detail sections and time picker.
  - `lib/features/appointments/appointment_detail_sections.dart` ~375 lines.
  - `lib/features/settings/widgets/settings_business_tab.dart` ~1215 lines.
  - `lib/features/finance/finance_screen.dart` ~1087 lines after extracting target/activity widgets.
  - `lib/features/finance/finance_screen_widgets.dart` ~394 lines.
  - `lib/features/clients/client_detail_screen.dart` ~1061 lines.
- Mixed routing approach.
- Raw map payloads still used in several areas.
- Some legacy product/code names remain.
- Supabase security advisor was cleared by the 2026-08-11 Auth/database
  hardening. Separate performance-advisor output still includes expected
  low-traffic unused-index notices.
- CI has not yet accumulated hosted-run history for this launch branch.
- `device_calendar` and `flutter_local_notifications` still use CocoaPods on
  iOS. Flutter 3.44 supports this hybrid build, but their Swift Package Manager
  support must be revisited before a future Flutter release makes it mandatory.
- No repository tests with mocked Supabase.
- Limited widget/integration tests.
- No crash/error reporting.
- No environment separation docs beyond `.env`.

## Priority Queue

1. Complete signed-out abuse, authenticated workflow, and destructive disposable-account end-to-end tests against the deployed Edge Functions and migrations.
2. Prove fresh external signup/confirmation/recovery/password-change and
   existing-email OAuth linking; verify the deletion secret and Google Places
   key restrictions without exposing either value.
3. QA booking/payment, task/reminder, public-request, import-retry, export, and deletion loops on a physical Android device and finish the accessibility/device matrix.
4. Publish the legal/support web surface, complete iOS/Android distribution signing, and finish both store declarations.
5. Preserve the release candidate in a reviewed clean commit/tag and run the
   provenance preflight before any signed store artifact.
6. Add repository fakes, end-to-end flow coverage, and production crash/error reporting.
7. Continue refactoring the largest files only in small behaviour-preserving slices.

## Current Risk Level

Product risk: medium-low. The core loop is coherent.

Architecture risk: medium. The app is improving but several screens remain large.

Security risk: medium before production. RLS/public boundaries and Auth
controls are stronger, but clean replay, two-account dynamic isolation,
production-secret verification and live deletion/abuse-control evidence remain
release gates.

UX risk: medium-low in source, with physical-device accessibility, text-scale, compact-phone, permission, error, and Android coverage still required before launch.

### 2026-08-10 booking-page ownership and live-web verification

- Home now keeps Notifications as its sole utility. Tools owns Booking page,
  Business profile, and Settings beneath the existing Money, Tasks and Notes
  workflows.
- Booking page is an owner workflow with readiness, request state, preview,
  copy/share actions, editing entry points, and the canonical request inbox.
  Business profile is limited to business details, services and working hours.
- The public Workloop website now renders real `/:handle` customer pages and
  proxies requests to the existing bounded Supabase Edge Function. Privacy,
  terms and deletion pages are public. A safe live honeypot submission returned
  the expected 202 response without inserting a request.
- `workloop.app` and `www.workloop.app` are attached to the managed deployment
  but remain pending DNS and SSL validation; the temporary public deployment
  URL is operational.
- Dart formatting is clean across 206 files, Flutter analysis reports no
  issues, all 349 Flutter tests pass, and the iOS profile build succeeds at
  71.0 MB.
- That exact iOS profile build installed and launched on the paired physical
  iPhone. Install/launch remains distinct from a signed manual workflow and
  accessibility pass.

### 2026-08-11 atomic appearance switching

- Manual Light/Dark changes now resolve the compatibility palette before the
  app tree builds, so legacy colours cannot trail the active semantic theme by
  one frame.
- System appearance changes rebuild the app boundary and use the current
  platform brightness through the same atomic path.
- Settings identity and row-icon surfaces now read semantic theme tokens
  directly. A widget regression switches appearance and verifies both surfaces
  after exactly one frame.
- Flutter analysis is clean, all 355 Flutter tests pass, and the signed iOS
  profile build succeeds at 71.0 MB.
- That exact profile build installed and launched on the paired physical iPhone;
  CoreDevice confirmed the running `Runner` process. Human rapid-toggle review
  remains the final perceptual check.

### 2026-08-11 beta interface uniformity sweep

- Work is now one retained command workspace. Its title, description, request
  inbox and create action stay mounted while Schedule, Tasks and Notes change
  below them; each view retains its own content state.
- Primary screens share the same feature-header geometry and 46-point circular
  create action. Root and peer navigation now use a quieter neutral surface and
  a two-pixel indigo active line instead of large filled selection blocks.
- Money uses the same neutral/indigo semantic palette as the rest of Workloop.
  Business setup rows no longer assign unrelated colours to Services, Working
  hours and Business profile.
- Flutter analysis is clean, all 359 Flutter tests pass, and 27 protected launch
  goldens pass after visual review. An unsigned 70.8 MB iOS profile artifact
  builds successfully. A temporary QA copy using the existing development
  profile installed and launched on the paired iPhone as PID 90668.
- Xcode now has the Apple Developer account and regenerated signing assets. A
  signed profile build succeeds, and the App Store export produces a 34.3 MB
  `Workloop.ipa` with `beta-reports-active=true` and `get-task-allow=false`.

### 2026-08-11 Stripe beta-readiness pass

- Payment collection now offers system sharing and copy fallback for secure
  links, optional Stripe email receipts for contactless payments, completed
  receipt access, explicit processing/refund states, and keyboard-safe scrolling.
- Stripe Terminal 5.7 is installed on iOS and Android. The authenticated
  `stripe-payments` Edge Function is active as v8; live mode is enabled after a
  supervised secret cutover. Connected-account creation and hosted onboarding
  now use Stripe Accounts v2 with the Merchant configuration, full Dashboard
  access and Stripe-owned fee/loss responsibility, matching the live platform
  setup. Stripe platform-configuration failures are mapped
  to a stable public error and the Flutter sheet now uses the standard inline
  error state instead of exposing backend exception details or dashboard URLs.
- Apple Sign in is enabled on the Workloop App ID. The Tap to Pay entitlement
  request was submitted and is awaiting Apple review; no entitlement was added
  to the app before approval.
- Flutter analysis and all 360 Flutter tests pass. Signed profile and App Store
  IPA builds succeed with the refreshed Apple account and profiles.
- Stripe reports business and platform identity verification complete, and the
  public `@workloopapp` Stripe profile is active. The direct-charge Connect
  model and Connect Platform Agreement are confirmed in the dashboard.
- Four public Stripe handoff routes for setup return/expiry and Checkout
  success/cancellation are implemented, validated and deployed in Workloop
  website version 5. All four production URLs return HTTP 200.
- A production connected-account webhook is active for payment, Checkout,
  refund, dispute and account events. Its signing secret and all four public
  handoff URLs are stored in Supabase. The authenticated live Stripe API key is
  installed and `STRIPE_LIVE_MODE_ALLOWED=true` is active.
- The approved one-time cleanup removed one test connected account, two
  non-succeeded test transactions, 18 test webhook events and the legacy test
  account pointer. Payment/refund/webhook tables are empty and invoice Stripe
  attribution remains zero.
- A read-only Stripe account request returned HTTP 200 for the expected Workloop
  platform with charges and payouts enabled. An unauthenticated payment-function
  probe now reaches the expected HTTP 401 boundary rather than the live-mode
  HTTP 503 block. Stripe records the negative-balance liability and ongoing
  seller-compliance acknowledgements as completed on 12 August 2026. The first
  live Accounts v2 merchant account was created for the authenticated production
  workspace and is pending hosted onboarding; charges and payouts remain disabled.
  No charge, refund or live webhook has been created. Hosted onboarding and one
  bounded payment/refund smoke test remain.

### 2026-08-11 authentication and backend hardening

- Confirmed email/password, native Apple sign-in, Google OAuth entry and TOTP
  setup/challenge flows are implemented. Apple and Google are enabled live;
  Google is limited to the owner while its consent screen remains in testing.
- Supabase now rejects leaked passwords and passwords below the 12-character,
  uppercase/lowercase/number/symbol baseline. Sessions are capped at 30 days
  and expire after 7 inactive days; refresh-token replay detection remains on.
- Opted-in MFA is enforced at both the Flutter auth gate and database boundary.
  Twenty-two authenticated public tables received a restrictive AAL2 policy,
  while accounts without a verified factor retain existing AAL1 access.
- Trigger-only functions are closed to mobile RPC use, direct Postgres requires
  SSL, and the live Supabase security advisor reports no findings.
- Auth connection allocation now uses the dashboard-recommended 17% strategy,
  preserving the current 10-of-60 ceiling while scaling with future compute.
  Performance advisor output is otherwise limited to pre-beta unused-index
  information; relationship, workflow and cleanup indexes were retained until
  representative production telemetry exists.
- App Store Connect contains the Workloop record (`6800472527`). Xcode signing
  is connected and App Store IPAs export successfully. Apple rejected build 1
  for missing camera and photo-library purpose strings referenced by the file
  import dependency; the truthful strings are now present and replacement
  build 2 passed processing and is `Ready to Submit`. The automatically
  distributed `Workloop Internal Beta` group contains the build and its focused
  testing guidance; adding the sole Account Holder is currently disabled by
  App Store Connect despite the documented eligible role.
- The verified `auth@workloop.uk` SMTP path delivered a real Supabase recovery
  email and the seven security-change notifications are enabled. External beta
  still needs a fresh-account confirmation test outside the development team.
  The newest visible scheduled database backup is 8 August and must be
  rechecked after the Pro upgrade produces its next scheduled snapshot.

### 2026-08-12 QA and release-candidate truth refresh

- The latest observed safe local source run reports clean Flutter analysis and
  360/360 unit/widget tests. This does not supersede the release-candidate gate:
  the signed-out iOS simulator integration currently fails because the Auth mode
  toggle is below the tappable 402 x 874 viewport and its tap does not reach the
  Create-account state.
- The repository now authors 82 pgTAP assertions (51 schema/security, 16 tenant
  isolation and 15 privileged-MFA/payment-retention). No clean replay or pgTAP
  pass was produced locally because
  Docker and the Supabase CLI are unavailable; historical rolled-back live
  scripts are not a substitute.
- The production-refusing staging SDK isolation harness now covers practical
  core mutations across contacts, services, appointments, invoices and line
  items, expenses, tasks and checklists, notes, notifications, booking requests,
  push tokens and calendar-sync accounts. It records every disposable row
  for owner cleanup and still has no passing staging result. Its canonical
  runner requires the declared staging project ref to match the Supabase URL,
  enforces the same guard inside each test process, and supplies credentials
  through a private temporary Dart-define file rather than command arguments.
- Android key properties and keystore patterns are ignored. CI and signed-build
  commands use `scripts/qa_release_candidate.sh`, which refuses tracked or
  untracked changes, verifies an optional expected full SHA, rejects tracked
  signing material and stale target artifacts, then records
  commit/version/toolchain provenance plus new artifact sizes and SHA-256. The current
  owner worktree is intentionally dirty, so it is not a releasable candidate.
- The local privacy/terms source and deletion instructions now reflect the
  canonical `workloop.uk` surface, `support@workloop.uk`, Stripe processing and
  the current Business > Settings > Account navigation. The deployed 10 August
  legal pages remain older; publication, legal-controller details, mailbox
  monitoring and launch-market legal review remain external.
- Build 3 remains a valid local signed archive only. It was not accepted by App
  Store Connect and predates current source/backend payment work, so it must not
  be used as the beta artifact.
- Stripe live configuration exists, but the merchant remains pending hosted
  onboarding and no live charge/refund has run. Tap to Pay still lacks Apple's
  entitlement. Payment collection remains gated rather than beta-operational.

Current verdict: continue developer testing. Do not invite even a small external
beta until the Auth integration defect, clean database/pgTAP run, disposable
staging workflows/isolation, external Auth lifecycle and current clean signed
artifact are green. Physical Android/accessibility, observability,
performance/load, complete payment operations and store/legal operations remain
explicit public-launch gates.

### 2026-08-12 beta-blocker remediation and integrated verification

- The first-run Auth action now appears above the fold. The signed-out journey
  passes on the 402 x 874 iPhone 17 Pro simulator and still covers account-mode
  switching, returning to sign in, and password recovery. This supersedes the
  red Auth result immediately above.
- A forward migration now protects privileged onboarding/task/booking RPCs with
  the existing opt-in MFA policy, removes authenticated access to private
  implementations, gives authenticated Edge Functions a bounded policy check,
  links Stripe webhook events to workspaces, and limits full webhook payload
  retention to 30 days with deletion-time and scheduled scrubbing.
- Stripe readiness now requires details, charges, and payouts. Privacy export
  includes connected-account, provider transaction, and refund records. Account
  deletion fails closed until Workloop's Stripe Accounts v2 merchant account is
  confirmed closed.
- Booking/request language, calendar permission recovery, calendar-copy error
  handling, in-app and local public payment/legal disclosures, Android signing-secret
  ignores, compact Business/booking layouts, current responsive coverage, and
  clean-candidate provenance checks are implemented.
- Integrated local evidence is clean: 220 Dart files formatted, no analyzer
  findings, 371/371 Flutter tests, 52.84% line coverage, 27/27 protected
  goldens after reviewing the three intentional baseline changes, 30/30 Deno
  tests, eight Edge entry-point checks, four data-profile dry runs, signed-out
  simulator smoke, signed iOS profile (71.3 MB), Android profile APK (158.7 MB,
  16 KB aligned and v2 signed), and web release compilation.
- That fresh signed profile installed and launched on the paired iPhone 15 Pro
  Max; CoreDevice confirmed the current Runner process (PID 95655). This is
  install/launch evidence, not manual workflow or VoiceOver evidence.
- Production remains unchanged. The new migration's 82 authored pgTAP
  assertions still require a clean replay, and the expanded core/public/two-user
  staging journeys still require a disposable non-production project. The
  clean-candidate preflight correctly rejects the current owner worktree.

Current verdict: the source-level Auth, MFA-boundary, payment-data, legal-copy,
responsive and release-process defects found in the audit are remediated. An
external beta remains gated by clean database/staging evidence, external Auth
lifecycle proof, support/legal operation, and a clean tagged TestFlight build.

### 2026-08-13 exact beta-candidate evidence refresh

- Candidate source is clean and immutable at
  `81673f6e5f67b11a5c4f2697e51477d95811ab4f`, local tag
  `v1.0.0-beta.4`, version `1.0.0+4`. The tag remains on the app-source commit;
  this later documentation-only evidence does not describe a different binary.
- Fresh exact-tag verification passes formatting across 222 Dart files,
  Flutter analysis, 375/375 Flutter tests, 52.86% line coverage, protected
  goldens, the signed-out iOS simulator journey, 32/32 Deno tests, eight Edge
  entry-point type checks, and four deterministic data-profile dry runs.
- An isolated local Supabase stack rebuilt all 52 migrations from an empty
  database. All three pgTAP files passed with 83 assertions, database lint had
  no warning-level findings, and local Data API/Auth checks covered anonymous
  denial, tenant isolation, confirmation, recovery/password replacement,
  refresh-token revocation, TOTP challenge and AAL2 enforcement.
- The exact-tag App Store IPA is 33,854,083 bytes with SHA-256
  `2dc632e23f5ea00a54df57405d9b675fb8ca33b749310ba4df5c461a0ca3c6fa`.
  Strict verification passes under Apple Distribution team `6RH526FD7B`; its
  Store profile has `beta-reports-active=true`, `get-task-allow=false`, Sign in
  with Apple, and no unsupported proximity-reader entitlement. It is not
  uploaded.
- Production remains behind local security/payment source. Do not blanket-push
  migrations. Hosted staging must reconcile the missing booking/contact
  hardening before the privileged MFA/payment-retention migration, then deploy
  candidate Edge Functions with both payment gates false.
- Dynamic hosted staging core, two-user, public-booking and deletion journeys
  remain blocked pending owner approval for a disposable paid preview branch.
  External Auth/provider delivery, physical accessibility/lifecycle QA,
  support monitoring/legal approval, crash visibility and load measurements
  remain separate human or operational gates.

Current verdict: **not ready to upload** under the strict beta definition. The
signed artifact is valid and reproducible, but hosted staging, external Auth,
exact-build manual-device, support/legal and production-promotion gates remain
open.

### 2026-08-13 booking-request confirmation email implementation

- Build 5 source now requires a customer email on new public booking requests,
  normalizes it at the public Edge boundary, retains it on the request and
  converted client, and keeps legacy email-less requests confirmable.
- Owner confirmation now enters an authenticated Edge Function and the existing
  MFA-aware, tenant-checked, idempotent booking workflow. The captured request
  address is authoritative and cannot be redirected by a tampered or older app.
- The booking transaction also creates one private confirmation-email outbox
  row. Resend delivery is idempotent, HTML-escaped, leased and retried with a
  bounded backoff. The app distinguishes sent, queued, terminal failure and
  legacy no-email outcomes without pretending the booking failed.
- Public and in-app privacy copy now describes requester email, confirmation
  purpose and Resend processing. Payment collection remains independently
  disabled for beta.
- Local backend proof replays all 55 migrations, passes 111/111 pgTAP
  assertions across four files, reports zero warning-level database lint
  findings, passes 38/38 Deno tests, and type-checks both new handlers. Focused
  Flutter booking/public-profile tests, the full 383/383 Flutter suite and
  analysis also pass.
- The 71.2 MB iOS profile compiles and signs as `1.0.0 (5)` and passes strict
  code-sign verification. Because the feature tree is not frozen or deployed,
  this is compile evidence only and is not the next App Store IPA.
- This work supersedes Build 4 as the next source candidate: the intended next
  identity is `1.0.0+5` / `v1.0.0-beta.5`. Beta 4 and its signed IPA remain
  immutable historical evidence.

Production is unchanged. A paid disposable preview branch successfully
replayed all 55 migrations, passed 111/111 hosted pgTAP assertions and clean
database lint, and ran the core, two-tenant-isolation and public-booking
journeys. The public journey proved one delivered confirmation with correct
recipient/content/time, one request/outbox on retry, honeypot and invalid-
service rejection, owner conversion, a secure every-minute Vault-backed drain,
and real provider-401 backoff/recovery. Resend reports `workloop.uk` verified
with DKIM/SPF and a valid DMARC record. The branch was cleaned and deleted.

Production promotion still requires explicit approval and ordered migration/
function deployment. Bounce/suppression operations, disposable account
deletion, external Auth lifecycle, physical accessibility and an exact clean
Build 5 distribution artifact remain open, so this is not yet an upload-ready
beta.

### 2026-08-15 account lifecycle and operating automations

- A deletion request now immediately bans the Auth identity and revokes its
  refresh sessions. Flutter independently revalidates the server-side Auth
  user and deletion state before exposing a workspace, clears any local
  onboarding draft and signs out locally when the identity is gone or pending
  deletion. A deleted identity can no longer fall through into onboarding.
- The existing protected scheduled worker completes requested deletions in
  bounded batches. It runs deletion before email work and isolates each job so
  an email-provider failure cannot leave a deletion request active. A manually
  removed Auth user can be recovered only when it has no remaining workspace
  memberships; ambiguous ownership still fails closed.
- The database now creates preference-aware, deduplicated attention items for
  booking requests waiting four hours, overdue invoices and a local-time 07:00
  daily brief. Existing device-side appointment and task reminder scheduling
  remains the reminder authority.
- Private operational alerts cover stuck deletions and delayed or terminal
  transactional email. The same worker sends those alerts to the configured
  operations address without logging customer content.
- Scheduled retention prunes old notifications, inactive push tokens, expired
  rate-limit state and retained Stripe webhook payloads. Completed-deletion
  identifiers and transactional outbox rows are scrubbed on bounded schedules.
- A weekly GitHub health check can verify a recent completed Supabase backup
  through a read-only Management API token. It is opt-in and fails closed when
  the latest completed backup exceeds the configured age.

Production now has lifecycle migrations `20260815192234`, `20260815192246`
and the service-role correction `20260815192737`, plus request-worker version
19, completion-worker version 22 and scheduled-worker version 11. The existing
minute cron is active, `OPERATIONS_ALERT_EMAIL` is configured, and its latest
HTTP response was 200 with no job failures. The first live run generated six
waiting-booking and 27 overdue-payment attention items, detected the existing
stuck deletion, completed it, closed the alert and delivered the pending
completion email. Both paid rehearsal branches were deleted after passing.

GitHub now holds a 90-day, single-project, backup-read-only credential, the
production project reference and `ENABLE_BACKUP_HEALTH=true`. A direct live
Management API check returned five backups and a latest `COMPLETED` backup at
2026-08-15 06:14:57 UTC. The scheduled check itself remains source-only until
this workflow and script are committed and reach the repository default
branch. A fresh disposable request/sign-out/re-signup journey is still required
before calling every mobile lifecycle transition externally proven.

### 2026-08-15 transactional Auth email pack

- All six Supabase Auth action templates and seven enabled security-change
  notifications now have a version-controlled Workloop subject, HTML body,
  clear purpose, fixed support route and consistent premium visual treatment.
- A separate private outbox queues exactly one welcome when a new Auth user
  first becomes email-verified, including provider signups that arrive already
  confirmed. Existing users are not bulk-emailed.
- The existing scheduled Resend worker now drains booking, launch-list and
  account-welcome queues. All three use fixed senders, stable provider
  idempotency keys, leases, bounded retry and no recipient/body logging.
- Local proof: all 56 migrations replay cleanly, 156/156 pgTAP assertions pass,
  database lint reports zero findings and the full Edge suite passes 48/48.
  Hosted Supabase now matches all 13 reviewed templates. Production has the
  private outbox migration and scheduled-worker version 8; its trigger/grants
  were verified read-only. A fresh external signup remains the final provider
  delivery proof for the new verification-to-welcome sequence.

### 2026-08-15 account-deletion confirmation emails

- An accepted deletion request now queues a purpose-specific email confirming
  that Workloop received the request while stating clearly that deletion is not
  complete yet.
- The authoritative transition to `completed` queues a separate confirmation
  only after workspace and Auth deletion have succeeded. It explains that the
  account can no longer be used and links the privacy notice for the limited
  records Workloop may retain for security, legal or financial obligations.
- Both events use a private, service-only outbox with one row per request/event,
  fixed recipient data, stable Resend idempotency, a five-minute lease and
  bounded 24-hour retry. Application clients cannot select a recipient, claim
  a job or manufacture a completion email.
- Production now has migrations `20260815190332`, `20260815190424` and the
  service-role correction `20260815192737` plus scheduled email-worker version
  11. Read-only verification found both triggers,
  denied claim access to `anon` and `authenticated`, granted only
  `service_role`, and found no unexpected queued rows. The production worker is
  intentionally limited to the four already-approved transactional queues;
  and the production scheduled worker has successfully claimed and delivered
  a pending completion email without exposing the queue to app roles.
- Combined local proof: all 62 migrations replay cleanly, 199/199 pgTAP
  assertions pass across eight files, database lint reports zero findings, the
  Edge suite passes 58/58, Deno format/lint/type-check are clean, Flutter
  analysis is clean, all 384 Flutter tests pass, and the iOS profile build
  succeeds. A controlled disposable deletion and inbox check remains the final
  external proof of provider delivery and exact request/completion wording.

### 2026-08-31 private founder control room and Apple beta reporting

- A private `reporting` schema now supplies aggregate-only current KPIs, daily
  metrics and source health to the owner-only Workloop Control Room in Google
  Data Studio. The database login inherits a NOLOGIN read-only group with no
  access to Auth or application tables.
- Verified Resend webhooks update delivery aggregates without storing recipient,
  subject or body content. Google Analytics and Search Console are connected as
  separate website sources.
- App Store Connect uses separate least-privilege team keys: Sales and Reports
  for future store analytics and Developer for TestFlight metrics. Their private
  keys exist only as hosted Edge Function secrets; the downloaded copies were
  removed after secret verification.
- `collect-apple-reporting` authenticates a daily Vault-backed Cron request,
  fetches tester state and 365-day sessions/crashes/feedback, discards tester
  identity, and upserts ten aggregate metrics. The first production invocation
  returned HTTP 200 with 7 installed testers, 97 sessions, 0 crashes and 1
  feedback item; the dashboard shows TestFlight source health as `succeeded`.
- Regular App Store download analytics remain dormant while Workloop is a
  TestFlight-only beta. The Sales and Reports credential is staged for the
  public-store reporting collector when a store release exists.

### 2026-08-31 Build 6 remote push candidate

- Build identity is now `1.0.0 (6)`. The iOS target includes the Push
  Notifications entitlement and remote-notification background mode.
- Firebase Messaging obtains the native APNs token on iOS and registers one
  opaque token per signed-in device through
  membership-checked RPCs. A refreshed token can belong to only one account,
  and explicit sign-out removes the current device token when possible.
- New business-attention rows fan out to a private per-device outbox. The
  existing protected minute worker claims with leases, sends privacy-safe lock
  screen copy directly through APNs, retries transient failures and disables dead
  provider tokens. Stored notification preferences and 21:00-07:00 local quiet
  hours are enforced before delivery.
- Tapping an alert opens only an allow-listed authenticated Workloop route.
  Foreground messages refresh the in-app centre without displaying a second
  system banner. Existing task and booking reminders remain device scheduled.
- Local proof is clean: Flutter analysis, 386 Flutter tests, 4 push-worker
  tests, Edge type-check and the signed iOS profile build all pass. The profile
  artifact is `1.0.0 (6)`, 73.2 MB, with development APNs and background
  entitlements.
- Firebase is attached to billed project `workloop-502614`; the iOS app and
  development/production APNs key are configured. The push migration, worker
  and APNs provider secrets are live. A controlled physical-iPhone sandbox
  delivery was visibly received, and the production-entitled Build 6 IPA is
  processed and `Testing` in both TestFlight groups. The remaining manual gates
  are foreground duplicate suppression, notification tap routing, quiet hours
  and two-account token reassignment.

### 2026-09-01 Build 8 feedback and stability candidate

- The complete tester-feedback list is implemented in source: compact Auth,
  refreshed expired-session recovery, one coherent dashboard reveal, anchored
  booking-page preview navigation, editable onboarding services, friendly
  hours/minutes and 12-hour public hours, selectable public services, exact
  workspace-timezone request times, and explicit owner confirmation for
  overlaps or outside-hours bookings.
- Public request-time guidance now compares the selected service duration with
  the published hours. It remains a preference rather than a promise, exposes
  no existing booking data and still permits an exceptional time request.
- Notification taps now use exact allow-listed entity routes. Direct APNs
  payloads include the privacy-neutral delivery identifier FlutterFire needs
  for foreground, warm-tap and cold-start callbacks, and both notification
  bootstraps navigate through the app router rather than an inherited context
  above it. Routes wait safely through sign-in when necessary.
- Async saves, pickers, provider refreshes, token registration and account
  actions now re-check mounted user/workspace state after waits, reducing
  disposed-widget crashes and cross-session races.
- Public service-role endpoints now require a current workspace member before
  serving a profile or accepting a request. A separate insert trigger is the
  database defence in depth. Production still has 8 ownerless public profiles
  exposing 29 active services until this source is promoted.
- Final local proof: 233 Dart files are format-clean, Flutter analysis is clean,
  all 406 Flutter tests and all 65 Edge tests pass, every configured Edge entry
  point type-checks, four deterministic data profiles validate, diff hygiene is
  clean and the development-signed `1.0.0 (8)` iOS profile builds at 73.2 MB.
- This remains a source candidate. The production project has no preview
  branch, the three new migrations have not had hosted replay/pgTAP, the Edge
  changes are not deployed, no distribution IPA exists and the physical
  notification/session/booking matrix remains open.

### 2026-09-01 Build 9 booking and interface candidate

- Auth now uses the installed W/arrows Workloop icon and a balanced standard-
  iPhone composition; compact-height devices simplify the brand panel and keep
  the complete form scrollable.
- Root and peer navigation use quiet filled selection states. Headers share a
  narrow module-colour marker and aligned top-right create actions, while all
  modal sheets share one radius, handle and padding system.
- Service rows no longer guess an industry with decorative icons. Owner service
  setup supports up to eight parent-scoped extras with extra duration and price;
  packages remain ordinary services.
- The public booking page offers capped suggested times computed from trusted
  hours, timezone, notice, buffer, existing work and the aggregate selected
  duration. Customers can always request another time and are told that a time
  is not held or confirmed.
- Booking requests and appointments use immutable service-item snapshots.
  Legacy intake remains compatible and receives the same trusted base snapshot.
- Repository reads now fall back only for the specific not-yet-deployed
  add-on/snapshot relations, so the signed candidate remains usable against the
  current Build 6 production schema while the staged migration is rehearsed.
- Current local proof: formatting and analysis are clean, 432/432 Flutter tests
  pass, 71/71 Edge tests pass, all configured handlers type-check and refreshed
  light/dark goldens were inspected. Database pgTAP is authored but cannot run
  locally without Docker/Postgres; production has not yet been changed.
- The candidate is versioned `1.0.0 (9)`. Its development-signed profile was
  strictly verified, installed and launched on the paired physical iPhone.
  A strict-valid 34,770,219-byte App Store IPA was also produced with
  production APNs, `get-task-allow=false` and `beta-reports-active=true`.
  Ordered backend promotion, the physical feature matrix and TestFlight upload
  remain release gates.

### 2026-09-02 Build 9 hosted rehearsal and production promotion

- A paid disposable Supabase branch replayed the five booking migrations from
  production migration `20260831174824`. The rehearsal found and corrected an
  ambiguous snapshot conflict target, retry ordering after add-on deactivation,
  an optional JWT-claim dependency inside service-role-only RPCs, and four
  missing composite foreign-key indexes. The branch was deleted after the final
  smoke matrix, so its hourly charge is no longer running.
- Hosted smoke evidence covered exact requested instants and timezone, base and
  add-on snapshots, duplicate request tokens, entity notification routes,
  privacy-safe availability, default overlap rejection, explicit overlap and
  outside-hours acceptance, deactivated-add-on idempotent retry, and the
  orphaned-profile 404 boundary.
- Production now contains migrations `20260902172036` through
  `20260902172046`. `get-public-profile` v25,
  `create-booking-request` v28, `get-public-booking-availability` v1 and the
  combined scheduled worker v21 are active; every deployed file matches the
  reviewed local source.
- Production RLS, grants, triggers and covering indexes match the rehearsed
  boundary. Security advisors report no finding against the new tables or
  service-role-only RPCs, and performance advisors report no new unindexed
  foreign keys. Live public profile and availability calls both returned HTTP
  200 with bounded Europe/London suggestions.
- The protected every-minute worker continues to return HTTP 200 after v21 was
  deployed. The only stored iOS token is a development token already disabled
  after APNs returned `BadDeviceToken`; installing and launching the TestFlight
  build must register a fresh production token before release push taps can be
  validated.
- Final source proof is 234 Dart files format-clean, Flutter analysis clean,
  435/435 Flutter tests and 71/71 Edge tests passing, configured Edge handlers
  type-checking, diff hygiene clean, and a signed iOS profile build succeeding.
- A fresh App Store `1.0.0 (9)` IPA is 34,766,683 bytes with SHA-256
  `2d4179b6043cd241ee1365fa03d173918ed8497f553c3775644fd5d14f6128a4`.
  Strict signature verification passes with Apple Distribution, production
  APNs, `get-task-allow=false`, `beta-reports-active=true` and Sign in with
  Apple. The iPhone was not reachable for a post-promotion install in this
  pass, so the physical feature matrix and TestFlight upload remain open.
- Two active public service rows still contain accidental durations of zero and
  9,999,999 minutes. Their real durations require owner confirmation rather
  than an inferred data correction.

### 2026-09-02 public service duration guard

- Production migration `20260902174021` quarantines the two invalid services:
  each is now inactive and hidden with a 60-minute review placeholder. Neither
  had linked appointments, and no booking history was changed.
- `services_duration_mins_check` is validated in production and rejects base
  service durations outside 5-1,440 minutes. Flutter repository validation and
  `get-public-profile` v26 apply the same bounds before a value reaches or
  leaves the database.
- Live checks show zero invalid service rows, both affected public pages omit
  the quarantined service, and a controlled 9,999,999-minute update is rejected
  by Postgres. Owners can correct and reactivate their service from Settings.
- Final source proof is analysis-clean with 438/438 Flutter tests and 71/71
  Edge tests passing. The rebuilt App Store `1.0.0 (9)` IPA is 34,766,747
  bytes with SHA-256
  `e8e0df6a5b657a8043049503cf5f33d7b68d760120da92eddeeff59d16145006`.

### 2026-09-02 Build 8 app polish candidate

- The next locally installable beta candidate is version `1.0.0 (8)`. Earlier
  Build 9 notes describe a superseded internal rehearsal and are retained as
  history rather than renumbered.
- A single `WorkloopAppCanvas` now owns the textured light/dark background above
  the app Navigator. Route scaffolds and retained workspace layers are
  transparent, so navigation no longer reconstructs or shifts the artwork.
- Authenticated route gates seed from the current Supabase session and reuse an
  already-prepared workspace for the same user instead of invalidating shared
  providers on every routed screen.
- Owner-created bookings can select the same parent-scoped service add-ons used
  by public requests. Duration and price are composed from the base service and
  selected extras before the existing booking workflow snapshots them.
- Packages remain an intentionally simple catalogue service with one combined
  name, duration and total price; optional extras can be added after saving.
- Module identity is limited to restrained header markers and active navigation
  states. Ordinary content, lists and the persistent canvas stay neutral.

### 2026-09-04 Quiet + Warm rollout and Build 11

- The owner explicitly approved a full Quiet retro + Warm desktop visual reset,
  superseding the earlier Studio presentation. The app, native icon/splash,
  public website, private Workloop OS, hosted Auth/transactional emails and
  Stripe platform branding now share the new identity.
- iOS 1.0.0 (11) is approved and Testing for the existing 13 private beta testers.
  A signed profile of the same candidate installed and launched on the iPhone.
  The Android 11 bundle was signed and validated on an emulator; Play publication
  and physical Android validation remain open.
- Analysis is clean; 485 Flutter tests passed with four flag-dependent skips;
  the actual enabled payment configuration passed its separate five-test suite.
- Eight editable Canva masters and a reproducible, platform-sized brand kit are
  ready. Instagram's avatar is live; TikTok awaits completion of account sign-in.
- Detailed coverage, evidence limits, artifacts and remaining public-launch
  requirements: `docs/releases/2026-09-04-quiet-warm-rollout.md`.

## 2026-09-05 — email lifecycle expansion
Deployed customer booking-reminder workers and consent-aware account onboarding, weekly business tips and inactivity journeys. Verified real inbox delivery and both unsubscribe paths. Website email preferences/privacy updated live. App controls implemented and validated; Build 12 preparation is in progress, so do not attribute these controls to Build 11. Details: releases/2026-09-05-email-system.md.

### Owner release hold
Build 12 TestFlight upload is explicitly on hold pending further requested improvements. No Build 12 upload occurred. Backend/email and public website changes are live; app controls remain local. Final app verification: 488 tests passing, 4 skipped, static analysis clean.

### 2026-09-05 — customer lifecycle email additions
Booking acknowledgements/declines/changes/cancellations, conditional setup help and the combined weekly summary are live and verified with synthetic inbox delivery. Deliberate payment-request email UI is implemented locally. Full app suite 489 passed / 6 feature-gated skips; enabled-payment suite 7 passed; database 468 assertions; email tests 14; signed profile build passed. Ten additional previews and a complete 76-variant guide were sent to the owner. Website email guidance is public. TestFlight remains explicitly held. Direct-charge refund receipt settings still require real connected-business verification; see releases/2026-09-05-customer-lifecycle-emails.md for evidence and limits.

### 2026-09-05 — Direct business contacts in email

Customer emails now display direct business contact details instead of asking for replies. The new contact editor is local; TestFlight remains on hold. Backend contact resolution is live and all three customer delivery paths passed controlled inbox checks. The collection has 100 user/customer variants plus two internal alerts; 26 exception variants are prepared for verified events/review, not automatically enrolled. Details and evidence: [email contacts and exceptions](releases/2026-09-05-email-contacts-and-exceptions.md).

### 2026-09-05 — Workspace reliability and Quiet + Warm polish

Implemented opaque page transitions, immediate retained tabs, shared business
data and clock refresh, truthful loading/errors, safer editors and account
revalidation, simpler Today and stronger continuous navigation/panel frames.
Removed the visible Business Feed/duplicate Coming up; retained useful incoming
notifications. Optional local weather and updated native disclosures are ready.
Weather v1 and website policy v33 are live. **542 Flutter tests passed, six
configuration skips; eight explicit payment checks passed; analysis clean.**
Both iOS and Android profile builds pass with card collection enabled. The
1.0.0 (12) profile installed and launched on the paired iPhone. Interactive
phone checks and Android smoke results are recorded in the detailed report.
TestFlight is still on hold. See
[the app improvement report](releases/2026-09-05-app-improvement-pass.md).

### 2026-09-05 — Final compact navigation and device checks

Owner refinement: the bottom navigation now uses a 64-point row, lower icons
and vertical dividers extending through the home-indicator safe area. Final
analysis is clean; **550 Flutter tests pass, six configuration skips**. Final
iOS and Android profile builds passed. The new iPhone build is installed and
launched; Android launches on a fresh API 36 emulator with no captured runtime
errors. Physical iPhone checks confirmed local weather, clean Record income
transitions and linked tab data before the final bar adjustment. That final
bar has raster/golden coverage; Mirroring was unavailable for its last physical
visual check. Full evidence and limits are in the improvement report above.
**TestFlight remains explicitly on hold.**


### 5 September 2026 — further app refinement and reminder groundwork

The current local app has compact working-screen headers (Today retains the
wordmark), a 52-point navigation row plus safe area, continuous dividers and
visible-only tap-to-top behavior. Business hierarchy, onboarding occupations,
first-use guide and additional email access flows are implemented. Adversarial
review fixed account-switch cleanup races, partial-success setup failures,
slow-save cache handling and client next-booking selection.

SMS groundwork and the verified-email onboarding boundary are deployed. Texting
is off: no customer permissions, queued texts or enabled businesses were present
at verification. Apple browser authentication is configured through its real
Services ID; final external account/device journeys remain release gates. No
TestFlight upload is authorized. Refer to the dated app/auth/SMS release reports
for final tests, build evidence and remaining provider requirements.

### 2026-09-05 — SMS paused; WhatsApp feasibility only

The owner has paused SMS because of its ongoing cost. Text reminders remain off,
with no Twilio account creation/funding, sender rental, SMS phone-auth activation
or customer enrollment to proceed while paused. The disabled groundwork is
retained; email reminders continue independently. This is not a commitment to
make SMS available later.

WhatsApp reminders are being assessed for feasibility only. Implementation,
activation, customer enrollment, sending and spending have not been authorized.
See [the SMS decision and evidence](releases/2026-09-05-booking-sms-reminders.md).
### 2026-09-05 — Manual WhatsApp implementation follows the SMS pause

The owner authorized a manual booking reminder through WhatsApp: Workloop
prepares a draft, while the owner reviews and sends in their own WhatsApp app
or website. Implementation and verification are in progress. Automated email
reminders continue; SMS remains disabled and no WhatsApp Business API account,
paid sender or scheduler is being activated. This supersedes the earlier
feasibility-only status for the **manual action only**. The TestFlight hold
remains in force.

### 2026-09-05 — Manual WhatsApp reminders implemented in source

Upcoming scheduled bookings now offer **Send WhatsApp reminder**. The action
reads current booking/client/business details, prepares the saved-business-zone
message and opens WhatsApp or its website. The owner reviews their sending
account and message, then sends it themselves. Failed launches retain a flat
inline draft/copy option; missing phone numbers link to the existing client
action. No automatic WhatsApp send, paid messaging API, database write or
delivery claim was added. SMS remains off and email reminders are unchanged.

The existing client WhatsApp action also handles UK/international numbers and
launch failures safely. The focused reminder/booking/client batch passes
**38 tests**, scoped analysis reports no issues and the diff whitespace check
is clean. This supersedes the implementation-in-progress entry above for
local source. Full integration tests, goldens, builds and physical-device
handoff verification remain pending root's final checks; TestFlight is still
on hold. See [the manual WhatsApp report](releases/2026-09-05-manual-whatsapp-reminders.md)
for files, guards, coverage and limits.

### 2026-09-05 — Settings and notification audit implemented

Local Settings now has distinct owner alerts, customer reminders and Workloop
email destinations, plus direct account/privacy access. Account actions have
clearer consequences, failed-edit recovery and stale-account/export guards.
Maps/appearance save failures are honest, and the maps chooser now remains
usable on small screens with enlarged text. Client push/local-reminder retries,
identity changes and deferred notification taps were repaired.

Focused batches passed **17 account, 30 settings/preferences and 23 notification
client tests**. Full analysis is clean. The first full run had 703 passes, six
configuration skips and only two intended Settings golden changes; both were
visually reviewed and updated. Final whole-app rerun/build/device/provider
verification is pending the integrator's final record. Two reviewed push
migrations are live, with **647 full database assertions / 129 focused push
assertions** passing. This is not a new uploaded/installed app claim, and
permission/registration is not proof of delivery. TestFlight remains held;
SMS remains off. Details: [settings and notifications](releases/2026-09-05-settings-and-notifications.md).

### 2026-09-05 — Money overview ahead of transaction history

Money now keeps the received total, cash movement, target and payment setup
above its transaction history. Made and Spent initially show the five most
recent entries in the selected period; View all exposes the complete matching
history with its existing edit/delete actions. Expanding or collapsing keeps
the control and scroll offset in place. Changing the period returns to the
recent view. Spent places category totals before history, while Owed retains
its complete overdue-first action queue. Payment setup also remains available
when using Custom dates; target calculations remain weekly/monthly only.

The focused Money/hierarchy/failure batch passed **40 tests**, including
**11 new long-history regressions**. Scoped Dart analysis and whitespace checks
passed. The integrator visually reviewed the two intended Money golden changes
and their update run passed **2 tests**. The final combined suite and fresh
native builds remain pending the last notification permission-event integration;
earlier receipts do not verify that final combination. No records, financial
calculations, providers or payment activation settings were changed by this
hierarchy pass. TestFlight remains on hold. Details and limits are appended to
[the settings and notification report](releases/2026-09-05-settings-and-notifications.md).

### 2026-09-06 — Settings, notification and Money integration verified locally

The final combined source passed full analysis, **718 Flutter tests** (six
configuration skips), an additional **18 payment-enabled checks**, and fresh
iOS/Android profile builds. The final app was installed on the owner's iPhone
and launched at **00:08:45 BST**. Its build-12 token registered an eligible
active session one second later; the live worker was healthy with no pending
deliveries. This completes the earlier pending source/build entries, not
physical notification delivery verification.

Google blocked Android server-key creation with
`iam.disableServiceAccountKeyCreation`. The owner chose to preserve that policy
and leave Android push configuration pending. No key/secret or policy exception
was created. iPhone Mirroring remained unavailable while the phone was in use,
so native notification-settings round-trip and visible background/terminated
push/tap checks remain outstanding. No test push or quiet-hour override was
performed. No TestFlight/Play upload was made. Full receipts, changed files,
limitations and follow-up checks are in the final integration section of
[the audit report](releases/2026-09-05-settings-and-notifications.md).

### 2026-09-06 — Dashboard clocks and exact attention actions

The decorative calendar has been removed from Today and its clear-day hero.
Each booking's analog clock now matches the digital booked start, including
minute-adjusted hour hands and the newly selected booking when swiping.

Needs attention now retains each active request's identity and opens the exact
request, payment, task or client after refreshing that record's source. The
four-row preview reserves an entry for every available attention category before
filling remaining slots in the existing priority order, so a request backlog
does not hide every overdue task/payment. No extra inferred note/booking alerts
were introduced.

Eight clock/dashboard checks and 34 attention/provider/navigation checks pass;
scoped analysis and whitespace checks are clean. The companion client batch
passed 63 focused tests. The reviewed backend route repair is live at
00:24:36 BST, with 96 historical destinations repaired and no notifications
replayed. Final full-suite, golden, native and device receipts for this combined
revision remain pending the integrator's handoff.
These results do not prove physical push delivery or a new installed/uploaded
build. TestFlight remains held. See
[dashboard direct actions](releases/2026-09-06-dashboard-direct-actions.md) and
[notification route repair](releases/2026-09-06-exact-notification-routes.md).

### 2026-09-06 — Dashboard direct actions verified and installed

The combined revision now passes clean analysis, **758 full-suite Flutter tests**
(six default capability skips), **18 payment-enabled checks** covering those
skips, and the reviewed dashboard/notification goldens. The final focused
notification navigation batch is 66 passing checks, including preservation of
an unsaved draft when another record is opened from an alert.

Fresh iOS and Android profile builds passed. The updated **1.0.0 (12)** app was
installed and launched on the owner's iPhone at **00:38:18 BST**. This replaces
the earlier pending native-build state above. Physical notification display/tap
checks remain unverified because iPhone Mirroring could not reconnect; no test
push was sent. Android remote push remains pending under the owner's unchanged
service-account key policy. No TestFlight or Play upload was made.

The final receipt, artifact hashes, original fixture failure and successful
rerun, files/reasons, and remaining checks are appended to
[dashboard direct actions](releases/2026-09-06-dashboard-direct-actions.md).

### 2026-09-06 — Consistent monthly income targets

At a glance and Money now share the calendar-month income calculation and
progress indicator. The goal remains monthly while Money history is filtered
to Week, Month or Custom. Red means below 50%, amber means 50% to below target,
and green means reached/exceeded. Penny precision prevents fractional-payment
sums from leaving a reached target incorrectly amber; percentage and spoken
status remain available alongside colour.

The monthly-only editor saves the existing monthly setting, supports zero to
remove it, validates invalid amounts, and owns its controller through the
closing animation. Source passes clean analysis, 784 full-suite tests, 18
payment-enabled checks and reviewed goldens. Both native profile builds pass.
The fresh build 12 was installed on the iPhone at 00:56 BST; launch was blocked
by the locked phone, and Mirroring by the locked Mac. No store upload occurred.
See [monthly target changes and verification](releases/2026-09-06-monthly-targets.md)
for files, the save-lifecycle repair, receipts and remaining physical check.

### 2026-09-06 — Notification settings recipient/channel clarity

Settings now groups **Your alerts** and **Emails to you** under **For you**,
with **Customer messages** separately under **For your customers**. The Business
shortcut uses the same destination label. Single paper panels contain flat
rows; compact icon treatment and consistent header/body spacing preserve the
Quiet + Warm design without nested content cards.

Your alerts explicitly distinguishes in-app inbox + business push, local phone
reminders and business-push-only quiet hours. Customer settings distinguish
automatic email from manual WhatsApp. Email preferences correctly distinguish
an active limited welcome series from ongoing account tips; this changes the
presentation, not saved consent/defaults or backend delivery rules. Failed
email saves are immediately visible. Shared panel Material now correctly
supports native switch/list-tile feedback.

Final verification: **816 Flutter tests passed, six configuration skips**;
**63 payment-enabled integration checks** covered the gated cases, and the
46 focused Settings cases passed. All twelve new light/dark visual captures
were reviewed before acceptance; existing Settings/Business goldens were
reviewed and the full suite passed. Full analysis and whitespace checks passed.
iOS (74.1 MB) and Android (163.1 MB) profile builds succeeded. Local 1.0.0 (12)
was installed on the iPhone at 01:22 BST; launch was denied at 01:23:20 because
the phone was locked. Mirroring also found the Mac locked, so final hands-on
screen and push-delivery verification remains pending. **No store upload**.
Android remote push remains pending under the owner's retained policy choice.

The source audit also records the existing absence of a Stripe-webhook owner
payment notification as a separate backend follow-up. Full scope, source file
reasons, channel matrix, artifact hashes and native limitations are in
[the Settings clarity receipt](releases/2026-09-06-notification-settings-clarity.md).

### 2026-09-06 — Stable dashboard section loading

Needs attention now reserves a loading space on its first check, with At a
glance revealed after that check and the initial setup preference settle.
Background refreshes preserve the accepted same-workspace attention result;
refresh errors retain it with explicit last-update/retry feedback. Switching
workspaces clears the acceptance marker. No duplicate business-data cache or
resolved-screen redesign was introduced.

Verification: clean analysis; **827 full-suite passes, six configuration skips**;
**18 payment-enabled passes** cover the gated cases; **26 focused dashboard
and workspace passes**, including 11 new loading regressions. Existing goldens
passed without updates. iOS and Android profile builds passed. Local build
**1.0.0 (12)** installed on the iPhone at **01:37 BST**; launching was denied
because the phone was locked, and Mirroring reported the Mac locked. Physical
transition observation remains pending. No store upload occurred.

See [dashboard section stability and verification](releases/2026-09-06-dashboard-section-stability.md).

### 2026-09-06 — Net profit and searchable Payments timeline

Money now opens on Overview, with Net profit showing received income minus
recorded expenses for the selected period. Signed bars distinguish profit and
loss around a zero line. The monthly income target remains independent.

Payments combines received income and expenses, newest first, with All / Income /
Expenses filters and whole-period search. The normal preview remains five rows;
search shows up to 25 matches with a total count and View all results. Spent and
Owed have independent search. Part-payments and negative adjustments reconcile
with the totals, and partial-payment details show received and remaining amounts
using the actual receipt date. Missing expenses cannot produce a falsely complete
net-profit figure. Existing records, repositories and collection flows are reused.

Final evidence: clean analysis; **863 full-suite passes, six configuration skips**;
**76 payment-enabled focused passes**; **26 monthly-target passes** after scoping
older test selectors to the editor and received panel. Two updated and three new
Money goldens were visually reviewed, accepted and passed in the full run. iOS
74.2 MB / Android 163.2 MB profile builds passed. Local **1.0.0 (12)** installed
on the iPhone at **02:02 BST**; launch was denied because the phone was locked,
and Mirroring also found the Mac locked. Physical Money checks remain pending.
No store upload, backend deployment or live customer transaction occurred.

See [Money profit/timeline scope, previews and receipt](releases/2026-09-06-money-profit-and-timeline.md).

## 2026-09-06 — Crash reporting candidate implemented

Firebase Crashlytics is now included in source using the existing Firebase app.
The Dart adapter submits fixed error categories and static code-stack frames,
without customer/request contents, user IDs, custom logs or Analytics breadcrumbs.
Native crash diagnostics and installation/session identifiers still follow the
SDK's data practices. Release configuration defaults reporting on and records the
choice; local debug reporting stays off. Focused 16 Dart + 19 release/symbol tests
pass. Full integration, native builds, a device report and readable Firebase
console receipt remain pending; no TestFlight upload is implied. See the
[crash-reporting scope and verification](releases/2026-09-06-crash-reporting.md).

## 2026-09-06 — Workloop company operator disclosures

Workloop remains the product/trading name. Haani Enterprise Limited, company
15758586 (England and Wales), is now identified in app Help/About/legal copy,
public website/legal/booking/payment pages, private Workloop OS, and live
email/Auth footers. Public registered-office disclosures retain 35 Well Lane,
Batley WF17 5HQ; the proposed replacement address has not been filed.

Flutter analysis is clean; 885 tests pass with 6 skips and the signed iOS profile
build succeeds. No TestFlight upload or new installed app is implied. Both
websites have verified live disclosures, with private OS access preserved.
Email rollout uses isolated live bundles and 13 content-only Auth updates;
triggers, schema, consent, SMTP and authentication settings are unchanged.
Provider identity changes and Apple/Google/Stripe verification are tracked
separately from these source/live-content receipts. See
[operator release evidence](releases/2026-09-06-company-operator-app.md) and
[email rollout](releases/2026-09-06-email-operator.md).


## Current release preparation — 7 September 2026

See [the overnight release record](releases/2026-09-07-launch-preparation.md) for current source/backend/site evidence, lifetime beta access and new pricing. Older brand/build/pricing descriptions above are historical. Public iOS launch remains gated on verified store purchases, public review and genuine merchant payment testing; Android additionally requires external account/push setup.

## Booking corrections — 7 September 2026, local build 14

Requested booking dates now prefill accurately, including the public website's
older text-only requests. Exact booking links open directly without showing the
Today list first, and Tomorrow's ordinary time labels no longer append BST/GMT.
The website-origin correction is live in version 37. Full app tests passed
1,011 cases; the six capability-gated payment cases were exercised in a separate
seven-test enabled run. Analysis and the signed iOS profile build are clean.
Build 14 is compiled locally; phone installation/physical checks remain pending
device connectivity, and it has not been uploaded to TestFlight. See the
[integrated receipt and limits](releases/2026-09-07-booking-fixes-build14.md).

## Build 14 upload — 7 September 2026, 08:31 BST

The prior local-only status is superseded: the signed distribution candidate
**1.0.0 (14)** was uploaded successfully from a frozen clean copy of the tested
source. Apple reported the package is processing at 08:31:11 BST. Production
push signing, version/bundle identity and location-purpose strings were verified.
Root working changes remain intact.

Processing completion and beta tester availability still require verification;
App Store Connect's browser session has expired. Physical iPhone checks remain
pending because the user is at work. No public release or availability email was
sent. See the [upload follow-up and evidence](releases/2026-09-07-booking-fixes-build14.md).

## Android beta candidate — 7 September 2026

Signed APK and Play App Bundle **1.0.0 (14)** are prepared from the same tested
source as iOS build 14. Signature, version, Android 8+ compatibility, ARM64 native
alignment and isolated release-emulator startup/navigation checks passed. Google
Play organisation registration is still pending the permanent owner-login choice,
fee and verification; neither Play nor Firebase distribution is claimed. Live
beta configuration confirms verified new Workloop accounts receive lifetime
access without a purchase. See the [Android beta receipt and limits](releases/2026-09-07-android-beta-build14.md).


### 2026-09-07 — Social links and reviewed contact-file imports

Website version 38 is live with four social profiles, a Works with strip and
`/help/connections`. Locally, client imports now accept UTF-8 vCard 3.0/4.0,
combine split CSV names, ignore provider type-label columns and allow contact
exclusion before import. Analysis, 1,018 full-suite tests (six capability skips),
24 final import checks and the final signed iOS profile build passed. No new
TestFlight/Android distribution or physical-device import check is claimed.
See [the scoped release record](releases/2026-09-07-social-links-and-client-imports.md).

## 8 September 2026 — Connected business tools, local delivery

Implemented the four owner-approved phases: quotes/invoices with local PDF
sharing and connected partial payments; finite recurring bookings; private
receipt/mileage records; and a scoped 2026/27 sole-trader tax estimate for
England, Wales and Northern Ireland. The existing Money, booking and expense
workflows remain the entry points.

Final analysis is clean. The full Flutter suite passed 1,065 tests with six
capability skips; the payment-enabled run passed all seven cases. Isolated SQL
replay passed 928 assertions across 30 suites. The signed iOS profile build
passed, and invoice UI/PDF layouts were visually checked.

These are local source/build results. The three migrations and receipt-aware
account-deletion endpoint are not deployed, and there is no new TestFlight
upload. The iPhone was unavailable; authenticated hosted Storage and native
picker/share checks remain release gates. See
[files, scope, evidence and deployment order](releases/2026-09-08-business-tools.md).

## 8 September 2026 — Build 16 deployed for the owner

The owner approved deployment and device installation, then explicitly limited
the new build to themselves. The three feature migrations and receipt-aware
account-deletion endpoint v31 are now live. Authenticated hosted receipt,
tenant-isolation, invoice/payment, mileage/tax and recurring-booking checks
passed; all isolated QA fixtures and credentials were cleaned up.

Build **1.0.0 (16)** was installed and launched on the owner's iPhone over Wi-Fi;
CoreDevice independently reported build 16. The new Money tools and forms were
inspected on the phone. Apple upload and processing completed. Only the internal
group containing the account holder is assigned; the external beta remains on
build 15. No public App Store submission occurred.

See [the owner-preview receipt and verification limits](releases/2026-09-08-build16-owner-preview.md),
including interrupted native picker/PDF-share checks and the separate hosted
account-deletion lifecycle limitation.

## 8 September 2026 — Build 17 business-workflow review

Invoices/quotes now have a main Money destination. Reviewed Invoice setup
reuses canonical business contacts and supplies legal/term defaults; client
and booking entry points open the same invoice/payment record. Fixed/percentage
deposits, dated receipts/refunds, gross VAT reuse, current card balances and
safe retries are verified. Receipt capture includes camera/library/Files,
mileage/tax inputs are reviewed, and Tomorrow follows dashboard row styling.
Profit per job remains outside scope.

Four additive migrations are deployed with matched SQL hashes. Full Flutter
suite: 1,133 passed; final payment-enabled/timezone subset: 83 passed; SQL:
1,009 assertions passed. Hosted checks and fixture cleanup passed. Normal
signed build **1.0.0 (17)** is installed and launched on the owner's iPhone,
with their sign-in retained. No build-17 TestFlight or external distribution
occurred. Native PDF/picker cancellation is verified; actual camera capture
is restricted by iPhone Mirroring and remains a handheld check.

See [the full review, files, evidence and limits](releases/2026-09-08-business-workflow-review.md).

## 8 September 2026 — Build 18 document, receipt and Money refinement

Documents now open inside Workloop before sharing. Receipt photos/PDFs offer
locally extracted details for review; uncertain values retain manual entry.
Money prioritizes unpaid balances, cash figures and recent activity before
planning/setup. Shared external labels fix tax and invoice field presentation.

The owner's fresh-signup problem was traced to a pending deletion blocked by
Stripe Standard-account closure. After explicit approval, the deployed endpoint
now verifies OAuth disconnection for that provider-specific case before deleting
local data. The old Auth identity and workspace are confirmed removed. No schema
or access-policy change was required.

Full Flutter suite: 1,190 passed with ten capability skips; all eleven separate
payment-enabled cases passed. Final analysis and 26 affected startup checks
passed. Eight real Vision fixtures, actual iOS simulator PDF/OCR integration and
Android native compilation passed. Native checks caught and fixed UIScene
channel registration and transparent-PNG recognition before installation.

The normal signed **1.0.0 (18)** app is installed and launched on the owner's
iPhone. CoreDevice confirmed build 18 and its process remained running after
launch. All 409 recorded source/asset hashes matched the pre-build manifest.
No TestFlight upload or external tester change occurred. Final physical screen
review was unavailable because Mirroring reported the phone in use; handheld
camera/HEIC/share and Android runtime checks remain separate limits.

See [the complete scope, files, evidence and remaining limits](releases/2026-09-08-build18-refinement.md).

## 9 September 2026 — Build 19 private beta release

The owner authorized releasing the reviewed features to the existing beta
testers. Build **1.0.0 (19)** was uploaded, processed, approved and is now
**Testing** in Workloop Private Beta for the existing **13 testers**, with the
existing internal group also assigned. TestFlight description, review notes and
What to Test were updated. No public App Store submission or new tester was added.

The app's only change after owner build 18 is the matching business-record/receipt
privacy disclosure and separate 9 September privacy date, plus the build number.
The full Flutter suite passed 1,190 tests with ten existing skips; analysis,
focused legal checks, required profile build and signed distribution build passed.
The original and exact uploaded IPA, frozen source and release evidence are saved
under `build/release-build19-20260909/app/`. The known vendor StripeTerminal dSYM
warning remains nonblocking; manual device and public-launch limits are retained.

The website's new feature copy, Money screenshots, privacy notice, metadata and
FAQ are live at workloop.uk. Existing pricing and access terms were preserved.
See [app release evidence](releases/2026-09-09-build19-testflight.md),
[website release evidence](releases/2026-09-09-website-release.md),
[read-only backend check](releases/2026-09-09-backend-release-check.md) and
[public privacy worksheet delta](releases/2026-09-09-privacy-disclosures.md).

## 9 September 2026 — Account-access hierarchy, local only

The sign-in and account-creation layout now uses an open brand row, clearer
welcome typography, shared gutters and space distributed above the form and
before the legal footer. Compact windows and keyboards remain scrollable;
account creation stays alongside the primary sign-in workflow.

Analysis passed, all 1,196 Flutter tests passed with ten existing skips, four
auth screenshot baselines were visually reviewed, and the local iOS profile
build passed. This refinement was not installed or uploaded. The owner asked
to hold TestFlight uploads and bundle the remaining tweaks into one release;
source version `1.0.0+19` is unchanged. See [files, previews and verification
limits](releases/2026-09-09-auth-hierarchy-local.md).

## 9 September 2026 — Welcome organiser, local only

The welcome screen replaces its process diagram and repeated benefits list with
one illustrated organiser for the owner's day, clients and money. The shared
wordmark, paper panel, native artwork, typography and bottom action now follow
the same visual hierarchy as the revised account-access screen. Onboarding
steps and data collection are unchanged.

Analysis passed, all 1,197 Flutter tests passed with ten existing skips, and the
local iOS profile build passed. Light/dark screenshots and compact double-text
access were checked. No upload, installation or version bump occurred; both
screen refinements are held for the owner's next combined release. See
[files, previews and verification limits](releases/2026-09-09-welcome-organiser-local.md).

## 9 September 2026 — Onboarding service descriptions, local only

Onboarding now offers an optional multiline service description, preserves it
when editing or restoring a draft, and passes it through the save request. A
new migration writes it into the existing service-description column. The
editor uses shared labels above the inputs and owns its controllers until the
sheet is removed, resolving an exit-transition disposal race found by the
new interaction checks.

Analysis passed, all 1,204 Flutter tests passed with ten existing skips, both
service-editor previews were reviewed, and the iOS profile build passed. An
isolated 102-migration replay passed 63 SQL assertions. The new private function
body matches the hosted implementation except for the description insert;
security and the guarded public wrapper are preserved.

No deployment, installation, version bump or TestFlight upload occurred. Include
the migration before distributing the next combined app release. See
[files, previews and verification limits](releases/2026-09-09-onboarding-service-descriptions-local.md).

## 9 September 2026 — Complete onboarding week, local only

Working hours now shows all seven days in one compact table with Continue fixed
below it. Active-theme colours fix the light-mode contrast. Standard-size text
fits without scrolling on 320 × 568, 390 × 844 and 430 × 932 phone layouts,
including the onboarding header and safe areas. Larger accessibility text can
scroll the week while Continue remains available. Existing defaults, picker,
stored values and navigation are preserved.

Analysis passed, all 1,212 Flutter tests passed with ten existing skips, the
light/dark previews were visually reviewed, and the iOS profile build passed.
No installation, version bump, backend change or TestFlight upload occurred.
This joins the other local tweaks for the owner's combined release. See
[files, previews and verification limits](releases/2026-09-09-onboarding-hours-local.md).

## 9 September 2026 — Consistent theme changes, local only

The app's mutable compatibility colours could leave dark panels or icons behind
after switching to Light. A mounted-screen pixel test reproduced the fault.
Compatibility colour reads now resolve immutable values from the local Theme;
all 47 existing colour pairs are preserved. Open forms and shared surfaces keep
their controllers, focus, selection and unsaved edits. Sheets/dialogs follow
their local theme, and date pickers no longer force a dark colour scheme.

Analysis passed, all 1,218 Flutter tests passed with ten existing skips, and the
local iOS profile build passed. The 26 focused tests include repeated manual and
pure System changes on mounted screens, an open service editor and date picker.
One reviewed dashboard Light baseline was corrected because it contained stale
dark-mode icons; the other baselines were retained and the full comparison passed.

No deployment, installation, version bump or TestFlight upload occurred. This
joins the held local tweaks for the owner's combined release. See
[files, root cause and verification limits](releases/2026-09-09-theme-switch-local.md).

## 9 September 2026 — Refined Dark palette, local only

Dark now uses deep charcoal layers, soft ivory text, quieter blue-grey frames
and powder-blue accents. Warm status colours remain restrained. The existing
Light palette, layout, typography, workflows and immutable theme-switch behavior
are unchanged. Native dark launch backgrounds match the new canvas.

Analysis passed, all 1,221 Flutter tests passed with ten existing skips, and the
local iOS profile build passed. Contrast and mounted-screen state checks passed.
After visual review, 33 Dark baselines were accepted; all 41 other screenshots,
including every light-named baseline, remain byte-identical. The full screenshot
comparison then passed. No installation, version bump, deployment or TestFlight
upload occurred; this is held with the other tweaks for the combined update.
See [previews, files and verification limits](releases/2026-09-09-dark-palette-local.md).

## 12 September 2026 — Connected app polish, attachments and document workflows

Bookings, notes and clients now share private camera/photo/file attachments and
in-app JPEG/PNG/WebP/PDF/text viewing. Note editing preserves one saved identity
across attachments and retries. Client/task/document links return to the right
record, stale workspace data cannot expose actions, and failed payment balances
offer recovery before collection. Quote/invoice actions, dates, VAT labels and
deposit conversion now follow the corrected document workflow.

The three attachment/deposit/receipt-role migrations are live, and the updated
account-deletion worker is ACTIVE at version 35. Live privileges, private bucket
settings and deployed function sources were checked. Security Advisor findings
did not increase. Analysis passed; all 1,326 Flutter tests passed with one
configuration skip; SQL checks passed 49 assertions and two Edge cleanup tests.
The signed iOS profile build 1.0.0 (19) installed and launched on the iPhone
15 Pro Max. No TestFlight upload occurred. The real checkout matched 826 verified
inputs from the isolated build used to avoid another task's build-directory race.

Live card collection still requires Stripe account onboarding: no connected
payment-account rows were present at verification. Native capture/sharing,
authenticated live file upload and real customer delivery/payment journeys are
separate remaining checks. See the [changed files, decisions, evidence and
scope limits](releases/2026-09-12-connected-app-polish.md).

### 2026-09-12 — Booking reminder settings without a chat promise

Settings and Business now call the existing destination **Booking reminders**,
with a calendar/clock icon and **Automatic email · Manual WhatsApp** subtitle.
Customer conversations and replies are explicitly handled outside Workloop.
Automatic email timing, booking updates/contact details and manual WhatsApp
guidance are separated. A saved-selection summary and one-tap email-reminder
off action use the existing workspace preference, with guarded saves and no
change to customer enrollment or delivery rules.

This is local source work for a future combined build. See the
[change and verification receipt](releases/2026-09-12-booking-reminder-settings.md)
for file reasons, checks and the remaining device-validation boundary.

### 2026-09-12 — Compact Money overview

Money now groups net profit, received and spent in one cash panel. Profit trends,
payment history and expense categories open on demand. The monthly goal and card
settings use flat rows, and changing Money sections returns to the top. Existing
records, calculations and payment setup remain intact. See the
[layout and verification receipt](releases/2026-09-12-compact-money.md).


### 2026-09-12 — Required and optional form information

Forms now show persistent Required/Optional labels that follow their existing
save rules, including conditional VAT/deposit/receipt requirements and draft
versus issue guidance. The client form explicitly says only a name is required.
Shared wording supports enlarged text and assistive technology. Compact sign-in
spacing preserves the standard-phone fit; working-hours guidance clarifies that
all days may be off and enabled blocks must have valid ordered times.

Analysis passed; 1,349 Flutter tests passed with one skipped. Eleven reviewed
form appearance references passed in the final suite. The development-signed
iOS profile build succeeded. This is local source/build work; physical form
entry and manual assistive-technology review remain follow-up checks. See the
[files, reasons and verification receipt](releases/2026-09-12-form-requirements.md).


## 12 September 2026 — Apple trial journey

The approved public model is one Apple calendar month free for eligible new subscribers, then £14.99/month with automatic renewal. Customer screens, pre-setup gating, native eligibility, renewal/cancellation details, restore recovery and service-email reminders are implemented. Backend preparation is deployed with beta preserved and sales/enforcement/reminders still off. Full Flutter verification: 1,411 passed, one skip, analysis clean, signed iOS profile build passed. Public release remains paused; build 20 is older than this change. See `releases/2026-09-12-apple-trial-customer-journey.md` and its backend receipt for evidence and activation gates.
