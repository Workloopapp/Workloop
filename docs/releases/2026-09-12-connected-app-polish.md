# Connected app polish and attachments — 12 September 2026

The app review focused on the operating loop: client context, bookings and work,
notes, quote acceptance, invoice collection, and returning to the right record.
Changes extend the current Quiet + Warm components and repositories. Existing
uncommitted work was preserved; this is not a clean release-commit provenance
claim. A separate active task was also changing/building reports in this checkout.

## Changes

| Area and files | Behavior and reason |
| --- | --- |
| `lib/shared/attachments/record_attachment.dart`, `record_attachment_picker.dart`, `record_attachments_repository.dart`, `record_attachments_provider.dart`, `record_attachments_screen.dart` | One private attachment flow for saved bookings, notes and clients. Camera, selected photos, Files, in-app viewing, remove confirmation, visible load failures and stable-ID upload retry. JPEG, PNG, WebP, PDF and UTF-8 text, up to 10 MiB each. Types are checked from content; arbitrary HTML/Office rendering is not added. |
| `lib/features/appointments/appointment_detail_screen.dart`, `appointment_detail_sections.dart` | Photos & files sits beside booking notes. Linked task rows have the required Material surface, fixing a rendering assertion when navigating from a task. |
| `lib/features/notes/notes_screen.dart`, `lib/shared/repositories/notes_repository.dart` | Files is available in the note toolbar. The editor saves one stable note identity before opening its attachments, supports an image-only Photo note, updates that same note afterwards, and preserves text on save failure. Unchanged notes no longer cause unnecessary writes; saving blocks accidental dismissal. Note deletion cleans files first and reports partial cleanup honestly. |
| `lib/shared/documents/workloop_document_viewer.dart`, `ios/Runner/Info.plist` | Shared viewer accepts WebP and labels general images by filename; receipt labels remain specific. Camera/photo permission descriptions cover the added uses. Existing private in-memory PDF/image/text viewing and sharing are reused. |
| `lib/features/clients/client_record_link_screen.dart`, `client_detail_screen.dart`, `widgets/client_overview_tab.dart` | Direct-link Back/discard/delete returns to Clients; pushed screens return to their caller. Workspace changes hide prior records, while same-workspace refresh preserves an open edit. Added client files beside notes. Received/owed summaries use the same canonical payment calculations as Money, including legacy paid and cancelled records. |
| `lib/features/tasks/tasks_screen.dart`, `task_detail_widgets.dart` | Client and booking context opens the exact record. Task detail follows the current provider row after returning, including changed client names. Workspace switches and failed refreshes hide stale mutation actions and provide recovery. |
| `lib/features/finance/documents/business_document.dart`, `business_document_detail_screen.dart`, `business_document_body.dart`, `business_document_pdf.dart` | Issue/accept/collect actions precede work details. Header and refresh remain reachable. Exact client, booking and source-quote links preserve context. Failed/loading payment balances cannot expose collection controls and have a direct retry. Corrected overdue deposits, draft/quote date wording and non-VAT PDF labels. Workspace checks hide stale document content during scope changes. |
| `lib/shared/repositories/clients_repository.dart`, `privacy_repository.dart`, `supabase/functions/complete-account-deletion/index.ts` | Client deletion cleans its own attachments while related booking/note files remain with those records. Export v4 includes attachment metadata and bytes. Account deletion cleans the new private bucket before removing its pointers. |
| `supabase/schema_contract.sql`, `supabase/rls_policies.sql` | Append the attachment ownership, private storage and cleanup contracts, keeping the documented security boundary aligned with the migrations. |
| Focused attachment, connected-navigation, business-document tests; viewer/destructive/task trust fixtures; two client context goldens | Cover new behavior, scope changes, lost responses, direct return paths, retry states, accessible sizes and intentional hierarchy changes. |

## Database changes

- `20260912113740_private_record_attachments.sql`: adds the metadata table and a
  private 10 MiB bucket. Composite keys prevent cross-business target links.
  RLS requires membership and MFA. Files are immutable; a retry verifies bytes
  by hash. Metadata cannot be removed while its Storage object exists, so failed
  deletion retains a cleanup pointer. Account deletion blocks new uploads.
- `20260912113751_quote_invoice_deposit_dates.sql`: only new quote conversions
  clamp a proposed deposit date into the new invoice's issue/final-due interval.
  Source quotes and existing conversion retries retain their recorded values.
- `20260912113752_receipt_storage_completion_role.sql`: repairs the reproduced
  native Storage role's inability to execute the existing receipt lookup.
  The private trigger checks caller role; authenticated writes additionally
  require UID, membership and MFA. Direct function execution stays revoked.
  This avoids granting Storage broad access to business tables.

