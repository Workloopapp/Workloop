# One-month Apple trial and customer journey — 12 September 2026

The owner approved a one-month Apple introductory free trial that renews automatically at the current UK price of £14.99 per month unless cancelled. Public release remains paused. This supersedes the planned new-account 30-day no-card trial and the annual offer for new customers. An Apple calendar month follows the signed store dates, not a fixed 30-day calculation.

## Customer experience

- The existing subscription gate now comes before business setup. New customers see Workloop’s connected client/work/payment benefits, the store’s local monthly price and renewal terms before authorising with Apple. Verified access continues directly into the existing onboarding and first-use guide with a brief confirmation. No demo records or second onboarding system were introduced.
- The free-trial button appears only when native StoreKit confirms both the exact one-month free introductory offer and eligibility. Eligibility is rechecked before checkout. Unknown/ineligible customers see ordinary monthly terms; the Apple confirmation sheet remains authoritative. A changed offer stops checkout for another review.
- Only the monthly plan is offered to new purchasers. Historical annual receipts remain verifiable and restorable. Existing lifetime beta access and any already-started legacy trial are preserved.
- The account plan screen distinguishes active free trial, paid access, renewal turned off, unknown renewal status and payment retry. It displays verified end/renewal dates and the current native monthly price without claiming that today’s catalogue price is a legacy subscriber’s exact renewal amount.
- Restore, support, embedded terms/privacy, Apple management/cancellation and account export/deletion/sign-out stay available. The trial disclosure explains cancellation at least 24 hours before expiry and that deleting the app/account does not cancel Apple billing.
- Seven- and three-day reminder emails are implemented in the existing scheduled backend worker. The UI promises those emails only when the verified backend capability is enabled. That flag remains off pending controlled delivery verification. No customer reminder was sent by this work.

## Engineering and changed files

- `lib/features/subscription/store_purchase_service.dart` and `store_trial_offer.dart`: native metadata/eligibility, monthly catalogue, stale-product rejection, signed verification, pending-purchase protection and restore recovery. The already installed StoreKit 0.4.12 package is now a direct dependency at the same version.
- `subscription_screen.dart`, `subscription_plan_widgets.dart`, `subscription_access.dart`, `subscription_gate.dart`: value-first offer, timeline, account states, lifecycle refresh, expiry guards and successful handoff. Existing shared Quiet+Warm components and design tokens were reused.
- `lib/main.dart`: apply the same keyed gate to both new and existing workspaces; preserve account isolation, drafts and first-use timing.
- Embedded legal documents, `WorkloopAppInfo` effective dates and app `web/` legal copies: clear auto-renewal/trial/reminder disclosure dated 12 September 2026.
- Backend schema, verifier and reminder worker: see the separate [deployment receipt](2026-09-12-apple-trial-backend.md). The deployed additive migration is 20260912151753; subscription function v3 and scheduled worker v34. Existing 17 lifetime accounts retained access. Production sales/enforcement and reminders remain disabled.
- The separate marketing website checkout has six reviewed source changes covering terms/privacy, shared pricing, homepage/pricing wording and the existing rendered-HTML tests. Its public design and launch-list navigation are preserved. Those website changes are prepared locally, not published; public rollout must publish them alongside the compatible app.

## Verification

After sourcing `scripts/dev_env.sh`:

- `flutter analyze`: no issues.
- Full `flutter test --dart-define-from-file=.env`: **1,411 passed, one existing skip**. Two initial failures were old legal-date assertions; those assertions were updated to the intended 12 September effective date and the entire suite rerun successfully.
- `flutter build ios --profile --dart-define-from-file=.env`: passed, signed 80.6 MB app bundle. This is a local profile build; it was not uploaded or installed on a physical phone in this pass. Root version remains 1.0.0 (19); uploaded build 20 predates this implementation and must not be submitted as containing it.
- Six subscription golden images were inspected before refreshing their expected images, including eligible offer in light/dark, active trial, cancelled renewal, lifetime beta and compact large-text error. 22 independent journey tests cover 320px/2x text, eligibility, local pricing, cancellation, unavailable metadata, resume, expiry, account controls and verified handoff.
- Backend: 138 SQL assertions and 71 distinct Deno tests, Edge import checks, deployed source parity and protected endpoint probes. These are separate from real Apple receipt/purchase and email delivery evidence.
- Website: existing production build and all 44 tests passed in an isolated copy of tracked source plus the reviewed edits. User-owned untracked backup files stayed untouched and were excluded from that candidate.
- `git diff --check`: passed. No source commit/push or new public app submission was made.

