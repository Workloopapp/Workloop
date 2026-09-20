# Quiet + Warm rollout — 4 September 2026

The approved Quiet retro + Warm desktop direction is implemented in the app and published across Workloop-owned web, email and Stripe branding. iOS 1.0.0 (11) is **Testing** in App Store Connect and is available to the 13 members of Workloop Private Beta. Availability does not mean every tester has installed it.

## Surface coverage

| Surface | Result and evidence limit |
| --- | --- |
| Flutter app | Shared cream/powder-blue theme, brown outlines, window panels, restrained mono labels, original illustrations, readable warm dark appearance; Today, Clients, Work, Money, Business, forms, details, settings, onboarding and authentication use the new system. Existing workflows and navigation are retained. |
| Native identity | New icon and light/dark opening artwork installed in iOS and Android resources. macOS/web icons and Windows ICO also refreshed. Only iOS/Android were compiled in this rollout. |
| TestFlight | Build 11 processed and approved; assigned to Workloop Internal Beta and Workloop Private Beta. Existing automatic tester notification setting preserved. |
| Physical iPhone | Signed profile build 11 installed and launched successfully. This proves installation and process launch, not a complete physical-device feature matrix or visual inspection of every screen. |
| Android | Signed version-code-11 AAB produced. APKs derived from that exact bundle installed and cold-started on an emulator; new launcher and login were visually reviewed. No Play publication or physical Android validation. |
| Public website | workloop.uk published with the same visual system, original logos, seven actual current app screenshots, booking/payment-return pages, legal pages, favicon and social preview. Actual custom-domain asset hashes matched the reviewed files. |
| Private Workloop OS | Owner-only HQ published in the shared theme, retaining access controls and connected operational views. Mobile wrapping and desktop navigation controls corrected. |
| Auth/security emails | All 13 hosted Supabase Auth template contents updated and read back exactly. Subjects, flags and other Auth settings stayed unchanged. |
| Transactional emails | Welcome, waitlist, booking confirmation, deletion requested/completed and operational notices use the shared email presentation. Three caller/worker Edge functions deployed. Subjects, plain text and action links retained. Browser previews and automated checks passed; no manual live email was sent for this visual change. |
| Stripe | Platform icon/logo, Connect onboarding and hosted Checkout branding saved and verified. Stripe retains its own form structure and available typography. Merchant-specific branding is preserved. No bank, legal, onboarding or money movement changes. |
| Canva | Eight editable 1080 × 1080 brand master pages created and verified. Original scalable logo artwork, palette and type guidance included. |
| Social artwork | Circle-safe avatars and square, portrait, story, preview and cover exports prepared. User confirmed Instagram and TikTok @workloop.app. Instagram's new avatar is uploaded and visually verified with a successful-save notice. TikTok still requires completion of sign-in in the open browser tab. |

## Design and files

The shared implementation extends existing tokens, components, repositories and navigation. It does not rebuild functional modules. The reference is `docs/brand/quiet-warm-approved.png`; the implementation contract is `docs/brand/QUIET_WARM_IMPLEMENTATION.md`.

- `lib/core/theme/app_theme.dart`, shared slate/canvas/control widgets, `lib/shared/widgets/workloop_quiet_warm.dart` and feature screens: the cohesive app appearance, hierarchy and reusable native illustrations.
- `assets/brand/quiet-warm/`, font assets and native platform resources: original outlined Workloop window symbol, lowercase wordmark, accessible colour variants and platform-specific exports.
- `scripts/brand/`: reproducible vector generation, raster/platform export and distributable packaging. No additional app runtime dependency.
- `supabase/functions/_shared/` email renderers and `supabase/templates/`: visual identity without changing email delivery or authentication behaviour.
- `/Users/ismaeelsmiley/Documents/Workloop Website`: public marketing, customer booking/payment pages and legal surfaces.
- `/Users/ismaeelsmiley/Documents/Workloop-OS-Launch`: separate owner-only operating website.
- Existing golden/accessibility tests: approved visual expectations refreshed after review; obsolete image-specific Auth assertion now targets the actual native illustration. A lazily rendered Working hours action is scrolled into view before interaction.

Small issues found during review were repaired: excess Today card height, incorrectly split upcoming start time, crowded calendar heading, lazy-list test reachability, email UTF-8 metadata, dark legal-page wordmark, and clipped private-HQ status rows.

## Verification

