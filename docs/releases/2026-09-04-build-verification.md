# Workloop release preflight — 4 September 2026

## Final distribution update from lead — 4 September 2026

The chronological report below includes earlier intermediate states. Final iOS source is 31b190d3f21249dc5c0dff60885da3f62a6ea47d; Apple accepted Build 10 at 21:22 BST and external state is IN_BETA_TESTING. It is assigned to 13 existing external testers; two observed installed 10 and eleven still 6. The signed profile also installed/launched on the connected iPhone. Final repaired Android source is d3f9211474304f59d53c9a44b1a639a050fa45b8; AAB SHA256 cdda5308e7bae3fd274b4ab1ea569908eabcf7bad13575f97a4ae22af3a3a908, exact-derived emulator startup passes without the original reader error. No Android upload has occurred. See [the authoritative release audit](2026-09-04-launch-audit.md) for full current status and external gates.

---

Read-only inspection using QA Reviewer and Flutter Lead perspectives. No source, settings, artifacts, devices, production records, signing identities or store assignments changed. Commands inspected local state; no full suite or new build was run by this subtask.

## Highest priority discovery

`scripts/qa_all.sh` uses the same hard-coded placeholder Dart defines for its quality tests AND `RUN_SIGNED_BUILDS=true` store builds. That path produces a distribution app pointed at `https://example.supabase.co` with `ci-public-anon-key`. It must require a separate real release define file and validate the project before store builds. Payment capability defaults false and must be explicitly enabled only after the payment gates pass. Android is built first, so absence of upload signing blocks iOS output as well.

`qa_release_candidate.sh` enforces a clean tracked/untracked worktree and exact commit but records the pubspec version, not the actual artifact Info.plist/Android manifest. It does not verify the embedded backend identity or prevent Xcode rewriting the version. Existing ExportOptions.plist has manageAppVersionAndBuildNumber=true. Use false for deterministic release identity.

## Current artifacts

- Source pubspec: 1.0.0+8.
- HEAD: dbac1301674cc411a921db6a7828c3dc3c760738 (current working tree contains extensive subsequent changes).
- Archive: `/Users/ismaeelsmiley/Workloop/build/ios/archive/Runner.xcarchive`, created 2 September 17:53:52 UTC, version 1.0.0 build 9, Apple Development signature. Strict deep signature verification passes.
- IPA: `/Users/ismaeelsmiley/Workloop/build/ios/ipa/Workloop.ipa`, 34,766,747 bytes; SHA256 e8e0df6a5b657a8043049503cf5f33d7b68d760120da92eddeeff59d16145006. Version 1.0.0 build 9, com.ismaeel.workloop, iOS 15 minimum. Hash exactly matches final 2 September source evidence in TEST_RESULTS.md.
- Export profile: iOS Team Store Provisioning Profile: com.ismaeel.workloop. Team 6RH526FD7B, expiry 11 August 2027. Production APNs, beta-reports-active=true, get-task-allow=false, Apple sign-in present.
- DistributionSummary.plist explicitly says Cloud Managed Apple Distribution. Only a local Apple Development identity is available; cloud export explains successful production signing and does not require inventing a missing-p12 blocker.
- No `build/release` provenance directory exists. Build 9 was created from a dirty tree, so no reliable exact committed source binding exists.
- TestFlight status was not independently refreshed by this subtask. Prior audit says testers use 6 and upload 7 is pending; root must refresh immediately before assigning a newer candidate.

## Devices and toolchain

- Xcode: /Applications/Xcode.app/Contents/Developer. xcodebuild/xcrun/security callable.
- Flutter through `source scripts/dev_env.sh`: /Users/ismaeelsmiley/flutter/bin/flutter.
- Physical iPhone 15 Pro Max available/paired, iOS 26.5.2. Flutter ID 00008130-001418E211A1001C; CoreDevice ID 64EA9934-4D30-544D-B2F1-3B7EEBE57386.
- Android adb: /Users/ismaeelsmiley/Library/Android/sdk/platform-tools/adb. No attached Android device. Flutter lists iPhone and macOS only.
- No release AAB/APK found in current build outputs. `android/key.properties` and release keystore are absent. Gradle correctly fails closed for release signing. Only the ordinary ~/.android/debug.keystore exists; never use that for Play release.
- No Docker, Podman, Colima, Lima, postgres, initdb, pg_ctl, psql or Supabase executable found in PATH, standard /opt,/usr/local, ~/.local, bundled runtime or Applications searches. No running local stack was started.
- Bundled Node and pnpm can install official Supabase CLI, but CLI alone cannot execute a clean database replay without a container backend. Python database libraries are clients and do not supply Supabase PostgreSQL extensions.
- Keychain service `Supabase CLI` exists and may provide login automatically after installation. Metadata only was inspected. Also `com.ismaeel.workloop.testflight-review` exists for the reviewer account. Xcode account configuration exists. No .p8 file located in Documents/.codex outside caches and sessions. No credentials printed or retrieved.

