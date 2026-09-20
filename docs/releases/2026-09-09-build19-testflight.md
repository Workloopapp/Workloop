# Build 19 — TestFlight artifact preparation

9 September 2026. This records the local distribution artifact. Apple upload,
processing, tester assignment and website publishing are separate release steps;
this preparation did not perform them or install anything on the owner's phone.

## Source and scope

Build 19 contains the reviewed build 18 app described in
[the refinement report](2026-09-08-build18-refinement.md), with a small privacy
disclosure update. The app and its static `web/privacy.html` mirror now describe
quotes/invoices, payment terms/deposits, receipts, mileage and reviewed tax inputs.
They state that receipt reading runs on the device, raw recognised text is not
stored, selected details become expense data and saved attachments use private
workspace storage. The privacy effective date is 9 September 2026; the terms
retain 6 September 2026.

Changed files for this release preparation:

- `lib/core/workloop_app_info.dart`: independent privacy date and build fallback 19.
- `lib/features/settings/legal_document_screen.dart`: disclosure and privacy date.
- `web/privacy.html`: matching disclosure and date in the app's static mirror.
- `pubspec.yaml`: `1.0.0+19`, avoiding reuse of the owner's build 18 identifier.
- `test/features/settings/legal_document_screen_test.dart` and
  `test/workloop_operator_identity_test.dart`: existing privacy/terms and
  large-text navigation checks updated for the separate dates and disclosure.

The dirty working checkout was preserved. A separate 1,137-file snapshot includes
all tracked and non-ignored untracked source, tests, documentation and dependency
locks. Its own local release commit is
`fe5866a783c36c5c822dbcd875d75449a9c083aa`, on `codex/release-build19`.
It records the original checkout head
`dbac1301674cc411a921db6a7828c3dc3c760738` and dirty status separately. No root
commit or remote push was performed.

Frozen source: `/private/tmp/workloop-release-build19-20260909/Workloop`.
The manifest is in its parent directory as `source-manifest.json`, SHA-256
`0bffea166bc858bd9ebc6df9b7c9bc72dbf7d14e381f21b7dadb5f897304b4ca`.
Compared with the owner's 409-file build 18 manifest, the only app-source changes
are the app-info file, privacy screen and pubspec. The owner build 18 AOT and
manifest hashes remain unchanged. The unused earlier build 18 preparation copy
was preserved and was never archived.

## Verification

- Full Flutter suite: **1,190 passed, 10 skipped, zero failures**, run against
  root build 19 with `--dart-define-from-file=.env`. The skips remain the existing
  intentionally gated tests; this does not claim they executed.
- Focused legal/operator suite: **9 passed**, including 320px / 2× text coverage.
- `flutter analyze`: **no issues**.
- Release-tool Python suite: **19 passed**.
- Scoped `git diff --check`: passed. App/static privacy paragraphs match exactly.
- `qa_signed_builds.sh`: clean-commit preflight, archive, export-only App Store IPA,
  version verification and artifact recording all passed.
- The frozen source and recorded CocoaPods/SwiftPM/configuration input hashes remained
  unchanged after compilation. Build toolchain: Flutter 3.44.8, Dart 3.12.2,
  Xcode 26.6 (17F113).

Build command, run from the frozen source:

```sh
export FLUTTER_ROOT=/Users/ismaeelsmiley/flutter
export RELEASE_DEFINES_FILE=/private/tmp/workloop-release-build19-20260909/production-defines.json
export RELEASE_PAYMENT_COLLECTION_ENABLED=true
export RELEASE_PLATFORMS=ios
export RELEASE_EXPECTED_SHA=fe5866a783c36c5c822dbcd875d75449a9c083aa
bash scripts/qa_signed_builds.sh
```

The private local defines file contains only validated public mobile settings.
Its normalized fingerprint is
`2a5d4f056113a5abcf3031a0021235f9c3d856bc36e9759aa4744a85b0a63bce`.
Payment collection, subscriptions and crash reporting are enabled; APNs is
production; Tap to Pay is disabled. No server credentials or signing secrets
were copied into the source snapshot.

## Exported artifact

