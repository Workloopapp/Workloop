# Backend release check — 9 September 2026

Read-only production checks at approximately 07:27 BST supported the build 19
release. No database schema, Edge Function, customer record or account was changed
as part of these checks. The previously approved account-deletion fix was already
deployed.

- Supabase project `imtbyrvsonzvtddswbtb` was ACTIVE_HEALTHY in London on
  PostgreSQL 17.
- All seven 8 September feature migrations matched the local stored SQL hashes.
- Account deletion function v33 was active with JWT verification; all seven
  deployed source/dependency files matched the local release implementation.
- Stripe payments function v27 matched all five dependencies; the entrypoint had
  formatting-only differences. No function redeployment was needed.
- Receipt storage was private with a 10 MiB PDF/JPEG/PNG limit, workspace/MFA
  policies, deletion guard and completion trigger.
- Ten workflow RPCs were authenticated-only security-invoker operations; direct
  document/receipt ledger writes were blocked and private counters had no client
  access.
- No pending account deletions or errored/overdue account email queue entries were
  found.
- The last two hours contained 120 successful cron runs and 128 HTTP 200 results;
  available response bodies had no reported errors or positive failed/uncertain
  counters.
- Advisors returned zero errors, six existing security-definer warnings and 26
  informational private-table notices. These remain existing findings, not an
  all-clear security certification.

Auth HTTP logs were unavailable through the connector. No live-money transaction,
receipt upload, two-account isolation exercise or comprehensive Auth-log sweep was
performed. Existing automated/backend evidence and this operational check are
separate from manual device QA, provider payment readiness and public launch.