## Isolated backend verification

76 migration files and 13 pgTAP test files are present at inspection time. Current source requires a fresh replay and all current pgTAP assertions; historical 111-test or Build 9 hosted checks are not the same evidence.

`scripts/qa_local_supabase.sh` correctly checks Docker/daemon/CLI, checks local config for production identifiers, then runs supabase start, supabase db reset --local and supabase test db. Safe local route needs an installed functioning Docker-compatible macOS runtime. A hosted disposable branch is an alternative for functional rehearsal but does not prove replay from empty unless explicitly constructed from the entire migration history.

`scripts/qa_staging_e2e.sh` requires QUALITY_DEVICE_ID, E2E_SUPABASE_URL, E2E_SUPABASE_ANON_KEY, E2E_STAGING_PROJECT_REF, two disposable account email/password pairs, E2E_PUBLIC_HANDLE and E2E_REQUESTER_EMAIL. It rejects production ref and requires matching hosted staging URL. It does not accept a loopback URL; do not bend this safety guard to target production. None of these E2E variables are exported in the current shell.

## Android and card-collection launch gates

The user's requirement is now public iPhone AND Android launch with working card collection, so earlier payments-off beta scope is no longer sufficient.

- Need actual Play Console app/access/account readiness, durable upload key with encrypted backup, release AAB, Play app signing, Data safety/content declarations, internal/closed-test eligibility and device checks. This subtask did not open Play Console or infer account status from docs.
- Neither actual Runner.entitlements nor current Build 9 distribution profile includes Apple proximity-reader.payment.acceptance. Tap to Pay is not present in this artifact. Historical docs say application for entitlement submitted, approval awaited; live Apple portal must refresh status.
- `lib/core/workloop_capabilities.dart` defaults PAYMENT_COLLECTION_ENABLED=false; .env contains only Supabase public values. A new explicit payment-enabled artifact is necessary.
- Historical docs say Stripe merchant onboarding remains restricted and no real payment/refund proof. Live provider/backend status must be refreshed; don't describe those old details as confirmed current.
- Working card links can meet a card-collection launch scope without unsupported iPhone Tap to Pay, provided UX hides unavailable terminal modes and test/live payment/refund/reconciliation and receipt delivery succeed. User/lead decides precise launch promise.

## Artifact preservation and release path

Do not run `scripts/use_tmp_build_dir.sh` casually: it moves the existing entire build directory and replaces it with a symlink. Do not run a fresh flutter build ipa in this checkout before preserving Build 9.

Flutter ipa has no per-command output/build-dir flag. `flutter config --build-dir` changes global SDK config. Prefer an isolated clean snapshot/worktree with its own build/ and reviewed source identity; otherwise explicit xcodebuild archivePath/exportPath after correctly generating the release Flutter inputs. Never conflate an old archive export with a new source build.

1. Repair release script production defines, source version identity and missing current Edge check coverage.
2. Finish backend/app repairs and consolidate all intended changes into an immutable reviewed source snapshot/commit.
3. Run current full analysis/tests, Edge checks, fresh local DB replay/pgTAP and disposable hosted journeys; physical payment/notifications/navigation/accessibility checks remain distinct.
4. Produce fresh iOS and Android store artifacts using matching source identity and actual launch capabilities. Keep older archive intact, record byte size/hash, signature/entitlements/profile and actual embedded version/backend.
5. Upload exact iOS candidate, wait for processing/review, attach to intended existing TestFlight groups, verify production-token registration and installed-build journey. Assignment makes updates available but cannot force all tester devices to install immediately.
6. Upload/roll out Android test artifact and verify device evidence, then complete platform public-review gates. Store approval timing is external.

## CI and documentation drift

