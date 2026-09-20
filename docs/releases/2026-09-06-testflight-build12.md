# TestFlight build 12 release record

The owner authorised uploading the current local app and notifying its users on 6 September 2026. The earlier TestFlight hold is lifted; this is not a public App Store release.

## Candidate and verification

- Snapshot: `/Users/ismaeelsmiley/Workloop-Releases/build12-20260906T214251Z/Workloop`.
- Final snapshot commit: `69b3f5f5047d2a454e238849b8f9e2a8a69efe88`; original dirty checkout preserved.
- Version `1.0.0+12`, bundle `com.ismaeel.workloop`, team `6RH526FD7B`.
- Payment collection enabled, Tap to Pay disabled, phone authentication disabled, crash reporting enabled.
- Flutter 3.44.8; analysis clean; 891 payment-enabled Flutter tests passed.
- 21 release-tool/symbol-path tests passed. Signed release archive and profile device build succeeded.
- Fixed an archive-only Crashlytics uploader lookup: Flutter resolves packages in its iOS output folder while Xcode archive BUILD_DIR may use ArchiveIntermediates. Added relative/custom absolute output-path regression coverage. No runtime feature changes in this release step.
- Xcode was signed out; the owner signed back in. Upload succeeded at 22:56 BST. Apple displayed build 12 Processing.
- Exported IPA identity/version verified. Distribution entitlements: production APNs and get-task-allow false.
- Non-blocking Apple upload warning: StripeTerminal.framework lacks a vendor dSYM (UUID B897F24C-5DBA-3B9F-BC35-7A5EF6945F71). Tap to Pay is disabled. Do not claim complete symbol coverage for this vendor framework.

## Device evidence

Installed the fresh candidate profile on the paired iPhone 15 Pro Max and launched it. Live local weather displayed. Attention actions opened the exact task and booking request after navigation completed. This is profile-device evidence, separate from installing the App Store-signed TestFlight binary.

## Email preparation

Prepared branded HTML/plain-text service update and beta-testing prompt in the release folder's `operations` directory. Audience query found 15 verified non-test accounts, excluding seven development/demo identities; excluded any recorded unsubscribe/suppression. No ongoing marketing enrolment is part of this send. Recheck preferences immediately before dispatch.

Email dispatch is gated on build 12 becoming available to the external beta group. Use individual envelopes and fixed campaign/recipient idempotency keys. Prepared temporary server-side dispatch expires before Resend's 24-hour idempotency window and must be disabled after completion. Credentials stay in existing backend secrets.

## Remaining release actions

Confirm Apple processing and beta distribution, save What to Test, notify testers and then send the user update. Record provider receipts and any delivery failures below. Public App Store listing/review and genuine live merchant-payment verification remain separate launch work.

## Distribution receipt — 23:05 BST

Apple processed and approved build 12. Added Workloop Private Beta alongside Workloop Internal Beta; external group shows **1.0.0 (12) — Testing**, 13 testers. Saved the 849-character What to Test notes and left **Automatically notify testers** checked. Verified the group's public link is `https://testflight.apple.com/join/1ycJPHWx`.

Exported retained IPA: `build/ios/ipa/Workloop.ipa`, 35,494,215 bytes, SHA-256 `02f1b33939738054331cf3fda17b9755054b867ca23758d6f57ad16bd1fc37b1`. Xcode's upload export and this retained export came from the same archive; the retained export was separately signed/exported and should not be claimed byte-identical to Apple's upload package.

Authorised user-notice dispatch invoked only after the external group showed Testing. Temporary endpoint `send-build12-release-notice`, pg_net request 34700. Delivery receipts pending below.

## Email completion — 23:08 BST

Resend accepted 15 individual notices and the dashboard subsequently showed **Delivered for all 15**, including the three Apple private-relay addresses. No retry or duplicate send was needed. The HTML and plain-text notices came from `Workloop <hello@workloop.uk>`, with `support@workloop.uk` as Reply-To. They explain how to update and ask recipients to exercise their everyday beta workflows.

Disabled all sending code in temporary endpoint version 2 and enabled JWT verification; the remaining handler returns `410 campaign_completed`. No recurring job was created. Private provider receipts are retained in the release operations directory, not the app repository. This confirms provider delivery, not that recipients read the message or installed the update.

## Handoff and remaining limits

The owner began using the iPhone while the final Money-screen spot check was being attempted; Mirroring disconnected. Do not claim that additional manual check passed. The candidate's automated Money/navigation suites are included in the 891 passing tests, and the current profile candidate is installed on the phone.

The current turn changed `ios/scripts/upload_crashlytics_symbols.sh` and its regression checks in `scripts/tests/test_crashlytics_symbols.py` to fix archive packaging, and added this release record. No app data, bookings or payments were changed during manual checks. Suggested source commit: `fix: resolve Crashlytics symbols during Flutter archives`.

Public-launch follow-up remains as listed in `2026-09-06-ios-store-submission.md`: native store screenshots/listing completion, final review credentials/privacy declarations, genuine connected-merchant live-payment verification, and full production push/crash ingestion checks. Company tax/Companies House work stays in the separate company task. No public App Store submission or release occurred in this beta-release turn.