The new trigger uses a narrowly scoped private SECURITY DEFINER function because
the native Storage completion role does not have application-table privileges.
The existing receipt defect was reproduced with that role before the repair.
Ordinary client/note deletion remains compatible with a backend that has not
yet gained the attachment table; only the exact missing-table error is ignored
by cleanup. Upload/list failures and permission errors stay visible.

## Verification

Final integrated verification passed:

- `flutter analyze`: no issues.
- `flutter test --dart-define-from-file=.env`: 1,326 passed, one configuration
  skip. The skipped disabled-card-collection UI case does not apply while
  payment collection is enabled. All 60 focused workflow checks also passed.
- `flutter build ios --profile --dart-define-from-file=.env`: signed
  1.0.0 (19), 80.5 MB; strict code-signature verification passed.
- `git diff --check`: passed. Light/Dark client context snapshots were reviewed
  and updated for the intentional files row and corrected payment summary.
- The signed app installed and launched successfully on the paired iPhone
  15 Pro Max. No TestFlight upload or version bump was performed.

Tests/builds ran after loading `scripts/dev_env.sh`, in
`/private/tmp/workloop-polish-verify-20260912`, an isolated copy of the actual
checkout, because concurrent Flutter commands in the shared build directory
caused asset-generation races. All 826 snapshotted source/asset/test/backend
inputs matched the real checkout at verification. The source manifest, logs,
backend verification, install/launch receipts and signed `Runner.app` are in
`build/connected-app-polish-20260912/`. The earlier failing integrated run is
retained there: fixture/layout assumptions and the two intentional snapshots
were corrected before the final full suite passed.

The isolated PostgreSQL checks passed 39 attachment/lifecycle/receipt-role
assertions plus 10 quote-conversion assertions. These execute migration/function
bodies with focused surrounding fixtures; they are not a full Supabase replay
or a live Storage HTTP upload. Two cleanup Edge tests and the account-deletion
Edge type check passed. Non-VAT and registered-zero-VAT PDFs were rendered and
visually inspected. Client Light/Dark diffs were inspected before updating the
two changed context snapshots.

## Rollout and remaining evidence

All three migrations above are deployed to `imtbyrvsonzvtddswbtb`.
`complete-account-deletion` version 35 is ACTIVE, with its existing
`verify_jwt=true` preserved. All seven deployed source/import-map files match
the reviewed local inputs. Live SQL function hashes match the intended bodies;
the attachment table has RLS, no anonymous read or authenticated update grant,
and the bucket is private with the expected size/type limits. Security Advisor
findings are unchanged from the pre-deployment baseline: no new findings, with
six existing function-exposure warnings and 26 private-table policy notices.

The CLI stopped at a native Keychain lookup before any deployment. The already
authenticated Supabase connector applied the three reviewed migrations
individually and deployed the worker. The three new local migration filenames
now match the server-issued versions; older history was not rewritten. The
earlier `build/audit-fixes-20260912/attachment-release/` package is retained as
pre-deployment evidence and marked superseded; do not deploy it again.

The live application database currently has no connected Stripe payment-account
rows. Card collection needs account setup/onboarding before a real payment
journey can be verified; a successful app build does not establish payment
provider readiness.

The successful device launch does not substitute for camera shutter/HEIC
conversion on a physical device, native photo selection,
sharing to a chosen recipient, real customer email delivery and live card
collection/refunds. Those still require their own device/provider journeys,
including an authenticated live Storage upload. No customer
message or charge was sent as a test. Quote decisions remain owner-recorded;
PDF delivery uses native sharing, while the existing card collection flow offers
payment-request emails. Customer acceptance portals, formal credit notes and
mixed-rate VAT invoices are outside the implemented scope. The app does not
claim those workflows are complete.

A final iPhone Mirroring inspection was attempted after the successful native
installation/launch. Computer Use reported that the Mac was locked and could
not be unlocked automatically. Visual/native interaction checks therefore
remain blocked until the owner unlocks the Mac; the installation and process
launch receipts are successful independently of that UI-access limitation.

Invoice content was checked against [GOV.UK invoice requirements](https://www.gov.uk/invoicing-and-taking-payment-from-customers/invoices-what-they-must-include)
and [GOV.UK VAT guidance](https://www.gov.uk/charge-reclaim-record-vat).
Private storage follows the [Supabase access-control contract](https://supabase.com/docs/guides/storage/security/access-control).

Suggested commit after consolidating the existing dirty checkout:
`feat: connect private attachments and polish document and record workflows`