GitHub connector fetch_commit_workflow_runs returned no PR-triggered runs for current HEAD. The connector explicitly filters to PR events; this is not proof that push/scheduled CI never ran. No CI pass established for the current dirty source.

`.github/workflows/mobile-ci.yml` and scripts/qa_all.sh explicitly type-check 12 functions but omit `resend-webhook` and `collect-apple-reporting` (14 function entrypoints currently present). Tests still scan the full functions directory, but helpers are not equivalent to checking every handler entrypoint.

StoreSubmission contains obsolete icon-neon wording and old four/six build drafts; LaunchReadiness and KNOWN_GAPS mix historical source versions, private-beta limitations and newly public requirements. Update current state with a dated authoritative section after final verification, retaining historical evidence.

Memory used to preserve source/artifact/upload/install distinctions: MEMORY.md lines 127-139 and 374-385. These were historical guidance, not current operational evidence.

## Implemented release safeguards (4 September follow-up)

Owned changes: scripts/qa_all.sh, scripts/qa_release_candidate.sh, new scripts/qa_signed_builds.sh, scripts/release_config.py, scripts/tests/test_release_tools.py, and narrow .github/workflows/mobile-ci.yml additions. Existing dirty changes retained. The signed runner now requires RELEASE_DEFINES_FILE, RELEASE_PAYMENT_COLLECTION_ENABLED=true|false, and RELEASE_PLATFORMS=ios|android|ios,android. It uses a mode-0600 normalized temporary configuration, validates the exact production URL and public-key class (legacy JWT also verifies project/anon role), rejects unsupported keys, passes explicit source version/build number, exports with manageAppVersionAndBuildNumber=false, protects existing archive, and records a public config fingerprint rather than credentials. Artifact recording validates the actual IPA bundle/version. Android can run independently of iOS. Deno checks now cover resend-webhook and collect-apple-reporting. Release safety tests are wired into local QA and Mobile CI.

Verification: all 9 fake-tool release regression tests passed; bash -n for three changed scripts passed; git diff --check passed. No signing, upload, real build, source commit, global Flutter setting or existing artifact changes. Offline publishable-key format validation cannot prove a key belongs to the project; actual network/provider QA remains required. Android AAB embedded manifest identity is not separately parsed by this helper.

Invocation after immutable source and provider checks: RELEASE_DEFINES_FILE=/absolute/path/to/.env RELEASE_PAYMENT_COLLECTION_ENABLED=true RELEASE_PLATFORMS=ios bash scripts/qa_signed_builds.sh. Use android or ios,android only after durable Android signing is provisioned. The current checkout will correctly refuse due to dirty source/existing archive; root must prepare the intended clean isolated candidate.

## Cross-platform push repair (4 September implementation)

Implemented in remote_push_service.dart, remote_push_bootstrap.dart, shared/repositories/push_token_repository.dart, shared/push_delivery.ts, new push_delivery_fcm.ts, scheduled worker import/guard, CLI-generated migration 20260904194801_cross_platform_push_delivery.sql, pgTAP016, and focused Dart/Deno tests.

- Explicit APNS_ENVIRONMENT=production|sandbox is persisted per token and wins over the legacy worker-wide fallback. New iOS builds with an unknown signing environment refuse registration; developer profile/debug runs require sandbox. Store packaging now injects/records production and refuses a sandbox define. Never infer APNs from kReleaseMode.
- Existing four-argument registration remains compatible and preserves previously known environment on an old-client refresh. New five-argument registration uses one private MFA/membership-guarded implementation. Token ownership transitions are serialized, previous queued alerts are cancelled, and claims reject tokens whose workspace membership no longer matches.
- Android sends use FCM HTTP v1, RSA-signed service-account OAuth assertions, short-lived token cache keyed by credential identity, a fixed Google OAuth endpoint and stable errors that exclude raw provider messages/token/key values. UNREGISTERED disables tokens; configuration/payload errors do not. Retry-After extends durable database retry backoff.
- Server FCM_SERVICE_ACCOUNT_JSON must be stored only as a Supabase secret and correspond to the Firebase project used by android/app/google-services.json; enable Firebase Cloud Messaging API and service-account messaging permissions. No server credentials go into Dart defines.
- Android uses and eagerly creates existing workloop_reminders channel, ic_stat_workloop icon, privacy-safe notification text and deep_link data for FlutterFire taps. Root should add default channel/icon metadata to the Android application manifest when preparing native Firebase configuration.
- Apple token cache now changes with signing-key identity. Legacy BadDeviceToken no longer permanently disables a possibly-valid token merely because the global environment mismatches. Previously disabled devices recover on new registration; the migration does not blindly reactivate tokens.
- Batches are capped at5 sequential deliveries to remain below2-minute leases with bounded provider timeouts; worker Android setup no longer depends on APNs setup. Lifecycle token refresh/workspace errors no longer become unhandled asynchronous failures; initialization can retry.
- Morning-brief push previews are now generic, so even generated notification-body content cannot leak customer/payment details.

