# App Store preparation — 12 September 2026

Public release was requested, then explicitly paused by the owner to finish the
free-trial and monthly-subscription setup. Nothing was submitted for public App
Review and no public release occurred.

## Verified candidate

Current root source passed `flutter analyze`, all 1,349 Flutter tests (one skip),
and `flutter build ios --profile --dart-define-from-file=.env`, after sourcing
`scripts/dev_env.sh`. All 1,219 recorded inputs still matched the root when
preparation was paused. Existing uncommitted work was preserved.

An independent snapshot under `build/appstore-launch-20260912/candidate/Workloop`
was committed locally as `ffa24b0aa7cfd3dfdf0c9ecad916706f07667ef5` on
`codex/appstore-candidate-20`. Only that snapshot's pubspec and app-info fallback
were advanced to build 20; the root retains its prior version. Its App Store
archive/export passed `qa_signed_builds.sh`, strict deep code-sign verification,
production APNs, `get-task-allow=false`, iPhone-only device family, bundle/version
and App Store provisioning checks.

The prepared IPA is 37,684,621 bytes, SHA-256
`f193869db2ae5845dee8b581c680437fa45b5df2713bf032470395d4fe1176de`.
Xcode uploaded a fresh export of the same archive and reported `EXPORT SUCCEEDED`
at 15:57:32 BST. This hash identifies the prepared export, not Xcode's separately
signed upload package. Apple processing completion has not yet been verified.
The existing nonfatal StripeTerminal vendor dSYM warning remains.

## Apple and public-site preparation

- Apple showed build 19 as the latest available build before candidate 20 upload.
- Six current Flutter renders with fictional fixtures were visually checked,
  encoded as 1290 × 2796 RGB PNGs and uploaded to the 6.9-inch screenshot set.
  Saved order: Today, Clients, Money, Work, Business, Booking page. They are
  widget renders of current source, not a claim of physical-device workflow QA.
- Copyright was saved as `2026 Haani Enterprise Limited`.
- Privacy, terms, support and account-deletion URLs returned HTTP 200.
- App Privacy's collected-data categories were saved as a draft. Per-category
  usage/linkage/tracking questions remain unfinished and nothing was published.
  The candidate's SDK privacy manifests are recorded in the evidence directory.
- The owner accepted the updated Developer Program License Agreement; Apple
  subsequently showed the Free Apps Agreement as Active. The separate Paid
  Apps Agreement is still required for subscriptions at the last inspection.
- Public version 1.0 remains Prepare for Submission with manual release. No
  build has been selected for public review and reviewer fields remain open.

## Subscription work now takes priority

The live backend is healthy, with beta access open, enforcement off, Apple and
Google sales disabled, and zero recorded store transactions. Its existing trial
is 720 hours without payment details. The owner now requests one month free,
followed by a monthly subscription. Confirm the intended Apple introductory
offer versus the existing card-free trial before changing billing semantics.
Existing planned monthly price is £14.99. Public release stays paused.

Evidence and logs: `build/appstore-launch-20260912/`. No root commit or push,
production database mutation, subscription activation or live charge occurred.


## Subsequent owner decision

The owner approved the one-month Apple introductory offer followed by automatic £14.99 monthly renewal and asked for the complete customer journey. Implementation and verification now live in `2026-09-12-apple-trial-customer-journey.md`. This decision supersedes the pending choice above; public release remains paused.
