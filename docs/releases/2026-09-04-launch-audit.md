# Workloop launch audit and implementation — 4 September 2026

Latest verification: 21:42 BST. This dated result supersedes earlier candidate status; earlier records remain preserved.

## Plain-English verdict

Workloop is substantially improved and the new iPhone beta is available now. The main workflows, website booking bundles, payment safeguards, notifications infrastructure and operational reporting have received concrete repairs. This is not yet evidence of a public-launch-ready product on both platforms.

The critical external path is now Android: this is a new personal Google Play account, registration is unfinished, and Google requires a physical Android verification device and a qualifying closed test before production access. Card collection also requires a genuine verified merchant and a successful charge/refund journey. Clearview is a fictional demo and must not be activated with invented details.

## What is actually running

| Surface | Verified state | Important boundary |
| --- | --- | --- |
| iPhone TestFlight | 1.0.0 (10), uploaded 4 September at 21:22 BST, approved, external state IN_BETA_TESTING, assigned to Workloop Private Beta (13 testers) | Two tester entries were observed on Build 10; the other eleven still showed Build 6. Availability and installation are different. |
| Physical iPhone | Signed profile Build 10 installed and successfully launched on the connected iPhone 15 Pro Max | This is development/APNs sandbox validation, not proof of every TestFlight workflow or production push delivery. |
| Android | Signed versionCode 10 AAB built; exact derived APKs installed and cold-launched on Android 16 ARM64 emulator; Firebase initializes and login renders without payment-reader errors | Not uploaded to Play; no physical Android device is available. |
| Supabase | London production project imtbyrvsonzvtddswbtb active; reviewed migrations/functions deployed; recent worker requests return HTTP 200 | Database and worker health do not prove all end-to-end customer journeys. |
| Resend | Sender domain verified, receipt processing repaired; 24 retained webhook receipts replayed and recorded | Three historical bounces remain historical failures. No email was resent and no new private-relay delivery is claimed. |
| Marketing website | Version 28 published and checked at https://workloop.uk | Public booking bundles work in the live form; no dummy booking was submitted. |
| Workloop OS | Private owner-only version 15 published and checked at https://workloop-os-hq.ismaeelsmiley.chatgpt.site | Live GitHub, Supabase, TestFlight and local runner signals; Analytics is not connected and several other integrations remain planned. |

## Repairs delivered

### Booking and everyday use

- Added real selection of multiple existing services, with eligible extras, to the Flutter workflow and public website. Maximum eight services and eight extras; server validates membership, active catalogue entries, money and total duration.
- Immutable item snapshots preserve the requested names, prices and duration when a business later changes its catalogue. Legacy single-service requests remain supported during the beta update.
- Availability considers the complete visit. Changing services clears the previously selected time. Live website verification combined Conservatory Roof Clean (£120, 120 minutes) and Regular Round Visit (£22, 30 minutes) into £142 and 150 minutes.
- Corrected confirmation handling for combined titles, totals and longer bookings, including the supported 5–1440 minute range.
- Bounded best-effort push-token cleanup during sign-out so an offline network does not hold the user in the app indefinitely.
- Polished shared controls, touch targets, spacing, working-hours layout and schedule warnings, with narrow-screen, large-text, theme and golden regression coverage.

### Card collection and notifications

- Enabled hosted card collection in Build 10 while keeping device Tap to Pay explicitly disabled. Hosted links can satisfy the card-collection workflow once the actual business is verified.
- Added payment reservations/idempotency, safer retry handling, duplicate/overlapping collection protection, exact-penny validation and authoritative Stripe reconciliation for out-of-order events and refunds.
- Kept account, mode, currency, amount and metadata checks around provider events; card-only Checkout remains the supported collection route.
- Fixed Android eagerly starting Stripe Terminal at sign-in. The replacement AAB only starts the reader when a collection operation actually needs it; the original startup error is absent on the tested replacement.
- Added per-token APNs environment routing and FCM delivery support, safe token ownership transitions and provider retry handling. Android Firebase app/configuration and upload signing are now present.
- FCM server credential creation is still awaiting the separately requested permission. Android remote notifications are therefore not yet operationally verified.

### Backend and email operations