- Flutter analysis: no issues.
- Complete Flutter suite: **485 passed, 4 skipped**. The four skips require enabled card-collection flags; the matching release-flag suite was run separately and **all 5 passed**, covering iOS and Android charge-enabled/disabled states and unavailable Tap to Pay.
- Reviewed visual suite: **29 passed** after intentional golden refresh. Responsive/accessibility checks include small phones, light/dark appearance, enlarged text and keyboard reachability.
- Signed iOS profile and App Store archive/export succeeded. Strict code-signing checks passed. Upload succeeded and Apple subsequently showed the build as Testing.
- Android bundle signature, version, manifest, Firebase configuration and 16 KB alignment checked. All 17 native 64-bit libraries meet the alignment check. Four derived APKs installed; emulator cold start was 1.726 seconds with no recorded crash.
- Website: 19 tests, lint, TypeScript and production build passed; desktop, 320 px, enlarged-text and legal-dark visual checks completed.
- Email: 18 tests, three entrypoint type-checks, six subject/plain-text/link parity cases and 13 Auth variable/link parity cases passed.
- Brand: 91 files reproduce byte-for-byte; ZIP CRC and all 161 payload checksums verified.

Apple reported a non-blocking missing StripeTerminal framework dSYM warning. Upload and external beta approval succeeded; the warning limits symbolication for that third-party framework. Tap to Pay remains unavailable.

## Release provenance

The existing working checkout and earlier release artifacts were preserved. Build 11 was made from a separate source snapshot rather than committing or resetting the user's dirty application checkout.

- Candidate: `/Users/ismaeelsmiley/Workloop-Releases/build11-20260904T212527Z/Workloop`
- Candidate commit: `de624cf9bdfd55990a7fccef731ed00d1a4cec1f`
- Branch: `codex/release-build11`
- iOS IPA: `build/ios/ipa/Workloop.ipa`, 34,813,848 bytes.
- IPA SHA-256: `0599e593a27ffd7693d40873153f25d01eb313ea52e93b4b1e0a18e552e808f3`
- Android AAB: `build/app/outputs/bundle/release/app-release.aab`, 96,974,718 bytes.
- AAB SHA-256: `31169c97b4c868d1f2a2e2d455ac916559cc838281b0b8a1392494eb61c5b152`
- Apple Build 11 ID: `353c8885-2039-45fc-bf74-58f543522937`
- Public website: v29, commit `370f88c0d9ef79eb426e0798224865a1f2660aa3`.
- Private Workloop OS: v17, commit `90af39babee5e4d55322a83fb69f7f840a3b5d10`; owner-only access rechecked. Production build and TypeScript passed after the desktop navigation follow-up. Live desktop controls are correctly hidden. A further mobile check was inconclusive because the browser retained a 1,280 px layout despite the requested viewport; earlier mobile review is the relevant visual evidence.
- Supabase project: `imtbyrvsonzvtddswbtb`. Email callers deployed: `join-waitlist`, `confirm-booking-request`, `drain-booking-confirmation-emails`.

Verification logs and read-back results are retained beside the candidate under `verification/`; Android device evidence is under `android-emulator-qa/`. Provider browser observations are recorded in this report and the task's tool history.

## Deliverables

- [TestFlight update](https://testflight.apple.com/join/1ycJPHWx)
- [Public website](https://workloop.uk)
- [Private Workloop OS](https://workloop-os-hq.ismaeelsmiley.chatgpt.site)
- [Editable Canva brand masters](https://www.canva.com/d/ELT2-o4qmvAV8rN)
- Brand ZIP: `/Users/ismaeelsmiley/Workloop-Releases/brand-quiet-warm/workloop-quiet-warm-brand.zip` (1,897,640 bytes; SHA-256 `a00512789224139370e4d7e8c55beb77932384f3d613e032413da32df10f6d36`).
- Asset usage and full export-size table: `assets/brand/quiet-warm/README.md`.

The kit includes scalable and transparent logos, light/dark/reversed variants, 16–2048 px icons, 1080 px avatars, square/portrait/story layouts, a 1200 × 630 preview, 1500 × 500 banner, Facebook/YouTube covers, splash masters, adaptive Android foreground/mask and font licences. Platform crops should be reviewed at upload time.

## Remaining public-launch requirements

1. Finish signing into TikTok to apply the prepared profile artwork. Instagram is complete. No promotional posts or historical posts are being published or replaced by this change.
2. Complete the new personal Google Play developer account and its required verification/testing process; there is no physical Android phone available in this session.
3. Complete card collection with an actual merchant and real onboarding information, then verify live payment and refund behaviour. Clearview is fictional and remains unactivated.
4. Finish outstanding production notification/device checks and the physical booking-to-payment matrix. Simulator, automated and installation evidence do not replace those checks.
5. Complete public store submissions and approval. A polished app and an approved external beta are separate from an approved public release.

Suggested source commit message: `Roll out Quiet + Warm branding across Workloop surfaces`.