Validation: 11 focused Deno tests pass (including real generated-RSA assertion signature validation, OAuth caching, config/error classification, Android payload/channel, independent Android drain, Retry-After and APNs environment/legacy routing);6 focused Flutter tests pass (HTTP-backed repository parameter validation and routes/context/environment); Deno lint/type-check of worker pass;10 release-tool regressions pass; diff whitespace clean. Full flutter analysis identified one local braces issue fixed and2 concurrent payment-agent test lint findings reported to root.

Database status: recent_request_coverage agent reports the push migration compiled in its complete app-schema PGlite replay (80 migration files at that moment). pgTAP016 has22 assertions; execution status to follow. PGlite does not establish the actual Supabase Auth/network/provider/device stack. No production deployment, push send, app install or upload performed by this subtask.

Primary references consulted: Firebase HTTPv1 send/auth https://firebase.google.com/docs/cloud-messaging/send/v1-api ; FCM error codes https://firebase.google.com/docs/cloud-messaging/error-codes ; Google service-account OAuth https://developers.google.com/identity/protocols/oauth2/service-account ; Firebase Android message/channel reference https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages ; Apple APNs entitlement https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment ; Supabase changelog https://supabase.com/changelog.md .

Push database verification update: recent_request_coverage reports full80-migration app-schema PGlite replay succeeds and pgTAP016 passes22/22. Existing009 fixture required actual request.jwt.claims JSON alongside legacy role GUC; fixture fixed, production service-role guard retained, rerun requested. Current report release test count10 and Dart6/Deno11 remain passing. PGlite harness output: /tmp/workloop-db-validation/full-replay-results.json.

Final push handoff: existing pgTAP009 now passes35/35 and new016 passes22/22 in the full migration PGlite harness. Final11 Deno tests and6 Flutter tests pass,10 release harness tests pass. Full flutter analysis has no push findings; only concurrent payment test braces at stripe_collection_enabled_test.dart63/65 remain for its owner. No production push/config deployment or physical push verification performed here.

## Android Firebase wiring and emulator preparation

Changed only android/settings.gradle.kts and android/app/build.gradle.kts in this subtask. Pinned official GoogleServices Gradle plugin4.5.0 (current Firebase Android setup documentation). Applied conditionally when android/app/google-services.json exists; missing configuration leaves debug/profile usable with a build warning and blocks explicit release tasks immediately. A preReleaseBuild check additionally covers generic assemble/build task names. Plugin processing validates the Android package when real configuration arrives. No new Firebase SDK duplication; existing FlutterFire dependencies remain authoritative.

Actual Gradle configuration/tasks succeeded. Profile assemble dry-run succeeded without JSON. Release assemble dry-run failed with the intended missing Firebase configuration explanation. These were Gradle configuration/taskgraph checks, not APK/AAB builds. Root still owns real Firebase app registration/config download and Android upload signing. No signing keys or credentials created here.

Installed official SDK emulator37.1.11 and system-images;android-36;google_apis;arm64-v8a revision7. Existing SDK licence acceptance was verified through Flutter doctor; installation ran with stdin closed and never accepted new terms. Native ARM64 emulator and Hypervisor.Framework acceleration verified. Created WorkloopQA_API36 Pixel8 AVD at /Users/ismaeelsmiley/.android/avd/WorkloopQA_API36.avd. Headless emulator5554 boot complete (sys.boot_completed=1), Android16, arm64-v8a, Google Play services package present. Exec session53801 keeps the emulator running for root. No Workloop APK installed. Emulator cannot validate real NFC/Tap-to-Pay hardware.