- Repaired the notification routing function's missing default case, which broke the morning-digest scheduler.
- Repaired the Resend receipt authorization path and replayed retained provider events. Reporting now separates an accepted send from actual delivery or bounce.
- Registered workloop.uk and send.workloop.uk with Apple's private email relay; both show verified SPF. A fresh controlled relay email still needs validation.
- Confirmed explicit membership checks protect public service-role endpoints. Eight ownerless workspaces with 29 services are retained, rather than destructively removed; they are not treated as eligible public businesses.
- Recent production evidence: 60 email-worker cron successes and 60 HTTP 200 worker responses in the last hour, 26 sent outbox rows and no queued emails. Recorded provider events comprise 12 sent, nine delivered and three bounced receipts; these are event counts, not 24 distinct emails.

### Websites and Workloop OS

- Published the marketing booking changes to the actual custom domain, with combined price/duration and fresh availability verified in the browser.
- Patched React/React DOM/RSC to 19.2.8 and Vite to 8.0.16 on both websites. Marketing also uses Next/eslint-config-next 16.2.11 and a targeted PostCSS 8.5.23 resolution.
- Workloop OS now separates latest upload, external beta state and data coverage. Its 100% connected-source coverage explicitly does not mean public-launch readiness or universal tester installation.
- Failed source refreshes clear stale success/data rather than leaving a green result visible. Provider email failures now reach the business pulse.
- Updated the installed local preparation runner to 1.2.0. Prepared changes must pass isolated analysis/tests and unchanged-source checks before an approved apply. Heartbeat confirms the new runner is online. A real approved apply journey remains separately unproven.
- Workloop OS currently reads remote GitHub main at 07ecb37. The new mobile release commits are retained locally; that remote signal must not be presented as the new release source.

## Exact release provenance

The original dirty checkout and Build 9 archive/IPA were preserved. Initial source backup: `/Users/ismaeelsmiley/.workloop-release-backups/20260904-204036`. No broad reset or forced overwrite was performed. Mobile release snapshots have clean local commits and file-hash manifests; they were not pushed to GitHub by this task.

| Artifact | Exact source | Location / SHA256 |
| --- | --- | --- |
| iOS Build 10 retained IPA | 31b190d3f21249dc5c0dff60885da3f62a6ea47d | `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201205Z/Workloop/build/ios/ipa/Workloop.ipa`; eebf0dda5f2ee2f61e4dacb691671a9efc886d9a32e1c7c7b4da78ecb01b7746 |
| Final Android Build 10 AAB | d3f9211474304f59d53c9a44b1a639a050fa45b8 | `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T203101Z/Workloop/build/app/outputs/bundle/release/app-release.aab`; cdda5308e7bae3fd274b4ab1ea569908eabcf7bad13575f97a4ae22af3a3a908 |
| Marketing Sites v28 | fb4d0dd7b117d0a9bedf3d7b80eb059b6ca9e84b | workloop.uk, live bundle controls verified |
| Private Workloop OS Sites v15 | a1a102aa8054a31b378d3f8ffe569fe51b1a1880 | owner-only live site, Build 10 IN_BETA_TESTING verified |

The upload used a new distribution export of the verified iOS archive; the retained local IPA hash is not claimed as a downloaded Apple-processed binary hash. Actual bundle/version, production APNs entitlement, signature and provisioning were independently inspected. Apple accepted the upload with a non-blocking missing StripeTerminal framework dSYM warning; native SDK crash symbolication is limited for that framework.

The final Android source differs from the uploaded iOS source only in Android Firebase configuration and lazy native Terminal initialization. Both builds enable hosted card collection and disable Tap to Pay. Android bundle signature, version, Firebase resources and all 17 included 64-bit native library alignments passed; the four installed emulator APK hashes match their generated bundletool outputs. Hardware/NFC behavior is not covered by this emulator evidence.

## Verification results

| Check | Result |
| --- | --- |
| Flutter analysis | Clean |
| Full Flutter unit/widget suite | 475 passed, four feature-gated skips; separate payment-enabled checks passed |
| Focused UI/accessibility/golden checks | 62 passed during the polish pass |
| Deno tests | 89 passed |
| Release-tool regression tests | 11 passed |
| Signed iOS profile build | Passed; installed and launched on connected iPhone |
| Signed iOS distribution and Apple upload | Passed; external Build 10 is IN_BETA_TESTING |
| Signed Android AAB and exact-derived emulator startup | Passed, including the startup regression recheck |
| Database clean replay | 80 app migrations, 17 suites, 393 assertions; including four OS migrations gives 84 migrations, 18 suites, 413 assertions |
| Marketing website | 19 tests passed; TypeScript, focused lint and production build passed; live form verified |
| Workloop OS | TypeScript and production build passed; App Store adapter test, six runner tests and 20 pulse database assertions passed; live site verified |

