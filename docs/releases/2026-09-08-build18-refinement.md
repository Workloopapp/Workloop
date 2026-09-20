# Build 18 — documents, receipt reading and Money refinement

8 September 2026. Owner-only update; no external testing distribution is authorized.

## Changes

- Documents open in Workloop. Quotes and invoices preview their generated PDF;
  attached receipts show their saved PDF/image; the tax report is readable
  before sharing. The shared viewer supports scrolling, zoom and secondary export.
- Receipt photos/PDFs are read locally. Suggested amounts, dates, supplier and
  reference details require review; existing entries remain unless selected.
  Supplier/reference details reuse expense notes, so no schema was added.
- Money leads with outstanding payments, then received/spent/net figures and
  recent activity. Planning, tax and setup follow. Fresh accounts show honest
  empty states. Invoice, expense and tax labels wrap above input outlines.
- Sign-up messaging handles the service's intentionally ambiguous duplicate
  sign-up response without falsely promising that an email was sent.

## Account-deletion incident and repair

The owner's attempted fresh signup revealed an existing deletion failure:
Stripe rejected closing an independently owned Standard live account with
`stripe_loss_liable_cannot_be_deleted`. The old identity remained banned while
its deletion was pending; repeat signups therefore sent no confirmation email.

The tested correction disconnects Standard accounts from Workloop through
Stripe OAuth deauthorization when that specific provider response requires it.
Other errors fail closed. An exact account/request/owner/workspace audit
checkpoint is recorded before local deletion, using the existing server-only
audit table. Other account configurations retain the verified close workflow.
No database migration or access-policy change was needed.

Automatic approval review initially rejected deployment because the deletion
service affects all users. The owner explicitly approved deploying the fix.
`complete-account-deletion` version 33 is live with gateway JWT verification and
its existing admin-token check; all seven deployed source files match the reviewed
bundle. The configured live Connect client ID was read from the platform's
existing Stripe OAuth settings. The scheduled worker completed the owner's
pending request at 20:53:12 UTC. Separate queries verified the old Auth identity
and workspace are absent, with one confirmed Stripe-access-revocation checkpoint.

If Stripe successfully disconnects an account but the response or first database
checkpoint is lost, automatic retries fail safely and require operator
reconciliation. The repair does not claim that external-call-to-database window
is atomic. Test-mode Standard disconnection needs its matching Connect client ID;
normal test-account closing remains supported.