Launch command: /Users/ismaeelsmiley/Library/Android/sdk/emulator/emulator -avd WorkloopQA_API36 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader . Device selector: emulator-5554. Shutdown command when QA is done: adb -s emulator-5554 emu kill .

Logs: /tmp/workloop-sdk-package-list-20260904.txt, /tmp/workloop-android-sdk-install-20260904.log, /tmp/workloop-avd-create-20260904.log, /tmp/workloop-emulator-20260904.log, /tmp/workloop-android-gradle-tasks-20260904.log, /tmp/workloop-android-profile-preflight-20260904.log, /tmp/workloop-android-release-preflight-20260904.log. Primary docs: https://firebase.google.com/docs/android/setup ; https://firebase.google.com/docs/android/google-services-plugin-and-file ; https://developer.android.com/tools/sdkmanager ; https://developer.android.com/tools/avdmanager .

## New Android upload key prepared

After confirming no existing upload keystore, Android signing properties, or Keychain service, created a new PKCS12 upload key (3072-bit RSA, SHA256withRSA, valid through20 January2054). This is the upload identity; Google Play-managed app signing remains a separate store setup step.

Primary keystore: /Users/ismaeelsmiley/.workloop-signing/workloop-upload.keystore

Public certificate: /Users/ismaeelsmiley/.workloop-signing/workloop-upload-certificate.pem

Keychain service: Workloop Android upload signing; account: workloop-upload. Store/key passwords are strong random values stored as a JSON credential using native macOS Keychain APIs, verified by reading back within the same process. No passwords appeared in commands, tool output or logs. Android/key.properties is ignored and mode0600; keystore and backups are mode0600 under private directories.

Two encrypted, checksum-matching backup copies:
- /Users/ismaeelsmiley/.workloop-signing/backups/local-a/workloop-upload.keystore
- /Users/ismaeelsmiley/Library/Application Support/Workloop/Signing Backups/local-b/workloop-upload.keystore

Both backups are on this Mac. They do not constitute an offsite backup; a separate encrypted external/offsite copy is still needed.

Certificate details:
- Alias name: workloop-upload
- Entry type: PrivateKeyEntry
- Valid from: Fri Sep 04 21:06:14 BST 2026 until: Tue Jan 20 20:06:14 GMT 2054
- SHA1: 8E:4B:23:E9:76:E8:37:AA:56:55:24:15:F1:37:3D:43:3B:A3:E1:B6
- SHA256: 82:F1:D6:B8:25:8A:1F:BD:82:D4:24:A0:CC:25:E5:04:5A:65:86:8E:53:E2:E3:C3:AE:34:07:6C:B0:DE:17:08
- Signature algorithm name: SHA256withRSA
- Subject Public Key Algorithm: 3072-bit RSA key

Gradle :app:signingReport succeeds and loads the release alias and matching certificate fingerprint from the generated configuration. Firebase JSON remains absent, so actual store builds continue to fail closed until root configures it. No APK/AAB build or upload performed. An isolated release checkout must receive the ignored key.properties with permissions preserved; it points to the machine-owned external keystore.

Evidence: /tmp/workloop-android-signing-report-20260904.log; public manifest at /Users/ismaeelsmiley/.workloop-signing/signing-manifest.json. Official signing reference: https://developer.android.com/studio/publish/app-signing .

## Build10 immutable source capture (2026-09-04)

Release configuration now pins and records TAP_TO_PAY_ENABLED=false; any true value is rejected. Eleven release-tool regression tests pass. Hosted card collection is explicitly enabled for the candidate.

iOS candidate: `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201205Z/Workloop`, local commit `31b190d3f21249dc5c0dff60885da3f62a6ea47d`. 707 nonignored source files, 8,232,571 bytes, each SHA256 checked during capture.

Android candidate: `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/Workloop`, local commit `c8f4f24f72d0c5fc4b4b04c1464002b5bb9e805b`. 708 files, 8,233,577 bytes. The **only** source difference from iOS is the newly registered Firebase public Android client config `android/app/google-services.json`.

Both snapshots have sibling `source-manifest.json`, no Git remote, and a clean local source commit based on original HEAD `dbac1301674cc411a921db6a7828c3dc3c760738`. Original dirty checkout is preserved. Ignored runtime `.env` and `android/key.properties` are copied privately with mode0600 and excluded from source commits/manifests. No existing Build9 output has been overwritten.

