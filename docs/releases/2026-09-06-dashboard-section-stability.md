# Stable dashboard section loading — 6 September 2026

The owner reported that At a glance briefly appeared immediately below the
booking card, then moved down when Needs attention arrived.

## Cause and correction

Dashboard attention is computed from five asynchronous collections and the
business clock. Its loading branch removed the section while the lower overview
rendered unconditionally. A cold load or dependency refresh could therefore
briefly present an unknown attention result as if it were empty.

The dashboard now shows a neutral, accessible loading placeholder and withholds
the setup checklist/At a glance until the first attention check settles. A
confirmed empty result still omits Needs attention. On a same-workspace refresh,
it retains the already accepted provider value, including a confirmed empty
list. Failed refreshes retain that last result with explicit retry feedback;
initial errors still show their own error/retry state. The initial setup-choice
read also settles before lower content is revealed, and refreshes retain the
known checklist choice/progress rather than inserting a temporary checklist.

The widget remembers only the workspace identity for an accepted successful
attention result, not a second copy of business data. The marker clears when
the workspace changes. A new dashboard does not opt into previous values from
a pending provider belonging to an earlier workspace. Existing providers,
repositories, exact record routes and resolved visual design remain intact.

## Files and reasons

- `lib/features/dashboard/dashboard_screen.dart`: distinguish unknown initial
  attention from a resolved empty result; preserve same-workspace layout during
  refresh; wait for initial setup-choice readiness.
- `test/dashboard_section_loading_test.dart`: staggered real-provider regression
  coverage, including empty/error/retry, actual pull-to-refresh, delayed setup
  choice and workspace changes.

No schema, provider configuration, messages, notification preferences, TestFlight
upload or Play upload is changed by this fix.

## Verification

The original six-case reproduction produced **four failures** before the source
fix: early overview during delayed/empty initial checks, disappearing prior
attention during refresh, and premature lower content after a workspace switch.
The extended regression suite and existing dashboard navigation/workspace suites
then passed **26/26**. Scoped analysis passed. Full-app and native results will
be appended when complete.

Suggested commit: `Keep dashboard sections stable while data loads`

## Final verification receipt

- `flutter analyze`: no issues found.
- `flutter test --dart-define-from-file=.env`: **827 passed, six
  configuration-dependent skips**. The skipped payment cases were exercised
  with card collection enabled in the separate **18/18** payment suite.
- The focused dashboard section/navigation/workspace suites passed **26/26**,
  including all **11** new loading regressions. Existing resolved-screen
  goldens passed without image changes.
- `git diff --check`: passed.
- iOS profile build: passed, **74.1 MB**; strict deep code-signature verification
  passed. Android profile build: passed, **163.1 MB**. Both use the existing
  payment-enabled, Tap-to-Pay-disabled configuration; iOS uses development
  push credentials for the local install.
- The updated **1.0.0 (12)** app installed on the owner's iPhone on
  **6 September 2026 at 01:37 BST**. Launch at **01:37:51** was denied because
  the iPhone was locked (`RequestDenied / Locked`). iPhone Mirroring also
  reported that the Mac was locked. Installation is confirmed; physical
  observation of the dashboard transition remains pending.
- No TestFlight or Play upload, backend deployment or live-message send occurred.

Artifact SHA-256:

```text
iOS Runner: 5eb9cbe01b0262b42ca6662eabd7f3471acf3666c51377fb2c6d6efaa3149d5d
Android APK: 47dc4e7cb3947cbaf9b04b0af5e45a51033f3de59d5029e3efc7cbc0d8b172fc
```

The remaining check is opening Today on the physical iPhone, returning from
another tab and pulling to refresh. The change preserves the last successful
same-workspace attention result during refresh; a refresh failure explicitly
labels that result as the last update and provides Retry.