- Version: **1.0.0 (19)**; bundle: `com.ismaeel.workloop`; minimum iOS: 15.0.
- Archive: `/private/tmp/workloop-release-build19-20260909/Workloop/build/ios/archive/Runner.xcarchive`.
- IPA: `/private/tmp/workloop-release-build19-20260909/Workloop/build/ios/ipa/Workloop.ipa`.
- IPA size: **37,415,707 bytes**.
- IPA SHA-256: `b1c331af016774f4bb8cae0d09e7deb5dad2d9cbacf771f8ce98c4dbe7f40543`.
- Exported AOT SHA-256: `9e7b2b195a76e4102c34b420d5a0f68bcc2a0aec4f1696817fd61c938c5791dc`.

The extracted exported IPA passed deep, strict code-sign verification with system
certificate trust. Its entitlements have `aps-environment=production`,
`get-task-allow=false`, and application ID `6RH526FD7B.com.ismaeel.workloop`.
The App Store provisioning profile has no provisioned-device list. Export options
specify `app-store-connect`, `destination=export` and no automatic build-number
changes. Generated build settings confirm the normal `lib/main.dart` entry point
and the requested flags. The new privacy paragraph and date are present in the
compiled AOT binary.

The first sandboxed signature check could not access system certificate trust
(`CSSMERR_TP_NOT_TRUSTED`); the identical check with system trust access passed.
This was a verification environment restriction, not a signing change.

## Limits and handoff

The export log contains a nonfatal `Upload Symbols Failed` entry during symbol
packaging. The archive has no vendor `StripeTerminal.dSYM`; the embedded
framework UUID is `B897F24C-5DBA-3B9F-BC35-7A5EF6945F71`. This preserves the known
vendor symbolication limitation from earlier releases. The actual Apple upload
result and any warning must be recorded separately. Two existing plugins,
`device_calendar` and `flutter_local_notifications`, still use CocoaPods;
Flutter warns that a future version will require SwiftPM support. Neither
warning prevented this build/export.

Evidence is in `/private/tmp/workloop-release-build19-20260909/`: build/test logs,
`artifact-verification.json`, `exported-entitlements.plist`,
`codesign-verification.txt`, `owner18-parity.json`, input hashes and toolchain
metadata. The exact preflight/artifact receipt is in the frozen source at
`build/release/release-provenance.txt`. The full-suite log is also preserved there
as `build19-full-flutter.log` in the parent evidence directory.

If Apple's upload workflow re-exports the archive, retain this original IPA and
record the newly uploaded IPA's hash separately. This report is a post-build
receipt in the working checkout and is not claimed as an input to the frozen
artifact.

## Apple upload — 9 September 2026

The owner then explicitly authorized uploading for the existing beta testers.
A fresh authenticated App Store Connect check confirmed build 16 was the highest
uploaded build and build 19 was unused before the upload began. Xcode used the
existing account authentication and the same verified archive; no compilation or
automatic version change occurred.

```sh
xcodebuild -exportArchive \
  -archivePath /private/tmp/workloop-release-build19-20260909/Workloop/build/ios/archive/Runner.xcarchive \
  -exportPath /private/tmp/workloop-release-build19-20260909/apple-upload-export \
  -exportOptionsPlist /private/tmp/workloop-release-build19-20260909/build19-upload-options.plist \
  -allowProvisioningUpdates
```

Upload options set `destination=upload`, `method=app-store-connect`,
`manageAppVersionAndBuildNumber=false`, and
`testFlightInternalTestingOnly=false`. This keeps the build eligible for normal
external TestFlight review; it does not itself submit or assign the build to an
external group.