iOS signed archive compilation is underway; no upload has been performed. Exact release logs: `/tmp/workloop-build10-ipa-20260904.log`.

### Verified signed App Store IPA10

Build completed successfully; release helper recorded provenance for clean iOS commit31b190d. Artifact: `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201205Z/Workloop/build/ios/ipa/Workloop.ipa`. SHA256 `eebf0dda5f2ee2f61e4dacb691671a9efc886d9a32e1c7c7b4da78ecb01b7746`, 34825812 bytes. Independent extracted Info.plist verifies com.ismaeel.workloop, 1.0.0 (10). `codesign --verify --deep --strict` passes. Signed entitlements and embedded store provisioning both have aps-environment=production and get-task-allow=false. Tap-to-Pay entitlement absent as intended, and no provisioned-device restriction. Profile expires 2027-08-11 21:20:30.

Verification JSON `/tmp/workloop-build10-ipa-verification.json`; normalized feature/config provenance is in snapshot `build/release/release-provenance.txt`. No upload performed. Signed development profile build is now running separately from the preserved archive/IPA.

### Required signed iOS profile validation

`flutter build ios --profile` completed successfully (130.7s) from identical iOS candidate31b190d, with .env plus explicit PAYMENT_COLLECTION_ENABLED=true, TAP_TO_PAY_ENABLED=false, APNS_ENVIRONMENT=sandbox, build-name1.0.0/build-number10. `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201205Z/Workloop/build/ios/iphoneos/Runner.app` verifies deep/strict signature, correct bundle/version/build, development APNs entitlement, device provisioning, and get-task-allow=true. The Store IPA hash remained unchanged after this build. Verification JSON `/tmp/workloop-build10-profile-verification.json`; log `/tmp/workloop-build10-ios-profile-20260904.log`.

Android AAB build started from c8f4f24 with the actual Firebase config and encrypted upload key, log `/tmp/workloop-build10-android-aab-20260904.log`. Root handles any TestFlight upload separately.

### Verified signed Android AAB10

Signed AAB build completed successfully (381.3s), with the candidate source clean before and after compilation. Artifact: `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/Workloop/build/app/outputs/bundle/release/app-release.aab`. SHA256 `d99430047ea5e3ebb4945b4613cfd2ced5de86f61afd4a43a5ebe4e9948e1dc3`, 96923578 bytes. Independent Google bundletool validation and jarsigner verification pass. Embedded manifest is com.ismaeel.workloop, 1.0.0/versionCode10, minSdk26, targetSdk36, debuggable=false. Upload-certificate SHA256 is `82:F1:D6:B8:25:8A:1F:BD:82:D4:24:A0:CC:25:E5:04:5A:65:86:8E:53:E2:E3:C3:AE:34:07:6C:B0:DE:17:08`, matching the securely generated key.

FirebaseInitProvider is present and resource google_app_id equals the registered public Android application `1:292133784446:android:04fe7da7d2ccc5597d012f`. The AAB config requests PAGE_ALIGNMENT_16K; all17 included64-bit native libraries have LOAD segment alignments at least16KB (checked using NDK llvm-readelf). This verifies packaging/alignment, not a physical16KB-device runtime test.

Evidence: `/tmp/workloop-build10-android-verification.json`, sibling `.manifest.xml` and `.bundle-config.json`, `/tmp/workloop-build10-android-aab-20260904.log`, and snapshot `build/release/release-provenance.txt`. Both platform provenance files record PAYMENT_COLLECTION_ENABLED=true, TAP_TO_PAY_ENABLED=false and the same normalized public runtime configuration hash.

The transient Kotlin compiler session file under android/.kotlin was automatically removed when Gradle finished; no source or ignore rule changes were needed. Original Build9 IPA was independently rehashed unchanged as `e8e0df6a5b657a8043049503cf5f33d7b68d760120da92eddeeff59d16145006`.