Evidence: `build/subscription-trial-20260912/`, `build/subscription-backend-20260912/`, and subscription goldens under `test/golden/files/`.

## Remaining activation gates

The Apple monthly product and trial are saved as recorded below. Paid Apps Agreement/banking/tax, real native purchase/restore/cancellation/refund testing, a controlled reminder delivery test and an explicit isolated Sandbox/App Review access path remain activation gates. Sandbox receipts intentionally do not grant Production account access. App Review purchases use Sandbox, so the review path must be resolved before enforcing a public paywall. Never turn off beta/open production sales merely because mock tests passed.

Apple currently refuses disabling streamlined outside-app purchasing because no latest approved binary includes its required APIs. Preserve that as an explicit first-approval prerequisite, verify native purchase-intent handling and retry the setting after an appropriate binary is approved. Do not promote outside-app offers until account association works.

The updated website copy and a newly numbered compatible app candidate must be part of the coordinated release. Public release stays paused until the owner resumes it.

Suggested commit: `feat: add Apple free-trial subscription journey and renewal reminders`

## Apple configuration receipt — 12 September 2026

Verified through App Store Connect for Workloop app **6800472527**, subscription group **22364660** and monthly subscription **6809246089** (`workloop_monthly`):

- Saved the UK base price at **GBP £14.99/month**. Apple calculated equivalent prices for other storefronts; availability remains **United Kingdom only**.
- Saved the UK introductory offer **Free for the first month**, available **12 September 2026 to No End Date**. This is an introductory offer for eligible Apple accounts, not a new free month on every reinstall or account creation.
- Saved English (U.K.) product localisation: **Workloop Monthly**, description **Your clients, bookings, work and money in one place.** Saved the subscription group's English (U.K.) display name **Workloop**, using the app name.
- Saved and independently read back both Production and Sandbox server notification URLs as `https://imtbyrvsonzvtddswbtb.supabase.co/functions/v1/workloop-subscription/apple-notifications`. This proves configuration only; no real signed Apple notification has been received as part of this work. The current Apple form exposed no notification-version selector, so no separate version-selection action is claimed.
- Apple refused the attempt to turn off streamlined purchasing: the latest approved binary does not include its required StoreKit APIs. The setting remains on. See the prerequisite above.
- Final Business-page readback: Free Apps Agreement **Active**; Paid Apps Agreement still **View and Agree to Terms**. The owner has been asked to accept the legally binding agreement and complete Apple's banking/tax requests. Compliance setup also remains visible. The earlier accepted Developer Program agreement is a separate account step.

No subscription review screenshot, product submission, new app upload, public app submission or billing activation was performed in this pass. Saved product configuration does not establish Apple approval or actual checkout availability.

## Owner resumed release preparation — 12 September 2026

The owner subsequently said, “ok lets do it. what do you need from me”. This resumes the public-release work and supersedes the earlier pause. It does not establish that the remaining purchase, review-access or delivery checks have passed, so billing activation still follows those checks.

Live App Store Connect was reopened. During this follow-up, the Paid Apps Agreement changed from **View and Agree to Terms** to an effective agreement dated **12 September 2026–11 August 2027**, status **Pending User Info**. The owner completed the acceptance; the assistant did not accept it. Apple now shows **Add Bank Account** and the **U.S. Tax Questionnaire — Missing Tax Info**. Those payout and tax details are the current owner action. Free Apps remains **Active**. EU compliance setup is still displayed separately; the monthly subscription remains UK-only.

The owner has been directed to enter the account details directly in Apple. A read-only technical review of the smallest safe Sandbox/App Review access path is running alongside that setup. No new upload, public submission, entitlement activation or reminder sending occurred during this account-status check.