Database replay used isolated PGlite PostgreSQL 18.3, actual roles/RLS/PLpgSQL and controlled auth fixtures. Production is PostgreSQL 17.6. Cron/vault metadata are stubbed; this does not exercise real GoTrue, PostgREST, pg_net, external providers or concurrent network requests. It is meaningful clean SQL/RLS regression evidence, not a replacement for hosted staging E2E.

Key verification logs are retained privately at `/Users/ismaeelsmiley/Workloop-Releases/verification-20260904`, with additional working logs under `/tmp/workloop-*`, durable release manifests and Android startup evidence beside the release snapshots. Detailed chronology is in [build verification](2026-09-04-build-verification.md).

## What still prevents public launch

1. **Google Play account and test gate.** Finish the new personal developer account, identity/payment profile, agreements and registration fee. Verify it using a real non-rooted Android 10+ phone; a borrowed phone is acceptable, an emulator is not. Upload the signed AAB, complete app declarations/listing and establish at least 12 continuously opted-in closed testers for 14 days before applying for production access. The clock has not started in the observed account. This rules out a both-platform public launch within the next few days. [Google testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB), [device verification](https://support.google.com/googleplay/android-developer/answer/14316361?hl=en).
2. **A genuine merchant and money-flow validation.** The only connected Stripe account is fictional Clearview, restricted with business/representative/bank/agreement requirements and no transactions. Use a real business owner's details through Stripe-hosted onboarding. Then validate card success, decline/cancel, repeat taps/retry, webhook reconciliation, refund and receipt delivery. No real charge or refund has been made by this task.
3. **Notifications on actual devices.** Approve the prepared dedicated FCM service account/role/secret configuration, then validate Android foreground/background/terminated delivery and tap routing. An iPhone Build 10 sandbox token registered, but no fresh production-APNs delivery or full device notification journey is claimed.
4. **Disposable hosted journeys and final manual QA.** Auth confirmation/recovery/restart/expiry, two-account SDK isolation, public booking through owner acceptance, deletion and full business workflow require an isolated hosted test environment/accounts. Physical iOS/Android accessibility, upgrade, offline and deep-link checks remain open. No destructive production deletion test was performed.
5. **Public store/operational readiness.** Complete App Store public submission and Google declarations/review, genuine operator/legal/support details, support monitoring and a reliable offsite encrypted upload-key backup. Full crash-monitoring integration and load-test evidence are still absent; Apple beta feedback and clean automated tests are not substitutes.
6. **OS integrations remain partial.** GA4 needs its own Google OAuth configuration/consent. Gmail, Notion, Canva, Stripe and Meta connections shown as planned are not working integrations. They are not required to make the mobile app's basic workflow operate, but the private OS must continue describing them honestly.

Residual web dependency warnings are documented in [dependency audit](2026-09-04-web-dependency-audit.md). The exposed React parser dependency was patched. Remaining development-tool warnings are not waived as nonexistent, and a zero-vulnerability claim is not made; larger framework/toolchain upgrades need separate compatibility testing.

## Request coverage and change ownership

[Recent-request coverage](2026-09-04-request-coverage.md) traces the prompts that could be retrieved and the implementation/delivery gaps found. Its dated closure note records subsequent fixes. This audit does not claim access to every historical prompt or that all possible bugs have been eliminated.

Key changes are grouped by reason: Flutter booking/auth/shared controls for user workflow correctness; payment/push repositories and Edge functions for reliable delivery and collection; reviewed SQL migrations for notification routing, receipts, bundles, push and payment reservations; native Android Firebase/Terminal configuration for production packaging and startup; release scripts/CI for explicit real configuration and artifact identity; marketing form/helpers for customer bundles; OS data adapters/runner for truthful status and verified preparation.

The root checkout retains existing and new uncommitted work. Review and commit in focused groups rather than blindly committing the whole accumulated checkout. Suggested umbrella commit message: `fix: harden booking, payments, notifications and cross-platform release readiness`.
