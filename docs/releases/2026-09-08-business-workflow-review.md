# Business workflow review — 8 September 2026

The owner requested a thorough second pass across quotes/invoices, repeat
bookings, receipts/mileage and tax planning; deposits; coherent navigation and
data reuse; and correction of the dashboard's Tomorrow row. Profit per job is
explicitly excluded. New mobile builds remain private to the owner.

## Findings and implementation decisions

1. New documents could inherit stale business details from a previous document.
   New drafts now read current workspace/settings data. Reviewed legal details
   and payment defaults have one Invoice setup screen, accessible from Business
   and the document workflow. Existing address and customer contact columns are
   reused; private Auth contact details are not silently printed. Issued
   documents retain their original snapshot.
2. The features were appended below Money's transaction history. Invoices now
   have a main Money section beside Overview, Spent and Owed. Quotes stay with
   invoices; mileage is alongside expenses and receipts; tax planning is an
   overview action before transaction history. Client Money offers filtered
   quotes/invoices, and linked document payments open their actual invoice.
3. Deposits must distinguish the request from the receipt. A fixed or percentage
   deposit belongs to the same invoice/payment row. It does not create revenue;
   recorded receipts reduce the deposit requirement and total balance once.
4. Existing service/client details should be selectable rather than retyped.
   Unpaid booking payment adoption, document status, repeated work and dated
   manual receipt/refund handling now share connected workflows. Existing
   service/booking prices remain gross when VAT applies; a £60 job at 20% VAT
   produces £50 net + £10 VAT, not a surprise £72 charge.
5. A lost booking-save response allowed changed fields on an old retry token.
   Recovery must resend the exact submitted snapshot, avoiding self-conflict
   checks against a series that may already exist.
6. Mileage creation needed stable retry identity and recent vehicle reuse.
   Annual tax forecasts need reviewed expected annual mileage distinct from
   journeys already logged; otherwise owners would have to invent future trips.
   Account changes and pending saves must invalidate or lock the relevant inputs.
7. Physical iPhone inspection confirmed Tomorrow had smaller typography,
   different icon geometry and spacing than adjacent dashboard rows. It now
   follows their shared row rhythm; exact-booking navigation remains.
8. An open card-collection sheet retained its original deposit amount after a
   receipt elsewhere. New operations refresh the current payment; changed
   amounts require review before another tap. Lost-response retries retain
   the exact amount/key, and account switches invalidate captured actions.
9. System back could discard invoice-setup edits, a cancelled invoice could
   look paid in client history, and horizontal tab gestures trapped larger
   text layouts. Regression tests now cover the corrected behaviours.
10. Receipt attachment now offers camera, photo library and Files. Capture
    prevents simultaneous save/back and checks the opening business after
    asynchronous work. Future paid dates require correction before saving;
    existing records remain unchanged, and tax references exclude/flag them.

## Setup and novice guidance

Keep first signup short. The existing Getting started guide explains quote,
invoice, deposit, expense receipt, mileage and reviewed tax planning in their
workflow context. Invoice setup is available when first needed and saves partial
details; issuance checks required information. A legal name cannot safely be
inferred from an account's first name, and a business address does not establish
tax residence or eligibility.

## Standards used

Reviewed against primary guidance and established product documentation:

