# Crash and error diagnostics — 6 September 2026

## Scope and current evidence

The launch checklist previously had no remote crash reporter. The candidate now
uses the existing Workloop Firebase project through `firebase_crashlytics` 5.3.0.
This is implemented source with focused verification, not evidence that a new
build has reached TestFlight or that a real iPhone report has reached Firebase.
Native builds, a deliberate device report, console receipt and symbolication
remain pending the parent release verification.

Flutter Lead, System Integrator and QA Reviewer guided the change. Existing
Firebase initialization, app navigation, user/workspace state and business data
flows are preserved. No new provider account, paid service, database table,
backend endpoint or analytics system was created.

## What reports contain

Uncaught framework and root-isolate Dart failures pass through one adapter. It
sends a fixed error category and a bounded allowlist of static code frames or
AOT addresses/build ID. It does not pass the original exception string, Flutter
context, information collector, HTTP request/response, URLs, headers, customer
names, notes, amounts, custom user IDs, custom logs, or screen/activity events.
Missing/unrecognized stacks remain unavailable rather than inventing a source
location. Repeated identical code failures are deduplicated, and Dart reporting
is capped at 20 distinct failures per app launch.

Crashlytics also captures native SDK/OS crash diagnostics, app/build and device
technical information, and installation/session identifiers. These are not
anonymous simply because Workloop does not set a user ID. Native reports cannot
be scrubbed by the Dart adapter. Do not describe the feature as collecting no
data, as recording user actions, or as proving all errors/slowdowns are covered.
Handled application errors and child-isolate errors are not automatically routed
through this root handler. No Firebase Analytics package/breadcrumbs were added.
The App Privacy submission and privacy policy must reflect the native provider's
actual data categories; the launch/legal owner handles that companion update.

## Initialization and build control

- The app installs its handlers while the existing Firebase initialization is
  pending. Early Dart reports wait for that result without delaying app startup.
- Previous Flutter error presentation and platform error-handler behavior remain
  intact. Reporting is not error recovery; it must not hide broken operations.
- Initialization and transport errors are contained with bounded waits and are
  never recursively reported. A Firebase failure does not block app use.
- `WORKLOOP_CRASH_REPORTING_ENABLED=true` enables the adapter only in profile or
  release mode. Debug Dart reporting is always off. Normal local `.env` builds
  remain off unless the flag is explicitly supplied.
- Native plist/manifest collection defaults are false. Disabled initialization
  explicitly disables collection and deletes unsent reports; enabled builds keep
  previous native crash reports so they can be delivered on the next launch.
- The native SDK's runtime collection override persists across launches. When
  installing an off/debug build over a previously enabled build, the adapter
  disables it after Firebase initializes; it cannot retract a report already
  uploaded in the native initialization interval. Use a fresh diagnostic install
  where strict separation of local and production native reports is required.

Production `scripts/release_config.py` defaults the flag to **true** for this
authorized launch and preserves an explicit boolean/string `false` for a
reviewed rollback. Invalid values and unknown test/debug flags fail before a
store build starts. Provenance records `crash_reporting_enabled` alongside the
existing payment/APNs choices and the public configuration hash. No test-crash
flag was added to the production configuration allowlist.

## Native symbols

Firebase uses Flutter's Swift Package Manager integration in this checkout.
The last Runner build phase invokes Firebase's official uploader from either
Xcode's DerivedData or Flutter's custom build directory, with a CocoaPods fallback
for a future installation-method change. Its standard dSYM, plist and executable
inputs are declared. All build types generate dSYMs; uploading only runs for
Profile/Release physical-device builds. A missing uploader or native validation
failure fails the phase visibly. Debug and simulator builds skip upload.

The official `run` script validates synchronously and uploads in the background.
A successful build therefore does **not** prove Firebase received the symbols;
verify a readable report in the intended Firebase app. Keep the archive/dSYMs
associated with the released build. Android adds the standard Crashlytics Gradle
plugin 3.0.8 after the existing Google Services setup. Obfuscated Android Dart
builds would additionally require the documented Flutter symbol-upload step;
this change does not turn obfuscation on.

## Files and reasons

