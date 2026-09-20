# Launch preparation — 7 September 2026

This pass implements the owner’s overnight request. Build 12 remains the last verified external TestFlight release until a later receipt is appended. Public release is not authorised for tonight; one more week of beta testing is planned.

## Implemented and verified backend

- Thirty-day trial: exactly 720 hours from first accepted account-access check after beta closes, without payment details or automatic trial charging. Then native store subscription selection: planned £14.99 monthly or £149.99 yearly. Purchasing/paid enforcement remain off pending real StoreKit verification and provider setup.
- Hosted `workloop_subscription_access` migration applied on 6 September 23:14 UTC. Fifteen existing verified non-QA users have server-owned lifetime beta access. Beta remains open; later verified beta entrants receive the same grant. Authentication, MFA and active-session checks protect access. Account ownership, renewal/refund/grace ordering and Sandbox isolation are covered by tests.
- `workloop-subscription` Edge v1 active with explicit user/JWS authentication. Unsigned account calls return 401; missing/forged Apple notifications return 400. Real Apple receipt acceptance is not verified.
- `stripe_payment_received_notifications` migration applied on 6 September 23:20 UTC. Two active triggers, private RLS ledger, zero app-table grants. No historical owner notifications or customer emails/pushes sent. Successful future reconciled card collections create one owner alert opening the exact payment.
- `create-booking-request` v31 contains strict zoned timestamp validation; `join-waitlist` v17 and `drain-booking-confirmation-emails` v32 contain corrected pricing.
- Full isolated schema replay: 94 migrations, 27 suites, 805 SQL assertions. Auth/cron/Vault metadata are documented PGlite fixtures; this does not replace real provider tests. Subscription additionally passed 62 PostgreSQL-container assertions and 36 Deno tests. Email/operator templates passed 7 Deno tests.

## App

Booking-request acceptance preserves the requested instant through DST folds and uses the workspace timezone. Shared sheets now use one consistent surface, reachable scrolling and safer save/dismiss behavior; repeated haptic events were removed. Regular-client follow-ups use observed visit intervals, suppress already-booked/contacted clients, and can be snoozed. The surprise 'Ready for tomorrow' row links directly to actual upcoming bookings.

Subscription client tests cover failed/forged receipts, stale account/session work, duplicate/replayed purchase events, pending payment approval, restored purchases, acknowledgement retries, elapsed expiry and accessible account/export/delete controls. 47 focused client/settings/golden checks passed, including four reviewed plan visuals. Backend enforcement remains independent of the client. Google billing is not implemented/enabled.

Apple ITMS-90683: both foreground and Always-symbol purpose strings are present, explaining foreground weather/payment usage and no background tracking. Geolocator’s Swift Package includes the Always API symbol; Workloop continues requesting When In Use and has no background-location mode. Release artifact verification now checks this directly.

## Website / SEO

Public website version 35, source `9ae5f10585d7b9e39cfd96d425e488012c8035c3`, published. Correct launch pricing, lifetime beta promise, subscription terms/privacy, proportional current 390×844 product screenshots, three practical guides, navigation/internal links, article/breadcrumb schema and sitemap changes. Twenty browser checks across 320/390/768/1440px found no overflow, browser exceptions, missing product images or distorted screenshots after normal lazy loading. 25 production-render tests, lint and TypeScript passed. Real `workloop.uk` browser checks confirmed HTTP 200, canonical URLs, revised pricing, all three new guides and the product image.

Google Business Profile was not created: Workloop is an online-only service and does not meet Google’s in-person business eligibility. Free directory/editorial materials are prepared in Documents/Workloop Website Review/2026-09-06-launch; no paid listings, reciprocal-link schemes, submissions, outbound pitches or backlinks are claimed. Search Console indexing submission awaits an accessible authenticated session.

## Private Workloop OS

Owner-only version 19, source `1c00829146339287984a7ba0eb2246966ab93f81`, published to the existing private audience. Atomic owner-scoped approval decisions; full paged queue with actual request/summary; independent cancellable source refresh; explicit unavailable/loading states; corrected Google configured-versus-verified labels; stable server/client date and automatic day refresh. Fifteen tests, clean lint/types/build; browser tests at 390/1440px verified twelve-item pagination, disabled decisions on error, no overflow/exceptions. No schema/scope/auth changes. Direct requests without a valid viewer return 401; an owner-authenticated hosted workflow awaits Mac unlock.

