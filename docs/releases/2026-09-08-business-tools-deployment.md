# Business tools backend deployment — 8 September 2026

The user authorised the reviewed backend release and installation on their own
device. This receipt covers Supabase project `imtbyrvsonzvtddswbtb`; mobile build,
owner-only distribution and device verification are recorded separately. No
tester-group distribution was performed by this deployment.

## Applied migrations

The three reviewed migrations were applied individually in order, without a
general database push or repair of historical migration drift. Hosted history
increased from 98 to 101 entries. Each hosted migration stores one statement
whose SHA-256 exactly matches the locally tested SQL body.

| CLI-created version | Hosted/local reconciled version | Name | SQL SHA-256 |
|---|---|---|---|
| `20260908180041` | `20260908190556` | `recurring_booking_series` | `ba9a9a616607fc00f10cbf0fd581dd0dc596f259fe849f981bc4125dcd7de37e` |
| `20260908180121` | `20260908190606` | `connected_quotes_and_invoices` | `6a8a2623bc2dc8532efdc1e5a4caa0fa106940a836e93c4d507226c0c2dc36e7` |
| `20260908180227` | `20260908190613` | `expense_receipts_mileage_tax_estimates` | `4fb4abafa93e62834f5fea7a3235c7fd4fd8e6966dd294db418a71938e8eaa4b` |

Only these three new local filenames were renamed after hash verification. Their
contents and older local/hosted migration history were preserved. The unchanged
bodies passed the isolated replay of 97 local migrations, 30 suites and 928 SQL
assertions before deployment.

## Account deletion endpoint

`complete-account-deletion` moved from active version 30 to active version 31 at
19:06 UTC. JWT verification remains enabled. All five pre-existing dependency
files were preserved byte-for-byte. The entrypoint adds the receipt cleanup
import/call, and the new `receipt_storage_cleanup.ts` helper is included.
Downloading version 31 confirmed exact equality for all seven deployment files.

The downloaded bundle hash is
`5d8ea0ee5306f3a47fbe879beed4275c83a292eb8417235b425ef700ac0b1735`.
An unsigned empty POST returned HTTP 401 after deployment; it contained no user
credentials or account-deletion request.

Exact version-30 files, function metadata, pre/post advisor snapshots, migration
hashes, ACL checks, query plans and version-31 bundle evidence are saved under
`/private/tmp/workloop-business-tools-release-20260908/`, with access restricted
to the local user. `before-function-sha256.json` and
`deployed-function-sha256.json` record per-file hashes.

## Hosted verification

- All five new public tables and two private document tables have RLS enabled.
  Anonymous reads are denied. Document content and receipt timing rows are
  member-readable but have no direct member writes. Private document counters
  and payment retry records have no ordinary client table privileges.
- The eight public workflow entrypoints use SECURITY INVOKER, an explicit empty
  search path, authenticated EXECUTE and no anonymous EXECUTE. Trigger helpers
  are not directly executable by ordinary client roles.
- A transaction-rolled-back probe confirmed that the authenticated role without
  a user subject sees no new-table records, and that document and recurring
  booking workflows reject it before writing.
- The receipt bucket is private, limited to 10 MiB per object, and allows only
  PDF, JPEG and PNG. Actual authenticated Storage byte operations are tracked
  in the separate hosted Storage smoke receipt.

No real customer records were updated and no notifications, email or messages
were sent by these deployment checks.

## Advisor comparison