| Files | Change |
| --- | --- |
| `lib/shared/diagnostics/crash_reporter.dart` | Small injectable SDK boundary, safe categories/frames, bounded startup/transport and global handler lifecycle. |
| `lib/main.dart` | Attach reporting to existing Firebase initialization before Supabase startup completes; no route/auth changes. |
| `pubspec.yaml`, `pubspec.lock` | Crashlytics plugin and its platform interface only; existing Firebase Core/Messaging retained. |
| `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` | Native collection starts disabled. |
| `ios/Runner.xcodeproj/project.pbxproj`, `ios/scripts/upload_crashlytics_symbols.sh` | Correct SPM upload phase, declared symbol inputs and dSYM generation. |
| `android/settings.gradle.kts`, `android/app/build.gradle.kts` | Standard Crashlytics Gradle integration alongside the existing Firebase resources. |
| `scripts/release_config.py`, `scripts/tests/test_release_tools.py` | Explicit validated production capability and provenance, no diagnostic flags. |
| `test/crash_reporter_test.dart` | Privacy, gates, initialization, forwarding, deduplication and failure safety. |
| `scripts/tests/test_crashlytics_symbols.py` | Native phase directory/skip/failure checks with fake uploaders and no network. |
| `integration_test/crash_reporting_smoke_test.dart`, `test_driver/crash_reporting_driver.dart` | Standalone profile-only device verification; not imported by the app and not part of normal unit tests. |

## Verification completed

- Scoped Dart analysis: clean for the reporter, bootstrap, focused tests and
  integration probe. Plist/project lint and `git diff --check`: clean.
- `flutter test test/crash_reporter_test.dart --dart-define-from-file=.env
  --dart-define=WORKLOOP_CRASH_REPORTING_ENABLED=true`: **16 passed**. This
  deliberately supplies the flag to prove debug mode still cannot report.
- `python3 -m unittest discover -s scripts/tests -p test_release_tools.py`:
  **14 passed**, including default enablement/provenance, explicit disablement,
  invalid flag rejection and test/debug flag rejection before compilation.
- `python3 -m unittest discover -s scripts/tests -p test_crashlytics_symbols.py`:
  **5 passed**. No real symbol or crash report was sent by these tests.
- Flutter output: `/tmp/workloop-crash-reporting-focused.log`.

The normal Flutter suite, native SDK builds, signed artifact inspection and live
console/device report remain pending integration. Do not combine prior app test
counts with these changes until the combined candidate is verified.

## Device and release commands

For a normal development-signed profile candidate that exercises the production
reporting path (no forced error):

```sh
source scripts/dev_env.sh
flutter build ios --profile --dart-define-from-file=.env \
  --dart-define=WORKLOOP_CRASH_REPORTING_ENABLED=true
```

For the explicit, data-free diagnostic probe on an unlocked iPhone:

```sh
source scripts/dev_env.sh
flutter drive --profile \
  --driver=test_driver/crash_reporting_driver.dart \
  --target=integration_test/crash_reporting_smoke_test.dart \
  --dart-define=WORKLOOP_CRASH_REPORTING_ENABLED=true \
  -d '<connected iPhone ID>'
```

The probe refuses debug/release mode, initializes Firebase without signing into
Workloop, and submits one fixed-category sanitized fatal-style Dart event. It
does not deliberately terminate the process and does not claim delivery. Verify
its app/build and readable integration-test stack in Firebase, then reinstall the
normal app entry point. Test a real native process crash separately if the release
owner needs to establish next-launch native crash delivery as well.

The reviewed clean-checkout release path remains:

```sh
RELEASE_DEFINES_FILE='<production public config path>' \
RELEASE_PAYMENT_COLLECTION_ENABLED='<reviewed true or false>' \
RELEASE_PLATFORMS=ios bash scripts/qa_signed_builds.sh
```

That path adds the default-on reporting capability to its normalized private
configuration snapshot. It neither uploads the artifact nor bypasses existing
dirty-checkout, signing, archive-preservation or payment gates.

## Sources and follow-up

Implementation follows the official [Flutter setup](https://firebase.google.com/docs/crashlytics/flutter/get-started),
[collection control](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports),
[Apple symbol phase](https://firebase.google.com/docs/crashlytics/ios/get-started),
[readable native reports](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports),
[Android Gradle setup](https://firebase.google.com/docs/crashlytics/android/get-started),
[Flutter error handling](https://docs.flutter.dev/testing/errors), and
[Firebase data practices](https://firebase.google.com/support/privacy).

Follow-up: complete the live report/symbol proof, review App Privacy and public
policy against the included SDK, retain symbols per shipped artifact, then run
the normal public-launch workflow/device checks. Crash reports diagnose faults;
they do not replace payment, sign-in, notification or customer workflow testing.

Suggested commit: `Add privacy-limited Firebase crash diagnostics and release gates`.
