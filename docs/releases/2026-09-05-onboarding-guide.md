# Onboarding and first-use guide — 5 September 2026

The existing seven setup steps and atomic workspace creation are retained.
The step header now names the current step and its position. Mobile Valeting &
Detailing is an occupation with editable service suggestions. Other opens a
required free-text occupation (up to 80 characters); the actual occupation is
saved in the existing industry field, including in local account-scoped drafts.
No database field, occupation enumeration or new email trigger is required.

Setup recovery now preserves profile edits before Continue, preserves deliberate
empty service selections, and removes a previously chosen first booking when
the owner skips it or removes its service. An old draft date cannot make the
date picker assert. The completion screen stays visible after save until the
owner chooses to enter the workspace or open the requested import flow.

`FirstUseGuideGate` belongs around the verified MainShell with the current
account and workspace IDs. Only the explicit onboarding completion action arms
the introduction. Existing accounts have no introduction marker and are not
interrupted. The guide covers Today, Clients, Work, Money and Business, using
the existing Quiet + Warm illustrations. Real action shortcuts open the existing
client/booking editors and Money/Business/Today routes. No demo data is inserted.

Guide progress is a non-critical local preference scoped to account and
workspace. Skip, close, swipe dismissal or restarting the app does not cause
another automatic prompt. Settings → Getting started resumes an interrupted
guide or replays a completed one. Start over is available within the guide.
This device preference is separate from business readiness and from marketing
or customer email choices; clearing app storage can clear guide progress.

The owner email setup predicates remain: missing workspace, then missing active
service, then missing client, then missing booking. Guide progress and occupation
labels do not pretend any of these real records exist. Skipping services or a
first booking therefore continues to trigger the appropriate existing help.

Verification: targeted static analysis passed. Twenty scoped Flutter tests
passed across guide persistence, account/workspace isolation, skip/resume/replay,
real editor links, compact 2× text, custom occupation restoration, valeting RPC
mapping, skip clearing, completion navigation, existing onboarding layout and
handle retry tests. MainShell/Settings integration and full build belong to the
combined pass. No TestFlight upload or live customer data mutation.

Suggested commit: `Improve onboarding and add resumable getting-started guide`.