Sources: [Stripe OAuth disconnection](https://docs.stripe.com/connect/oauth-reference),
[Stripe account closure](https://docs.stripe.com/api/v2/core/accounts/close).

## Native implementation and privacy

`ios/Runner/ReceiptTextBridge.swift` uses Apple Vision and PDFKit. It recognizes
rendered PDF pages even when they also contain embedded text, avoiding missed
scanned receipts beneath a searchable heading. Android's `ReceiptTextBridge.kt`
uses bundled ML Kit Latin recognition and PdfRenderer. No receipt is sent to an
OCR service. Android's private temporary PDF handle is deleted after use.
Recognition composites transparent image pixels onto white, so exported PNG
receipts remain readable; it does not replace or modify the saved attachment.

Both implementations enforce the existing 10 MiB source limit, bound image
resolution, read at most five PDF pages, and explicitly report partial/truncated
results. Locked, malformed, unreadable, foreign-currency, ambiguous and credit
receipts retain a manual path. Account/workspace changes invalidate pending
recognition and viewing, including retained callbacks.

Sources: [Apple Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images),
[Google ML Kit](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).

## Changed areas

- `lib/shared/documents/workloop_document_viewer.dart`: one private viewer reused
  by document details, receipts and tax reports.
- `lib/features/finance/receipt_*`, `expense_editor_screen.dart` and
  `expense_receipt_section.dart`: local recognition, conservative parsing,
  reviewed autofill and existing expense-save/attachment workflow.
- Finance screens/summary widgets, `workloop_form_field.dart`, `slate_ui.dart`
  and Invoice setup: shared hierarchy, external field labels and large-text controls.
- Auth screen/validation: conditional signup and unavailable-account guidance.
- Native iOS/Android bridges and dependency registration: platform recognition
  and PDF raster support. `printing` 5.15.0 reuses the existing PDF generator.
- `AppDelegate.swift` and `StripeTerminalBridge.swift`: register plugins and all
  three custom channels in Flutter's implicit-engine callback for the existing
  UIScene lifecycle, using the engine messenger rather than an unavailable
  launch-time window. The initial simulator test caught the missing channel;
  the correction also covers the existing payment and notification-settings
  channels. See [Flutter's UIScene migration guidance](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).
- `stripe_account_offboarding.ts` and `complete-account-deletion/index.ts`:
  provider-correct Standard disconnection and durable audit evidence.

## Verification record

- Eight real local Vision fixture checks passed: JPEG, PNG, transparent PNG,
  scanned multi-page PDF, hybrid PDF, locked PDF, empty data and malformed image.
- Edge Function suites passed: 149 core tests and 36 subscription tests, using
  their required fixture permissions/import maps. Nine offboarding tests are
  included; an independent owner/offboarding run also passed twelve tests.
- Full Flutter suite: 1,190 passed with ten capability skips. The separate
  payment-enabled suite passed all eleven cases. Final analysis and diff checks
  were clean. Earlier stale Money assertions/goldens were corrected and visually
  reviewed before the final full run.
- Android native Kotlin compilation succeeded. This verifies the bundled ML Kit
  integration compiles; it is not Android device/runtime evidence.
- The final isolated iOS simulator integration passed: actual PDF rasterization,
  native searchable-PDF and transparent-PNG recognition, displayed PDF image and
  read-only simulated payment-bridge availability. It uses synthetic receipts
  and an isolated fixture with no account/backend access. This caught and fixed
  the UIScene registration and transparent-image recognition issues before the
  owner build. It does not prove physical camera capture or live payments.
- Focused document-viewer, OCR/review, Money, auth, invoice/client and tax suites
  passed; see the linked feature reports. After the native corrections, final
  analysis remained clean and all 26 affected startup/navigation checks passed.

## Signed owner build and installation

The normal `lib/main.dart` profile build **1.0.0 (18)** compiled successfully.
Deep/strict code-signature verification passed. Its development APNs entitlement
matches the sandbox runtime setting; `get-task-allow=true` is the expected owner
development build setting. All 409 recorded source/asset files matched their
pre-build hashes after compilation. The preserved app and manifest are under
`build/owner-preview-18/`; the AOT binary SHA-256 is
`ecf3bb2651458625f3ede751d49bff7b26b7f5297ee438865e839ec5e90d000b`.

CoreDevice installed the app on the owner's paired iPhone at 22:18 BST, launched
the normal app, and independently reported bundle `com.ismaeel.workloop`,
version **1.0.0**, build **18**. No simulator fixture was installed on the owner
phone. No TestFlight upload, tester assignment or public submission occurred.

The final physical screen walkthrough was unavailable because iPhone Mirroring
reported the phone in use. Native PDF/OCR proof above is from the isolated iOS
simulator and real local Vision engine, alongside visually reviewed Money/tax
and document widget checks. Physical camera/HEIC/native-share checks and Android
OCR runtime remain distinct manual validation limits; no live payment was made.

Evidence logs: `/private/tmp/workloop-build18-flutter-final.log`,
`/private/tmp/workloop-build18-payment-enabled.log`,
`/private/tmp/workloop-build18-ios-native-verified.log`,
`/private/tmp/workloop-build18-native-ocr-final.log`,
`/private/tmp/workloop-android-receipt-alpha-compile-online.log`,
`/private/tmp/workloop-build18-analyze-verified.log`,
`/private/tmp/workloop-build18-native-startup-regression.log`,
`/private/tmp/workloop-build18-ios-profile.log` and the `workloop-build18`
install/launch/device-app JSON receipts in `/private/tmp`.

See [document viewing](2026-09-08-document-viewing.md) and
[receipt/tax implementation](2026-09-08-expense-records-tax.md).

Suggested commit: `feat: refine Money with in-app documents and reviewed receipt autofill`