## External launch gates

- Finish Apple monthly/yearly store price/localisation/review metadata, notification URLs and genuine Sandbox purchase/restore/renew/refund. Monthly product `workloop_monthly` exists with 1 month duration and UK availability; annual product/prices are not yet verified. Mac lock blocked Safari controls. Never enable billing based only on synthetic receipts.
- Complete Apple public app review/listing/account agreements as applicable. Organisation conversion is pending independently; do not invent legal/tax attestations.
- Real verified merchant card collection/refund still required; fictional Clearview is not usable for live-money proof.
- Android Play registration/device/testing requirements remain. Respect the owner’s instruction to keep Google’s service-account-key security policy; Android push and billing stay pending.
- Physical iPhone validation and fresh signed-artifact/TestFlight receipt appended below when completed. No public App Store release or extra release email claimed by this report.

## Final verification notes

The first full Flutter run found an intentional booking-request detail golden change and two test doubles missing the existing AuthRepository.currentUserId getter now read by the subscription wrapper. The new booking-request rendering was visually compared with its baseline before updating only that golden. The fake now mirrors the real SDK current-account lookup; no production authentication behavior or timing assertions were weakened. Seven focused session/draft tests passed afterward. Final full-suite result will be appended after completion.

The authorised free Codex usage reset was redeemed once as account usage approached its limit. No paid credits were purchased.

### Final source checks, 7 September 00:38 BST

After the final purchase-state review, an empty/failed Restore or temporary store connection error preserves a payment awaiting approval; a terminal store event resolves it. Three regression cases were added. Date/time pickers now complement the framework-provided haptics by platform instead of producing duplicate pulses. Final `flutter analyze` passed and the complete Flutter suite passed **984/984**, with production payment collection enabled. The profile build also explicitly enables the subscription client; paid sales/enforcement remain controlled by the disabled server switches. Signed artifacts, installation, physical behavior and TestFlight processing remain separate checks.

The fresh Supabase security advisor had **zero errors**, six existing warnings for authenticated SECURITY DEFINER functions and 24 informational private-table RLS notices. These are not described as zero warnings; the existing functions retain authentication/MFA/workspace checks and private ledgers have no ordinary app-user grants. The latest post-deployment worker returned HTTP 200 with no delivery failures. Live website SEO checks passed 28 URLs, a 24-page sitemap and all three new article metadata/canonical checks. Authenticated search indexing and new backlinks are still not verified.

The iOS profile build completed successfully at 00:40BST with payment collection and subscription UI enabled (76.2 MB). This is compilation/signing evidence; device installation/launch and interaction are recorded separately.

### Signed iOS / Apple delivery, 7 September 00:48 BST

Isolated release snapshot: `Workloop-Releases/build13-20260906T234037Z/Workloop`, commit `87e332ca8b88939fd6c52cf0088387ea62ffc9df`. All 1,043 source files were copied with verified hashes without committing or resetting the original working checkout. Public configuration enables payments, crash reporting and subscription UI; APNs production; Tap to Pay off. Runtime secrets/config remain ignored.

Signed 1.0.0 (13) IPA: 35,827,864 bytes, SHA256 `0a10dca51324e00fe4fb06c4fbf39357ca2bc85ee850010cb3411ba54285d851`. Artifact validation confirmed bundle/version, both location purpose strings and no background-location mode. Apple upload returned **EXPORT SUCCEEDED**, with processing started at 00:48:12BST. External tester availability is not yet verified; public release has not occurred. Build12's earlier user email was not sent again.

Physical device inventory independently confirms installed 1.0.0 build 13. Launch returned Locked/RequestDenied; visual, keyboard, notification-tap and physical-haptic checks are still pending. Installation is not represented as a successful launch.