**Upload succeeded at 07:37:36 BST (06:37:36 UTC)**. Xcode exited zero and reported
`Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.
No Apple licence agreement blocked the upload, and no legal terms were accepted.
Apple emitted the expected nonblocking missing StripeTerminal dSYM warning for
UUID `B897F24C-5DBA-3B9F-BC35-7A5EF6945F71`.

Xcode re-exported the archive for upload. The exact package was captured from its
upload pipeline and retained separately:

- Uploaded IPA: **37,415,693 bytes**.
- Uploaded IPA SHA-256: `60ab932cceaade711004ad9d8f70c83f6d9501fa9ee41820091e9934e411fce1`.
- Uploaded signed AOT SHA-256: `784495376a87386497581b5dea6837d7fb6aa63fce3e1deb16d70243ba8b77f3`.

The upload package independently passed deep, strict signature verification,
bundle/version checks, production APNs and `get-task-allow=false`. Its compiled
privacy text/date are present. All AOT bytes outside the embedded Mach-O
`LC_CODE_SIGNATURE` data match the original export exactly; the signed AOT hash
changes because Xcode signs the new export. Both original and uploaded IPA hashes
are preserved rather than treated as interchangeable.

Durable evidence is now under
`build/release-build19-20260909/app/` in the main checkout. It includes
`Runner.xcarchive`, `prepared-Workloop.ipa`, `uploaded-Workloop.ipa`, the verified
`frozen-source.bundle`, source/input manifests, private public-configuration
snapshot, test/build/upload logs, Apple's distribution logs, entitlements and
verification receipts. `durable-evidence-sha256.json` records the key file hashes.
The source bundle contains the exact clean release commit listed above. The
existing `website/` evidence directory was preserved.

This upload step did not change tester groups, release metadata or website files.
App Store Connect processing completion and tester distribution must be recorded
separately after their UI states are verified.

## Additional release verification

The final required root profile build also passed on 9 September:
`source scripts/dev_env.sh` followed by
`flutter build ios --profile --dart-define-from-file=.env`. Xcode completed in
45.8 seconds and produced the 79.8 MB profile app. This is an additional compile
check, not the uploaded App Store binary or a new physical-device install. Its
log is `build/release-build19-20260909/app/profile-build-root.log`.

The website update is live and separately verified in
[the website receipt](2026-09-09-website-release.md). Production backend parity and
operational checks are recorded in
[the backend check](2026-09-09-backend-release-check.md).

## Store metadata and access checks

App Store Connect's existing English (U.K.) public version 1.0 draft now has the
updated promotional text and description from `docs/StoreSubmission.md`, replacing
the stale free-without-subscriptions and no-tax-calculation claims. The public
version remains **Prepare for Submission** with manual release selected. No public
App Store review submission or release occurred.

The missing public App Privacy policy URL was saved as
`https://workloop.uk/privacy.html`. The App Privacy questionnaire itself remains
unstarted; its source-based receipt-photo delta is prepared in
[the privacy worksheet](2026-09-09-privacy-disclosures.md). It is a separate public
launch requirement, not an assertion of completed Apple privacy certification.

TestFlight's beta app description and review notes were updated and the UI
confirmed **Saved**. Existing reviewer credentials/contact and group membership
were preserved. Current beta access is open, billing enforcement is off, and
Apple purchases are unavailable; paid-plan wording remains explicitly planned.
The existing dedicated reviewer identity is confirmed, not banned and has no
pending deletion. It has no workspace or lifetime grant, but the current access
helper returns beta access. Onboarding is reached before the subscription gate.
No credential, entitlement or review-account data was changed, and a fresh login
was not performed.

The exact copy is retained at
`build/release-build19-20260909/app/store-copy.json`. TestFlight upload processing
and external group release are recorded below when confirmed.

## TestFlight distribution completed

Apple completed processing build **1.0.0 (19)**, build ID
`0b89b128-9818-40db-bbbd-28d6a5f32ba8`. The build's What to Test notes were saved,
then it was assigned to the existing **Workloop Private Beta** external group
`777f639d-0d62-4da0-a1b3-67158adcdec5` with **Automatically notify testers** enabled.
Beta review was submitted and Apple approved the build.

Fresh authenticated App Store Connect group evidence at approximately 07:47 BST
shows **1.0.0 (19) — Testing**, with the existing **13 testers** and seven group
builds. The internal group remains assigned with its existing one tester. No new
tester, group, link or audience settings were added. Two existing external tester
rows already showed installation of build 19; this is Apple-reported installation
telemetry, not manual confirmation of their experience.

The public App Store version remains an unsubmitted draft. There was no Apple
license-agreement block on upload or beta release, and no legal terms were
accepted by the agent.

## Remaining boundaries and change record

The known StripeTerminal vendor dSYM warning affects symbolication, not the
successful upload/testing status. Existing handheld camera/HEIC/share and Android
runtime checks remain documented in the build 18 review. Paid subscription
provider activation and public App Privacy/submission remain separate public
launch work; the current private beta requires no purchase.

Suggested app release commit message, once the owner elects to consolidate the
preserved working tree: `Prepare build 19 beta release and receipt privacy
disclosures`. The isolated frozen source is already committed; the main app
working tree was not committed or pushed. Website source commits and live proof
are recorded in the separate website receipt.