- [GOV.UK required invoice details](https://www.gov.uk/invoicing-and-taking-payment-from-customers/invoices-what-they-must-include): identifiers, supplier/customer details, description, supply/invoice dates, amounts and applicable VAT; sole-trader legal name and address.
- [FreeAgent invoice workflow](https://support.freeagent.com/hc/en-us/articles/115001219190-Create-an-invoice): saved contacts, reusable terms, payment instructions and clear draft/issue workflow.
- [Jobber mobile quotes](https://help.getjobber.com/en/articles/quotes-in-the-jobber-app/): service details, customer review and deposits as part of the work-to-payment flow.
- Tax sources and the precise supported scope remain in the expense/tax release record and the calculation screen. This is a planning estimate, not HMRC filing.

## Changed areas and purpose

| Files/area | Reason |
|---|---|
| `finance_screen.dart`, profile/settings entries, client Money | Place each workflow beside related records and preserve readable mobile navigation. |
| `business_document_defaults.dart`, its provider, `business_document_settings_screen.dart` | One current source for reviewed legal/contact/term defaults; retain issued snapshots. |
| `finance/documents/`, document repository/providers, Payment model and collection sheet | Reuse services/booking/client details, gross VAT, deposits, current balances, dated receipts/refunds, search/status/duplicate and customer PDF. |
| Booking editor/repository and dashboard Tomorrow | Stable retry payloads, exact booking/invoice handoff and shared dashboard styling. |
| Receipt capture/expense editor, mileage and tax screens/models | Native capture, stable retries, paid-date accuracy and reviewed annual forecasts. |
| Getting started guide | Explain each workflow when useful without expanding mandatory signup. |
| Four additive migrations, schema/RLS notes and SQL contracts | Reviewed defaults, annual mileage, one invoice deposit balance and private dated receipt/retry state. |
| Focused widget/unit/native fixtures and reviewed goldens | Protect calculations, isolation, interruption recovery, accessibility and native surfaces. |

## Boundaries

Tax remains the explicitly supported 2026/27 planning calculation for eligible
sole traders in England, Wales or Northern Ireland. The screen checks scope;
companies, Scotland and unsupported income/reliefs require another calculation.
It does not file with HMRC. Receipts do not automatically establish an allowable
tax expense. No profit-per-job feature was added.

PDF sharing opens the owner's system share sheet; this does not prove delivery
to a customer. Deposits use the existing card processor and ledger; no real card
charge, bank payment or customer message is sent during this review.

## Verification and delivery

The complete Flutter run passed **1,133 tests** with ten payment-capability
skips. A subsequent **83-test run with payments enabled** passed, covering the
skipped payment paths, the final timezone changes, receipt capture and legacy
receipt/refund access. Full analysis is clean. Seven changed goldens were
visually inspected before their intentional update; light/dark and 320px/2x
layouts were reviewed. The first run's fixture/expectation failures were
investigated and corrected, then rerun; no unresolved test failure is hidden.

The database replay passed **101 local migrations, 33 suites and 1,009
assertions**. All four new migrations are live with exact stored-body hashes;
58 real authenticated API checks passed, and 65 cleanup counts are zero.
Stripe v26 remains active because its existing partial-amount implementation
is semantically identical to the local endpoint. No external tester build was
assigned. See [deployment evidence](2026-09-08-business-tools-deployment.md).

Final numbered device artifact and native observations are recorded below
after installation. A passed mocked/widget test is not proof of customer
delivery, native file sharing or live payment settlement.

Suggested commit: `feat: integrate business documents deposits and expense capture`

### Owner device delivery

Normal **1.0.0 (17)** was installed and launched on the owner's iPhone 15 Pro
Max at approximately 21:21 BST. CoreDevice independently reports build 17, and
iPhone Mirroring showed the normal Today dashboard with the owner's existing
signed-in account and records. No logout, replacement account or customer-data
mutation was needed. This is a direct owner installation; build 17 was not
uploaded or assigned to TestFlight or other testers.

Live Money navigation also loaded Overview and the new Invoices section,
including the existing customer invoice, its awaiting-payment state, and the
correct missing-details guidance for Invoice setup. Existing dark appearance
was retained. Both standard iOS build-output folders were restored to the
verified normal artifact, so a later install cannot reuse the QA preview.

The signed profile build uses the production Workloop backend, payment
collection/subscriptions/crash reporting enabled, Tap to Pay disabled and
sandbox APNs matching its development entitlement. Strict deep signature,
bundle/version and entitlement checks passed. All 360 checksummed mobile and
configuration files remained unchanged between freeze and build verification.
The preserved normal app is `build/owner-preview-17/Runner.app`; the workspace's
Xcode target was restored to `lib/main.dart` after native QA.

Native checks used only a fictional invoice and an in-memory receipt fixture:

- The actual iOS share sheet displayed the correctly named fictional PDF
  (8 KB), and dismissal returned to the invoice without sending it.
- Files opened and cancelled without selecting a personal file.
- Photo library opened through Apple's private selected-photo picker and
  cancelled without importing an image.
- The receipt-specific camera permission prompt appeared. After access was
  granted, Apple displayed **“iPhone camera is not available from Mac.”**
  Cancelling the camera returned safely to the unchanged receipt screen.
  Actual shutter capture and HEIC conversion remain handheld verification
  limits; they are not claimed as physically tested.

The initial automated native launcher stalled at Xcode's wireless debugger;
its assertions are not counted as passed. A manual fixture with verified AOT
markers established the observations above, then the preserved normal app was
restored. The fixture was also corrected to resolve its mock workspace before
showing actions, matching normal app startup. No business record or native
photo was created by these checks.

Device install/launch/app receipts and signature/configuration evidence are
under `/private/tmp/workloop-build17-*`. Analysis, 1,133-test full-suite and
83-test final focused logs are under `/private/tmp/workloop-business-review-*`.