The remaining nonblocking StripeTerminal dSYM warning is upstream: Stripe removed bundled symbols in 5.0.0, and its verified 5.7.0 release asset has no dSYM or separate symbol asset. The shipped arm64 UUID matches Apple's warning. This affects symbolication inside that vendor framework, not Workloop's own debug symbols. Dependency/archive were not changed after upload. [Stripe release notes](https://github.com/stripe/stripe-terminal-ios/releases/tag/5.0.0).

Website version36 preserves the pricing/content/screenshots from 35 and adds a public IndexNow ownership file plus a manual verified submission helper. Eight focused checks, lint and production build passed. All 24 public canonical sitemap URLs were verified and submitted once; HTTP 202 means ownership validation pending, not indexing, ranking, backlinks or Google Search Console completion.

The Android compiler generated a `.kotlin/sessions/*.salive` cache; the isolated snapshot locally excludes that generated directory. The original checkout now ignores `/android/.kotlin/` for future clean builds. No product source changed after the signed snapshot.

### Android artifact, 7 September 00:53 BST

The same clean source commit produced the signed Android App Bundle, 99,278,171 bytes, SHA256 `cdf82d22a482b72b726c7de084639b17c99c2a0594e633b8ec8093cac444230f`. Bundletool validation passed; manifest confirms com.ismaeel.workloop, version1.0.0/code13, minimumSDK26/targetSDK36. JAR signature verification passed with Android's self-signed-certificate/no-timestamp warnings and recorded streaming-entry-order warnings; no clean Play acceptance is claimed. All twelve arm64 native libraries' load segments meet16KB alignment. This is artifact inspection, not execution on a physical Android phone or store acceptance. Google Play registration, billing and push configuration remain pending, and no Google policy exception was made.

The release evidence JSON and signing reports are preserved alongside the isolated candidate in `Workloop-Releases/build13-20260906T234037Z`. No public release, new directory/backlink, repeated user email, live card charge or paid subscription activation occurred in this closing pass.

### Migration metadata maintenance boundary

Hosted history has98 entries:88 exact app matches, six same-name/different-timestamp app entries, and four intentional Workloop OS entries. The newest subscription SQL is byte-identical to the deployed body; Stripe differs only by the deployment lock-timeout prefix. No missing deployment or new schema discrepancy was found in this metadata check. A future CLI deployment must reconcile the documented histories before db push; do not force include-all or mark hosted entries reverted. See [the exact mapping and safe maintenance handoff](2026-09-07-migration-history-handoff.md). Separate repositories and the frozen mobile candidate were preserved; no migration was reapplied or schema changed by this check.

Android emulator smoke check: a universal APK derived from the exact release AAB and re-signed with the existing debug key installed over the earlier emulator build without resetting its data. Native startup, the sign-in screen, the shared More ways to sign in sheet and native Back dismissal were visually/semantically checked. No account was signed in, no email was sent, and this does not verify purchases, push delivery or authenticated app workflows on Android. The signed release AAB was not modified by creating this test APK.

## Key source areas and integration note

| Area | Main paths | Purpose |
| --- | --- | --- |
| Access and billing | `lib/features/subscription/`, `lib/main.dart`, account settings, subscription SQL/Edge function | Exact trial, lifetime beta access, store verification, safe purchase/restore states and accessible account controls. |
| Booking correctness | Appointment/request repositories, `booking_time` helpers, public booking Edge function | Preserve requested instants and workspace-local scheduling through date/time edge cases. |
| Shared presentation | `lib/shared/widgets/slate_ui.dart`, booking-request screens and form callers | One bottom-sheet surface, consistent scrolling/actions and platform-complementary haptics. |
| Useful follow-up | Dashboard/client follow-up and tomorrow-brief providers/widgets | Rebooking prompts grounded in actual visit history and tomorrow's useful next actions. |
| Release safety | `ios/Runner/Info.plist`, `scripts/release_config.py`, `pubspec.yaml`, `workloop_app_info.dart` | Required purpose strings, artifact identity checks and build13 metadata. |
| Public/private web | Separate marketing website and Workloop OS repositories | Correct launch content, current screenshots, SEO and reliable owner controls. |

Suggested integration commit message: `Prepare launch subscriptions, booking fixes and shared-sheet polish`.
The original app checkout remains intentionally uncommitted to preserve its earlier work. A clean, hashed release snapshot was committed separately for reproducible artifacts. Tests passed as listed; provider and physical-device limitations above remain explicit. Complete Apple store setup/real purchase tests and physical iPhone review before enabling paid public access. Use the next week for beta feedback rather than unrequested feature expansion.
