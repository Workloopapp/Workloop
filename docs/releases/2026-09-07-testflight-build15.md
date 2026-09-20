# Build 15 release — 7 September 2026

## Scope and source

The user authorised uploading the current app to TestFlight and GitHub. The main working checkout was preserved. Build 15 adds the reviewed CSV/vCard client import changes to frozen build 14, including field mapping, review/exclusion of rows, duplicate checks, and file-size/format limits. No new backend or public App Store release was performed in this task.

- Version: **1.0.0 (15)**, bundle `com.ismaeel.workloop`.
- Frozen source: `/Users/ismaeelsmiley/Workloop-Releases/build15-20260907T194212Z/Workloop`.
- Source commit: `85bbc8f2a8d12862171552ae959f3f2ca6582c00`.
- GitHub: `https://github.com/Workloopapp/Workloop/tree/codex/release-build15`. Push succeeded and `git ls-remote` independently returned the same commit. The existing default branch was not overwritten.

## Validation

- `flutter analyze`: no issues.
- Full `.env` tests: 1,018 passed, six capability-gated tests skipped.
- Payment-enabled suites: eight passed, including all gated tests and two other checks.
- Signed iOS profile build succeeded against the same app implementation before the build-number bump.
- Frozen build 15 distribution archive and IPA succeeded with Flutter 3.44.8. The first frozen-checkout attempt selected an older Flutter from PATH and failed dependency resolution; rerunning with explicit `FLUTTER_ROOT=/Users/ismaeelsmiley/flutter` resolved the environment mismatch.
- Exported IPA passed strict signature verification, bundle/version and both location-purpose-string validation. Production APNs; debug access disabled. The archive itself has development signing before Xcode distribution export re-signs it; the exported IPA was verified separately.
- IPA SHA-256: `2e7081b35901d6665896d3bd09c227c3c137f8f6b4392e61070f4f6d740f5fb3`, 35,841,947 bytes.
- Release config matches build 14: payment collection, subscriptions and crash reporting enabled; production APNs; Tap to Pay disabled. Public config SHA-256 `2a5d4f056113a5abcf3031a0021235f9c3d856bc36e9759aa4744a85b0a63bce`.
- Candidate source scanned for private-key/credential files, API tokens and service-role JWTs; no actual secrets found. Runtime configuration and signing material remain ignored.
- Fresh physical-device validation of these import additions has not been performed.

## Live TestFlight finding before upload

At approximately 20:46 local time, App Store Connect showed build 14 upload Complete, status Ready to Submit, attached only to the internal group. Build 13 was in the same state. The external **Workloop Private Beta** group had 13 testers and build 12 as its newest Testing build. Therefore uploaded build 14 was not yet available to the external beta users.

Build 15 upload and external-group assignment are in progress. Do not interpret this source record as proof of tester availability until the outcome below is appended.

## Upload receipt

Xcode upload succeeded at **20:52:33 BST** on 7 September 2026 (`EXPORT SUCCEEDED`; Apple reported the package is processing). The known nonblocking StripeTerminal vendor dSYM warning remains. No location-purpose warning occurred in the upload log. Processing completion and external tester availability still require the dashboard check below.

## External beta availability — completed

App Store Connect processing completed. Build **1.0.0 (15)** was added to **Workloop Private Beta**, with **Automatically notify testers** checked and specific testing notes covering request confirmation date/time, direct Tomorrow navigation, CSV/vCard import review and existing records. Submission immediately returned **Testing** in that external group, which contains **13 testers**. Build 15 is therefore available to that group; actual downloads/installations have not been independently verified. The public beta link remains `https://testflight.apple.com/join/1ycJPHWx`.

The account's updated developer-agreement notice did not block this upload or external-beta distribution. It still needs account-holder review before public launch. No public App Store submission was made.

## Related social work

- Instagram post 4 published: `https://www.instagram.com/workloop.app/p/Dc_2pI_ihcJ/`, four-photo carousel with continuous native **Feels Good (Instrumental) — d.higgs**. Facebook and Story cross-sharing remained off.
- Workloop Facebook page `61594170890519`: updated profile photo to the quiet/warm blue W avatar and cover to the matching retro artwork. The cover's lettering was moved up to avoid the overlapping mobile profile photo; saved page appearance was verified on the phone.
- Social receipts and the editable adjusted cover are in `/Users/ismaeelsmiley/Documents/Workloop Launch/quiet-warm-2026-09`.
