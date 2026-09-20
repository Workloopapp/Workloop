# Privacy disclosure preparation — 9 September 2026

This is a source-based update to the [6 September App Privacy worksheet](2026-09-06-ios-store-submission.md#app-privacy--source-based-answer-worksheet), not a submitted or certified Apple questionnaire. The release operator observed App Store Connect still showing **Get Started** for App Privacy and app version 1.0 still **Prepare for Submission** on 9 September; the missing privacy URL was saved separately. No earlier labels have been submitted. Completing public App Store submission is separate from the current TestFlight and website release.

## Receipt, document and tax additions

For these feature flows, the draft answers are **collected when the feature is used**, **linked to the user**, **App Functionality**, and **not used for tracking**. Saving to private storage still counts as off-device collection: records and objects are associated with the authenticated workspace. Optional capture does not make saved data uncollected.

| Apple category | Current source and change from the worksheet |
| --- | --- |
| **Photos or Videos** | **New category to include:** saved JPEG/PNG receipt photos upload to Supabase Storage. The September 6 statement that no targeted Photos/Videos collection existed is superseded. This feature accepts photos, not videos. |
| **Other User Content** | Retain for selected PDF receipts, supplier/reference notes, quote/invoice descriptions, document terms, mileage purpose/vehicle descriptions and other business records. |
| **Other Financial Info** | Retain for invoice/deposit/payment/refund amounts, recorded spending, reviewed annual turnover and expense forecasts, tax payments already made, reserves and mileage estimates. The estimate does not collect a bank feed, HMRC login or National Insurance number. |
| **Payment Info** | Retain. In addition to the existing payment-enabled Stripe rationale, invoice setup explicitly invites account name, sort code and account number in payment instructions. Those instructions are saved in workspace settings and document records, independently of Stripe availability. |
| **Purchase History** | Retain for service transactions/business expenditure and, when purchased or restored, Workloop store product/transaction/expiry/refund records linked to the account. Declaring this category does not establish that public subscriptions are available. |
| **Name, Email Address, Phone Number, Physical Address, User ID** | Retain the relevant existing categories for business/customer document snapshots, supplier/contact information and account/workspace association. Mileage is a manually entered log; it adds no automatic GPS collection. |

OCR raw text remains on the device and is not persisted or sent to an OCR service. The owner-reviewed amount/date/note fields become ordinary expense data; the selected receipt attachment is uploaded only through the existing save path. Reading or viewing alone does not upload a newly selected receipt. PDF generation/viewing does not introduce advertising, analytics or cross-app matching.

The remaining worksheet categories and purpose distinctions are unchanged by these additions. In particular, retain the existing account-email marketing/personalization purposes where applicable; do not apply them to receipt or tax data. Build 19 enables Crashlytics, so the worksheet's **Device ID, Crash Data and Other Diagnostic Data** entries remain relevant. Its more complete diagnostic mapping supersedes the older generic `StoreSubmission.md` row describing diagnostics as support-only. Absence of an assigned Workloop account ID does not establish that installation/session diagnostics are anonymous. Final whole-app SDK/category review still belongs to public submission.

## Public subscription wording

The current public source correctly describes **planned launch pricing**: a 30-day trial, then **£14.99/month or £149.99/year**; public subscriptions are not available yet, and joining the launch list starts neither a trial nor a paid plan. Existing beta lifetime access is restricted to the existing cohort.

These prices match `WorkloopPlans`. A subscription-enabled build only includes the client: purchase controls also require the server's platform sales flag and available store products, and use the store-returned localized price. The inspected release documents do not establish a completed genuine purchase/restore/renewal/refund lifecycle or current public product availability. Do not replace planned/private-beta wording with a buy-now or live-paid-plan claim on this evidence alone. The app and static privacy mirror already disclose store transaction/access verification separately from Stripe customer payments.

## Source anchors and scope

- [Receipt validation/private upload](../../lib/features/finance/expense_records_repository.dart): JPEG/PNG/PDF originals or saved photo copies, metadata and workspace paths.
- [On-device OCR contract](../../lib/features/finance/receipt_text_service.dart) and [review before applying](../../lib/features/finance/receipt_review_sheet.dart).
- [Stored tax inputs](../../lib/features/finance/tax_estimate.dart) and [document bank instructions](../../lib/features/settings/business_document_settings_screen.dart).
- [Document snapshots](../../lib/features/finance/documents/business_document.dart) and [payment-instruction persistence](../../supabase/migrations/20260908200023_business_document_defaults.sql).
- [Current privacy notice and subscription-access disclosure](../../lib/features/settings/legal_document_screen.dart), mirrored in [web privacy](../../web/privacy.html).
- [Subscription plan constants/server flags](../../lib/features/subscription/subscription_access.dart) and [store-gated pricing controls](../../lib/features/subscription/subscription_screen.dart).
- [Build 19 artifact flags](2026-09-09-build19-testflight.md) and [diagnostic boundary](../../lib/shared/diagnostics/crash_reporter.dart).

Website source checked: `/Users/ismaeelsmiley/Documents/Workloop Website/app/lib/pricing.ts`, `app/pricing/page.tsx`, `app/page.tsx` and `app/early-access/page.tsx`. No browser, provider mutation, questionnaire submission, live purchase or broad new audit was performed for this preparation. Beyond the newly required receipt-photo category and expanded evidence for existing financial/content categories, no further new category was established by this bounded review.
