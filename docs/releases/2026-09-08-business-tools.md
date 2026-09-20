# Connected business tools — 8 September 2026

The owner approved all four phases: connected quotes/invoices, recurring
bookings, receipt/mileage records and a scoped UK sole-trader tax estimate.
These extend the existing booking, Money and expense workflows.

## What changed and why

- **Quotes and invoices:** Money offers document creation and a document list;
  a booking without an existing payment also opens the invoice editor. Drafts
  hold itemised work, customer/business details, dates and payment instructions.
  Issuing freezes the snapshot and assigns a business-specific number. A quote's
  recorded acceptance can become an invoice draft. PDFs are generated locally
  and handed to the device share sheet. Sharing does not assert delivery.
- **Connected payments:** an issued invoice creates exactly one existing Money
  record. Manual partial payments and existing Stripe collection use that same
  balance. Receipt movements preserve each collection/refund date for Money,
  profit, monthly targets and the business feed. Drafts and quotes never become
  amounts owed. Older ordinary payment records retain their existing semantics.
- **Recurring bookings:** weekly intervals of one to four weeks create 2–24
  ordinary bookings in one transaction. Saved business timezone keeps the civil
  time across clock changes. Each occurrence can be moved or cancelled on its
  own. See [the recurrence record](2026-09-08-recurring-bookings.md).
- **Receipts and mileage:** expenses accept private PDF/JPEG/PNG originals;
  mileage records retain the journey date, business purpose, vehicle and distance.
  Account export/deletion includes the new data and receipt originals.
  See [the expense and tax record](2026-09-08-expense-records-tax.md).
- **Tax estimate:** a versioned 2026/27 calculation uses reviewed annual inputs,
  optional eligible mileage, tax already paid and reserves. It shows estimated
  Income Tax, Class 4 NI and the reserve shortfall. Collected payments and logged
  expenses are references for review, not an automatic assertion of taxable
  profit. Rules and source links are visible with the calculation.

## Files and architecture

| Files | Purpose |
| --- | --- |
| `lib/features/finance/documents/` | Typed document amounts, editor/list/detail screens and locally rendered PDF. |
| `lib/shared/repositories/business_documents_repository.dart`, `lib/shared/providers/business_documents_provider.dart` | Workspace-scoped document reads and transactional commands. |
| `lib/features/finance/finance_screen.dart`, `add_payment_screen.dart`, `widgets/payment_cards.dart` | Money entry points, protected invoice editing and receipt-specific history display. |
| `lib/shared/models/slate_models.dart`, payment repository, finance/feed providers, `money_profit.dart`, `money_timeline.dart` | Preserve cash movement amounts/dates across the connected experience. |
| Appointment screens, repository and `appointment_recurrence.dart` | Finite timezone-aware repeat workflow using existing booking infrastructure. |
| `tax_estimate.dart`, `tax_estimate_screen.dart`, `mileage_screen.dart`, `expense_records_repository.dart`, `expense_receipt_section.dart` | Separate calculation rules, supporting records and mobile forms. |
| Expense editor/repository, privacy repository and `complete-account-deletion` shared helper | Receipt attachment, safe removal, export and account lifecycle. |
| Three `20260908` migrations, schema/RLS contracts and matching SQL tests | Additive tenant-isolated storage and transaction boundaries. |
| Document, recurrence, tax/expense and database regression tests | Arithmetic, navigation, retries, date boundaries and workspace isolation. |
| `pubspec.yaml`, lockfile and two Manrope document font assets | PDF rendering dependency and embedded licensed font instances for portable exports. |

## Data decisions

`business_documents` stores drafts and quotes separately because existing app
versions treat rows in `invoices` as payments owed. Issuing materialises a linked
invoice once; immutable issued snapshots remain distinct from its changing
payment balance. Integer minor units drive Dart calculations; the server
validates and recomputes decimal line totals. Optimistic revisions reject stale
edits, exact retries are idempotent, and invoice collection follows existing
Stripe reservation guards.

Recurring creation wraps `create_booking_workflow` with bounded occurrence data;
it reuses existing conflict checks, task/payment creation, tenant guards and
notifications. It does not add a background scheduling service.

