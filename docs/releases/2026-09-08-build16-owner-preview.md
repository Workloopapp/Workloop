# Build 16 — owner preview, 8 September 2026

The owner approved backend deployment and installation on their iPhone, then
explicitly restricted the new build to themselves: **do not release it to the
existing testers yet**. No external beta assignment or public App Store
submission is authorised by this rollout.

## Source and artifacts

- Version **1.0.0 (16)**; bundle `com.ismaeel.workloop`.
- Main checkout remains dirty and uncommitted, with its existing work preserved.
  Only release version/fallback values and release documentation changed after
  the completed feature implementation.
- Isolated source:
  `/Users/ismaeelsmiley/Workloop-Releases/build16-20260908T190950Z/Workloop`.
  Local frozen commit `03f5923bb5e6c1c55d7f487db30864021ca23036`; no GitHub push.
  The source manifest records every copied file and checksum. All 533 mobile,
  asset and test files checked still match the verified working implementation.
- Production configuration retains payment collection, subscriptions and crash
  reporting enabled; Tap to Pay disabled; production APNs. Public configuration
  SHA-256 `2a5d4f056113a5abcf3031a0021235f9c3d856bc36e9759aa4744a85b0a63bce`.
- The distributable IPA and the exact package subsequently uploaded by Xcode
  both passed strict deep signature, bundle/version and entitlement checks:
  production APNs and `get-task-allow=false`.
- Exact uploaded IPA: `uploaded-Workloop.ipa` under the release folder,
  37,084,701 bytes, SHA-256
  `b15436b6ca9916517c4f8712021d27792e040ad6dd2b0203e9976b833a24917c`.
  Xcode's upload re-export differs from the initial local IPA; both artifacts
  and their verification records are retained rather than conflating hashes.

## Backend and hosted verification

All three feature migrations were applied, their stored statement hashes match
the tested source, and only those new local timestamps were aligned to hosted
history. `complete-account-deletion` v31 is active with JWT protection and the
exact receipt cleanup helper. See [deployment evidence](2026-09-08-business-tools-deployment.md).

Two isolated authenticated QA accounts exercised real private receipt
upload/download with byte hashes, tenant isolation, MIME/size guards, metadata
binding, deletion guards and actual object cleanup. Mileage/tax data round-trips,
quote acceptance/conversion, invoice issuance, idempotent partial payments and
finite booking retries across daylight saving also passed. The exact deployed
cleanup helper ran against real Storage twice successfully.

All QA accounts, sessions, workspaces, records, objects and outbox entries were
confirmed absent after cleanup; temporary credentials were removed. No customer
message or monetary transaction was sent. See [hosted smoke details](2026-09-08-expense-records-tax.md).

Previously fetched URLs may briefly return a CDN-cached response after origin
deletion. Fresh authenticated requests confirmed `NoSuchKey`; the other tenant
remained denied. The full privileged deletion endpoint's successful lifecycle
was not invoked because its separate administrator token was unavailable; its
401 rejection, exact deployed bundle and cleanup helper were checked separately.

## Physical iPhone

The iPhone 15 Pro Max became reachable over Wi-Fi after the owner connected it.
CoreDevice installed the app successfully and reported **1.0.0, build 16**.
Launch succeeded at approximately **20:11 BST**. The device build is a signed
profile build using sandbox APNs to match its development entitlement; it is
separate from the production-signed package sent to Apple.

iPhone Mirroring confirmed Money's new tools, live invoice list, new-invoice
editor, tax screen with loaded references, mileage list and receipt attachment
control. No invoice was saved and no existing expense was changed during these
read/navigation checks. The owner resumed using the iPhone while the receipt
picker check was starting, which ended mirroring; picker completion and native
PDF sharing are therefore not claimed as verified. Existing automated invoice
screen tests, PDF visual checks and hosted receipt operations are separate proof.

Device install, launch and queried build receipts are retained as
`/private/tmp/workloop-build16-device-install.json`,
`workloop-build16-device-launch.json` and `workloop-build16-device-app.json`.

## Apple upload and access

Xcode upload succeeded at **20:17:08 BST**. App Store Connect processing
subsequently completed and the upload row displays **Complete**. The known StripeTerminal vendor dSYM warning was
nonblocking; it limits symbolication for that framework.

The existing internal group initially had zero testers. Only the account holder,
Ismaeel Smiley, was added; the UI confirms **one tester**. Internal distribution
is automatic for Xcode builds. The external **Workloop Private Beta** group is
unchanged, with build 15 remaining its newest assigned build. Build 16 has not
been assigned or submitted to that external group.

Build 16's details confirm exactly **one group: Workloop Internal Beta, Internal,
one tester**, with zero individual testers and no external group. Private preview
notes were saved successfully. The general build-list status is **Ready to Submit**
for external review; no external submission was made. The internal group now
shows **one tester and 11 builds**, with the owner's status **Invited**. Acceptance
of the TestFlight invitation and installation through TestFlight are not claimed;
the successful direct device installation is recorded separately above.

A final read-only check of the external group's Builds tab confirmed its six
assignments: **15, 12, 11, 10, 6 and 5**, all in Testing. Build 16 is absent.

## Validation

Feature implementation: 1,065 full-suite Flutter tests passed, with six default
capability skips separately exercised in a seven-test payment-enabled run;
928 isolated database assertions passed. Final numbered source analysis is clean.
Signed device profile build and frozen distribution archive/export both passed.
The frozen release preflight and artifact provenance recording passed, and
`git diff --check` is clean.

Suggested commit: `feat: release business tools as owner-only build 16`.