Official standalone bundletool1.18.3 is installed at `/Users/ismaeelsmiley/.cache/workloop-tools/bundletool/1.18.3/bundletool-all-1.18.3.jar`, from Google GitHub release; SHA256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`. Documentation: https://developer.android.com/tools/bundletool . Parent can derive an emulator APK set directly from this AAB to preserve compiled-source identity during QA. No APK installation, Play upload or iOS upload was performed by this agent. Parent is independently handling TestFlight distribution.

### Exact AAB10 Android emulator startup QA

Derived device-specific APKs from the verified AAB using official bundletool and the upload key, with passwords passed only through private temporary files removed immediately after signing. APK set SHA256 `2c0043b35c00f32fd0f9cfa85b32b6c49f28552ea5930e2b1c5722b4f08cf94f`; provenance and device spec in `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/android-emulator-qa`. Installed successfully on emulator-5554, Android16/API36 ARM64. Installed package reports1.0.0/code10. Cold launch succeeded in1942ms; login screen visually reviewed and accessibility XML confirms visible controls. Firebase explicitly initializes successfully. App remains alive, crash buffer empty, no FATAL or Flutter exception observed. No credentials entered or production business data written. Source candidate remains clean.

**Nonfatal runtime finding:** Android MainActivity.kt:83 eagerly initializes Stripe Terminal at Flutter engine startup despite Tap to Pay being disabled and user signed out. This logs payment-reader authentication failure (`Missing connection token`) before sign-in. Login still renders and remains stable. Recommended small fix: remove configureFlutterEngine initialization call and call initializeTerminal inside collectPayment try block immediately before Terminal.getInstance, so startup never requests Terminal credentials. Parent informed; this agent has not modified the candidate/source.

Screenshot `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/android-emulator-qa/startup.png`; accessibility `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/android-emulator-qa/startup.xml`; final startup result `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/android-emulator-qa/startup-result.json`; private process log `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T201515Z/android-emulator-qa/startup-logcat.txt`.

### Android-only lazy Terminal initialization repair

Original source MainActivity.kt now removes initializeTerminal() from configureFlutterEngine and calls it inside collectPayment’s existing try block immediately before Terminal.getInstance(). Method channel, input/permission guards, callbacks and exception handling remain intact. No Flutter/Dart/iOS/version changes. This prevents reader credential requests during signed-out startup; actual Tap-to-Pay operations still initialize before use. git diff --check passes.

New Android snapshot `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T203101Z/Workloop`, clean local commit `d3f9211474304f59d53c9a44b1a639a050fa45b8`. 708 source files, 8,233,585 bytes. Source manifest verifies the only difference from earlier Android c8f4f24 is MainActivity.kt; compared with uploaded iOS31b190d, exactly MainActivity.kt and Android google-services.json differ. Both earlier AAB and iOS artifacts are retained. New Android AAB compilation underway, versionCode10 retained because no Android candidate has been uploaded to Play.

### Final repaired Android Build10 verification

Replacement signed AAB completed in344.0s from clean d3f9211474304f59d53c9a44b1a639a050fa45b8. Artifact `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T203101Z/Workloop/build/app/outputs/bundle/release/app-release.aab`; SHA256 `cdda5308e7bae3fd274b4ab1ea569908eabcf7bad13575f97a4ae22af3a3a908`, 96925227 bytes. Bundletool validation/jarsigner pass, upload certificate unchanged, package/version1.0.0/code10 confirmed, targetSDK36/min26, debuggable=false, FirebaseInitProvider present, PAGE_ALIGNMENT_16K, all17 included64-bit native libraries align at16KB or greater.

New bundletool APK set SHA256 `19465d848ed999e72b7368b03cc8c1a60394ba9832da9b1ffa0c6bdd564386b0`. Installed on emulator-5554; all4 installed APK hashes independently match the generated set exactly. Explicit force-stop/cold-launch succeeds (2956ms). Signed-out login screenshot reviewed and accessibility controls confirmed. Firebase initialization succeeds; app stays alive; no fatal/Flutter error, no StripeTerminal log or missing connection token, and crash buffer empty. Runtime regression is resolved. No credentials entered or production business data written. Physical Android/NFC/card charging were not tested.

Final artifact validation `/tmp/workloop-build10-android-fixed-verification.json`; build log `/tmp/workloop-build10-android-fixed-aab-20260904.log`; QA evidence `/Users/ismaeelsmiley/Workloop-Releases/build10-20260904T203101Z/android-emulator-qa` contains screenshot, XML, process log, startup-result.json, APK provenance and installed APK byte verification. Both earlier AndroidAAB and iOSIPA were rehashed unchanged. New snapshot remains clean. Original source change is solely MainActivity.kt for this repair. Suggested focused commit message: `fix(android): initialize payment reader only when collecting payment`.
