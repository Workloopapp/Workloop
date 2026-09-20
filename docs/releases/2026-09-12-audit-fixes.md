# Audit repair pass — 12 September 2026

Repairs for A01–A12 in `2026-09-12-app-audit.md`, plus the task editor controller
lifetime finding. Existing uncommitted work was preserved in the real Workloop
checkout. No commit, push or TestFlight upload is part of this pass.

## Changes and file map

| Finding | Result | Main files |
| --- | --- | --- |
| A01 | Payment links use the issued document's saved recipient, skip absent contacts, and finish database/configuration preflight before reservation. Reuse checks current transaction status, invoice, method and amount. Uncertain Stripe operations retain their guard. | `supabase/functions/stripe-payments/index.ts`, `receipt_email.ts`, `payment_link_test.ts` |
| A02 | PDF descriptions/terms continue across bounded rows/pages. A worker isolate keeps layout off the UI thread; release-mode page limits and a 15-second killable timeout prevent runaway layout. The viewer shows actionable failure guidance. | `lib/features/finance/documents/business_document_pdf.dart`, `lib/shared/documents/workloop_document_viewer.dart`, `document_open_exception.dart` |
| A03 | Income history uses each timeline movement's stable key, so deposits, balances and refunds can coexist. | `lib/features/finance/finance_screen.dart` |
| A04 | Cancellation writes existing reason/timestamp metadata and preserves work notes. | `lib/features/appointments/appointment_detail_screen.dart` |
| A05 | Booking fields and item snapshots save atomically and return fresh display data. Ordinary bundle edits preserve item identities; changing the service/name replaces its work snapshot. Price changes retain other services/extras, rejecting totals below them. Issued documents are unchanged. | Appointment detail screen, `lib/shared/repositories/appointments_repository.dart`, `20260912103516_atomic_booking_edits.sql` |
| A06 and controller risk | Task edits preserve appointment_id. The outgoing route owns its text controllers until unmounting. | `lib/features/tasks/tasks_screen.dart` |
| A07 | New income and receipt-free expense forms keep one UUID across retries. Upserts update that same record if the owner corrects the still-open draft. | `lib/features/finance/add_payment_screen.dart`, `expense_editor_screen.dart`, `lib/shared/repositories/payments_repository.dart`, `expenses_repository.dart` |
| A08 | Only exact missing-expense-schema errors use the compatibility fallback. Permission, query and service failures propagate to existing retry states. | Expenses repository |
| A09 | Shared validation rejects malformed, reversed, equal and overlapping enabled hours across onboarding, Settings, Profile and repositories. The completion transaction validates before any writes. Closed-day drafts are retained. | `lib/shared/utils/working_hours.dart`, onboarding hours/repository, Profile hours editor, Settings business/helpers, workspace settings repository, `20260912103515_validate_onboarding_working_hours.sql` |
| A10 | Services share the document money parser; invalid prices stay visible with a field error. Explicit zero remains valid. | `lib/features/settings/widgets/settings_business_tab.dart`, `lib/features/onboarding/screens/onboarding_service_editor.dart` |
| A11 | Received-date picker/save guard prevents future calendar dates. Current cash, monthly progress, profit graph and tax reference exclude existing future-day receipts. History retains original dates so records can be corrected. Month selection and the as-of clock are separate. | Add payment screen, `lib/shared/providers/finance_provider.dart`, `lib/features/finance/money_profit.dart`, `tax_recorded_figures.dart` |
| A12 | Calendar snapshots retain UID and export cancelled status, transparent availability and last-modified metadata. | `lib/shared/utils/calendar_export.dart`, `test/calendar_export_test.dart` |

Calendar state follows [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545#section-3.8.1.11).
The regression compares active/cancelled snapshots of the same UID; importing a
second file into a third-party calendar is still subject to that client's import
behavior. This is a snapshot export, not a synchronization protocol.

Regression coverage was added in the audit finance/income/receipt/hours tests,
booking edit tests, PDF/viewer tests, task failure-safety tests and calendar tests.
Existing fixtures now use valid hours and explicit clocks. The booking-request
conversion fixture chooses a date within the actual picker's allowed range.
Deno CI/local runners load each function's pinned import map and required test
templates rather than skipping scoped tests or failing dependency resolution.

## Backend deployment

Applied and confirmed in the live ledger:

- `20260909082604_persist_onboarding_service_descriptions` — existing local prerequisite.
- `20260912103515_validate_onboarding_working_hours`.
- `20260912103516_atomic_booking_edits`.

Stripe payments version **28** is ACTIVE. All seven deployed source/configuration
files were retrieved and exactly matched the local deployment inputs. Its existing
custom authentication/JWT configuration was retained. A synthetic request without
credentials returned HTTP 401 Unauthorized before any provider action.

New booking RPC privileges were checked: public wrapper is SECURITY INVOKER,
anonymous execution is denied, and the private implementation checks authentication,
workspace membership and MFA. Onboarding retains its existing invoker security and
wrapper boundary. Security advisor findings were unchanged after deployment.

Historical local/remote version mismatches were accounted for in an ignored,
temporary deployment manifest. The dry run listed exactly the three migrations
above; existing live migration history was not rewritten. No customer records,
provider settings, secrets or payment balances were manually altered.

## Verification

Final Flutter analysis is clean. The full suite passed **1,252 tests**, with ten
existing skips (2 minutes 12 seconds). The complete suite includes protected
goldens; no golden baselines were updated. The signed iOS profile build passed
(Xcode 48.3 seconds, 80.0 MB). Installation on the paired iPhone 15 Pro Max
succeeded and device metadata confirms **1.0.0 (19)**. After the phone was
unlocked, CoreDevice confirmed successful launch. This is the
new local profile build, not a new TestFlight upload. Detailed logs are in
`build/audit-fixes-20260912/`.

Completed focused evidence:

- 192 Edge tests: 149 shared, seven real payment-handler regressions, 36 subscription checks.
- 15 PDF/viewer Flutter tests; normal and multiline PDFs visually inspected.
- Assertions-disabled multiline PDF: 217 ms; impossible layout rejected in 13 ms.
- Extracted PDF retains 100 description lines, 150 terms lines and 100 bank-detail lines.
- 28 executable isolated PostgreSQL assertions: 12 booking and 16 onboarding.
- Additional pgTAP regressions added; a full hosted/staging pgTAP replay was not run.
- Payment-link live deployment source equality and database privileges verified.

## Risks and follow-up

A read-only production count found zero reservations without a matching payment
transaction after deployment, so no stranded-record cleanup was needed. Any future
ambiguous Stripe operation must be reconciled before its guard is removed; deleting
it without provider evidence could permit duplicate collection. No live charge or
refund was attempted as a test.

A successful phone launch establishes installation and process startup. Camera,
sharing, screen-reader, third-party calendar reimport, real collection/refund and
external email delivery remain separate end-to-end QA journeys.

The working tree still contains substantial earlier changes. This phone build uses
the current checkout; it is not evidence of a clean release commit or uploaded beta.
No TestFlight upload was performed.

Suggested commit once the owner consolidates the working tree:
`fix: repair audited booking, money, document and validation workflows`

Recommend linking this release note from CURRENT_STATUS/ENGINEERING_LOG when the
combined release is consolidated; no historic audit report was rewritten.