Expense receipt metadata binds private object paths to a workspace and expense.
Mileage and reviewed tax inputs are stored with workspace RLS. Tax results are
computed, not stored as an authoritative liability. Sensitive forms and pending
actions are pinned to their opening workspace and do not carry data into another
account after an identity change.

## Scope and practical limits

- Tax supports one qualifying cash-basis sole trade with a 5 April year end in
  England, Wales or Northern Ireland for 2026/27. The eligibility confirmation
  excludes VAT registration and other income, reliefs and circumstances outside
  this model. Scotland, limited-company tax and HMRC filing are unsupported.
  Payments on account are indicative and separate from the year's liability.
- Invoice VAT uses a single supported rate per document. Customer quote decisions
  are recorded manually. Paid invoice correction/credit-note creation and
  automatic quote-to-booking scheduling are not included.
- Repeat series are finite; edits affect one occurrence. Inline tasks apply to
  the first booking, as stated in the form. There is no edit-all-series action.
- Receipt attachment retains originals, without OCR or automatic categorisation.
  Each file is limited to 10 MiB. Export protects mobile memory with a 20 MiB
  aggregate limit and fails explicitly rather than silently omitting originals.

## Rule sources

Rules were checked on 8 September 2026 against
[HMRC Income Tax rates](https://www.gov.uk/income-tax-rates),
[self-employed National Insurance](https://www.gov.uk/self-employed-national-insurance-rates),
[simplified vehicle expenses](https://www.gov.uk/simpler-income-tax-simplified-expenses/vehicles)
and [payments on account](https://www.gov.uk/understand-self-assessment-bill/payments-on-account).
The shared higher mileage band follows
[ITTOIA 2005 section 94F](https://www.legislation.gov.uk/ukpga/2005/5/section/94F).

## Verification and delivery

- Final `flutter analyze`: no issues.
- Full Flutter verification: **1,065 passed, six capability skips**, on frozen
  final source using `flutter test --dart-define-from-file=.env --concurrency=4`.
  Evidence: `/tmp/workloop-business-tools-tests-verified.log`.
- Payment-enabled checks: **7 passed** with
  `--dart-define=PAYMENT_COLLECTION_ENABLED=true`; these exercise the six cases
  skipped by the default configuration plus the existing error-copy test.
- `flutter build ios --profile --dart-define-from-file=.env`: passed, signed
  `build/ios/iphoneos/Runner.app`, 79.0 MB. Existing Swift Package Manager notices
  for `device_calendar` and `flutter_local_notifications` did not block it.
- Full isolated SQL replay: 97 migrations, 30 suites, **928 assertions passed**.
  New document suite: 66; recurrence: 27; expense/tax: 30. Evidence:
  `/private/tmp/workloop-db-validation/final-business-features-results.json`.
  The harness uses PGlite PostgreSQL 18.3 with explicit Auth, cron, Vault and
  Storage metadata substitutes. It does not prove hosted API behavior, actual
  object bytes or concurrent multi-session locking.
- Invoice editor/list/detail checked at 320 px and 1.8× text, including actual
  saves, offscreen validation, stale-write recovery and workspace changes.
  All three pages of the generated 40-line sample PDF were rendered and reviewed.
- Receipt cleanup: two Deno tests passed; `complete-account-deletion` typecheck
  passed. Full-app analysis includes the receipt/mileage/tax UI and rules.
- `git diff --check`: clean. Existing dirty work remains intact and uncommitted.

This is a **local source and compiled-build delivery**. No production migrations,
Edge Function deployment, TestFlight upload or device installation were performed.
The known iPhone was unavailable when checked. Current installed/beta builds do
not gain these features from the local compile.

The release sequence is the three additive migrations, then the updated
`complete-account-deletion` bundle including `receipt_storage_cleanup.ts`, then
authenticated hosted Storage upload/download/remove and real-device workflow
checks before distributing a new mobile build. Use the individual tested
migrations: existing hosted/local migration-history drift makes an indiscriminate
database push inappropriate. Preserve the deployed endpoint's JWT verification.

Physical checks should exercise invoice PDF sharing, attachment selection/removal,
partial-payment refresh, and a repeating booking across a clock change. These
are verification gaps, not claims that the provider/device workflows passed.

Suggested commit: `feat: connect invoicing, recurring bookings, receipts and tax estimates`.