Security reports zero errors and the same six existing SECURITY DEFINER warnings.
The informational private-table RLS notices increased from 24 to 26 because the
two new private document tables intentionally have no client policies or grants.
See [Supabase's RLS notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
and [SECURITY DEFINER guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

The [composite foreign-key index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
increased from three to six informational findings. The new findings concern
`business_documents(workspace_id, source_quote_id)`,
`business_documents(workspace_id, invoice_id)` and
`expense_receipts(workspace_id, expense_id)`. Existing unique indexes on the two
document relationship IDs bound each lookup to at most one row; the expense-ID
index restricts lookup to one expense's receipts. Hosted EXPLAIN verified index
scans for both document relationship IDs and a bitmap index scan for expense ID.
The composite probes on currently empty tables chose available workspace indexes.
No additional index migration was added solely to clear these informational
findings. Unused-index notices are retained for these new and existing indexes.

The hosted checks establish deployed schema, access controls and bundle identity.
The isolated SQL replay remains distinct from real concurrent-session, provider,
authenticated Storage and physical-device verification.

## Private review release: deposits and workflow corrections

On 2026-09-08 at approximately 20:00 UTC, the owner-authorized follow-up applied
only the four reviewed migrations below to `imtbyrvsonzvtddswbtb`. The hosted
history increased from 101 to 105 entries. All prior entries were preserved;
normal `db push` and historical migration repair were not used.

| Original local version | Verified hosted/local version | Migration | Stored-body SHA-256 |
| --- | --- | --- | --- |
| 20260908193503 | 20260908200018 | reviewed_annual_mileage_estimate | `d54df2c62adbc7f8469f01b36db552e89b90e6e65d65fafe9526afb02493b446` |
| 20260908193610 | 20260908200023 | business_document_defaults | `113931e60124478f3dc8bce13900b710b901b9c3c04b585cc910a374b54f20b7` |
| 20260908193611 | 20260908200032 | invoice_deposits_and_manual_refunds | `17c34364ec579bddd398e9a1a1d8bac617706473a9eac6e71b62e3dd98cfc782` |
| 20260908194402 | 20260908200053 | recurring_booking_retry_recovery | `205b1b13c1afe7d10b245832307bde53437baf9f539d4f842381e37e2e3ecae0` |

Each stored migration body was hashed in PostgreSQL and compared with its exact
tested local SQL before renaming only these four new files. Before/after
function definitions, ACLs, schema checks, advisor output, and the readback
receipt are retained under the access-restricted temporary directory
`/private/tmp/workloop-private-review-release-20260908/`.

The changes introduce canonical invoice defaults, a reviewed annual mileage
forecast, fixed/percentage deposit requests on the same existing invoice
balance, actual dated manual receipts/refunds, and safe recurring-series retry
recovery. A VAT-inclusive £60 booking remains £60: at 20%, net is £50 and VAT
is £10. A 50% deposit requests £30 without recording income. Actual receipts
reduce the remaining invoice balance once; manual refunds create negative
receipt deltas and cannot impersonate Stripe refunds. An eligible uncollected
booking PAY can become the issued invoice without adding a second debt.

### Verification of the reviewed release

- Replayed the final hosted-named local files in isolated PostgreSQL 18.3
  (PGlite 0.5.8): **101 local migrations, 33 suites, 1,009 assertions passed**.
  The local/hosted history counts differ because historical hosted-only and
  version drift was intentionally preserved. This runtime substitutes Auth,
  Storage metadata, cron and Vault; it does not prove concurrent sessions or
  real provider delivery.
- Exact command:
  `/Users/ismaeelsmiley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /private/tmp/workloop-db-validation/documents-replay.mjs --output /private/tmp/workloop-review-deployed-full-sql.json`
  with stdout/stderr in `/private/tmp/workloop-review-deployed-full-sql.log`.
- The invoice suite covers gross/net VAT, the 3p half-penny case, reduced rates,
  immutable issued amounts, quote conversion, matching existing-PAY adoption,
  deposit limits, dated receipt/refund idempotency across time-zone changes,
  tenant/MFA boundaries and workspace cascades.
- Fourteen hosted schema/ACL checks passed: new public RPCs are invokers and
  authenticated-only, clients cannot write documents/receipts/private command
  context, existing RLS remains enabled, constraints are valid and the receipt
  trigger exists. No customer rows were updated by these checks.
- Advisor findings are identical before/after, comparing actual finding
  metadata rather than observation timestamps: zero security errors, six
  existing definer warnings, 26 private-table no-policy informational notices,
  six existing foreign-key index notices and 31 unused-index notices.
- Focused invoice checks passed: 30 Flutter tests, targeted analysis clean;
  existing Stripe contract tests passed 16. Seven additional live-state widget
  tests ran with payment collection enabled, covering fresh balances,
  changed-amount review, stable retries, email confirmation and account-switch
  isolation. Full-app and signed-device verification are recorded separately.
- A generated 40-line VAT-inclusive invoice was rendered and all four pages
  visually inspected. Net units, VAT rates, subtotal/tax/total, requested
  deposit, actual receipts, remaining deposit and total balance reconcile.

The card sheet now refreshes before a new collection. If the balance changes,
it shows the new amount and requires another explicit action. Once a request
starts, its amount and key stay fixed for a retry. Account changes hide payment
details and block retained callbacks; async completions recheck the workspace.

### Existing Stripe endpoint retained

Hosted `stripe-payments` **version 26 remains active**, with its existing
`verify_jwt=false` and in-handler authentication. Its current code already
supports partial amounts, tenant-scoped invoices, collection reservations and
saved-customer receipt addresses. No provider or beta configuration changed.

The exact six-file hosted bundle was backed up under `live-stripe-v26/` before
comparison. All five dependency/config files match local source apart from
final newlines. The entrypoint differs only in formatting: formatting temporary
copies of both with Deno 2.9.4 produces the same SHA-256
`d33a7a8e1773cf5e0fc06960523b410fbc51463c5372b20374b43d3984755255`.
Consequently no format-only redeploy was made. No charges, refunds, customer
emails or push messages were sent by this deployment work.

Invoice requirements and rounding were checked against
[GOV.UK invoice requirements](https://www.gov.uk/invoicing-and-taking-payment-from-customers/invoices-what-they-must-include),
[HMRC VAT Notice 700](https://www.gov.uk/guidance/vat-guide-notice-700), and
[HMRC invoice rounding guidance](https://www.gov.uk/hmrc-internal-manuals/vat-trader-records/vatrec12030).
The bounded fixed/percentage deposit workflow follows the established model
documented by [FreshBooks](https://support.freshbooks.com/hc/en-us/articles/223512188-How-do-I-request-a-deposit-on-an-invoice).

### Hosted authenticated review smoke and cleanup

After the four review migrations were deployed and their stored SQL hashes verified, the real hosted Auth and Data APIs passed 58 request/expectation checks using two disposable QA users and two isolated workspaces. The probe used ordinary authenticated member JWTs for business operations. Administrative access was limited to fixture creation and removal; service keys, passwords and JWTs were kept in mode-0600 temporary files and then removed.

Live Auth trigger definitions were inspected before creating users. Unconfirmed admin creation cannot enqueue a welcome email; confirmation and removal of the fixture welcome rows occurred in a single transaction. The users supplied no account-marketing metadata, the workspaces were unpublished with reminders/notifications disabled, and the QA contact had no email or phone. No provider payments or outbound messages were initiated.

- Canonical business structure, legal name, address, VAT details and payment/quote defaults round-tripped exactly. A different tenant saw no rows and could not overwrite them.
- Annual tax pence and 11,000 car/van plus 250 motorcycle forecast miles round-tripped as integer inputs, creating no actual mileage journeys. Unpaired, negative and over-limit forecasts were rejected without changing the saved values; another tenant could neither read nor overwrite them.
- A £60 VAT-inclusive quote at 20% retained £50 net plus £10 VAT and a £30 deposit request. Save retry, acceptance, conversion and invoice issuance preserved those figures. Requesting the deposit created no collected income.
- A £10 receipt dated the previous business day and a £2 refund dated the current day, each retried with its original key, left £8 collected and exactly two correctly dated receipt movements. Future received/refunded dates were rejected, as was a different tenant's refund attempt.
- A three-booking weekly series across the March 2027 UK clock change returned the same three IDs on retry. Another tenant could not replay that series.

Before cleanup, scoped welcome, learning, transactional, customer-event, SMS, push, booking-reminder and account-deletion delivery checks were all zero. No Storage objects or Stripe transaction records existed for these fixtures. Deleting only the two created workspaces, revoking their Auth sessions and deleting the two created users succeeded. A final 65-scope database check found zero remaining fixture rows across workspace/user-owned tables, Auth users/sessions and Storage prefixes. The cleanup probe initially named a nonexistent provider column in a read-only diagnostic; source inspection corrected that query before cleanup. No application operation failed.

Non-secret evidence: `/private/tmp/workloop-review-qa-results.json` (58 passed checks), `/private/tmp/workloop-review-qa-cleanup.json` (65 zero counts), and `/private/tmp/workloop-review-qa-fixtures.json` (created IDs only). These hosted results prove authenticated API behavior and cleanup; physical camera, photo-library conversion, file picking and native sharing remain separate device evidence.
