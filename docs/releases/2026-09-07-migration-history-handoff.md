# Workloop migration metadata drift — 7 September 2026

Read-only live MCP `list_migrations` for `imtbyrvsonzvtddswbtb`, compared with current filenames, followed by server-side checksum queries for the newest two stored migrations. Only hashes, byte counts and wrapper classification were returned; no migration bodies or secrets were printed. No schema change, version repair, file rename, test, build or deployment was performed. Only this temporary handoff folder was written.

## Current comparison

- Hosted history: **98 entries**.
- Flutter app checkout: **94 entries**; **88 exact name/version matches**, **6 same-name/different-version pairs**, **0 local-only names**, **0 same-version/different-name collisions**.
- Four hosted entries absent from the app folder belong to the separate Workloop OS. All four sources were located there; three have their own timestamp drift.
- `add_notes` appears twice at `20260607133335` and `20260705140451` identically in both histories. Preserve both; matching or deduplicating by name alone is unsafe.

## App timestamp mapping

| Migration | App-local version | Hosted version |
| --- | --- | --- |
| public_booking_target_date_availability | 20260902183040 | 20260902183936 |
| booking_email_reminders_and_user_journeys | 20260905145541 | 20260905150833 |
| restrict_email_worker_auth_access | 20260905151826 | 20260905151931 |
| normalize_booking_reminder_reply_address | 20260905152125 | 20260905152140 |
| stripe_payment_received_notifications | 20260906165210 | 20260906232054 |
| workloop_subscription_access | 20260906223935 | 20260906231421 |

## Intentional OS-only history

These files live under `/Users/ismaeelsmiley/Documents/Workloop-OS-Launch/supabase/migrations/`, not the Flutter app folder. Source paths and file hashes are included in `mapping.json`.

| OS migration | OS-local version | Hosted version |
| --- | --- | --- |
| workloop_os_business_pulse | 20260902212407 | 20260902212657 |
| workloop_os_codex_runner | 20260902213947 | 20260902214821 |
| workloop_os_codex_apply_gate | 20260902232000 | 20260902221652 |
| include_provider_delivery_in_os_pulse | 20260904200250 | 20260904200250 |

## Safest maintenance proposal — deferred, no changes tonight

1. **Do not run a normal `db push` from the current app-only migration folder or use `--include-all` to force it.** Version matching cannot infer that the six differently numbered files are already applied. The history also contains the four legitimate OS entries. This can stop a push or tempt an unsafe duplicate replay.
2. Preserve the hosted history as the authority for applied version IDs. A metadata match establishes the correspondence, **not byte-equivalent SQL**. Before accepting renames, compare the actual applied statements/effective schema with each local file using a controlled redacted review or server-side hashes. Do not dump secret-bearing historical SQL to logs.
3. Keep the **app and OS repositories separate** and the uploaded mobile candidate frozen. In a separately authorised maintenance pass, prepare a disposable release-verification directory/manifest that accounts for the complete hosted history from both owners. After content equivalence is established, stage each source under its authoritative hosted version there; do not rewrite correct hosted history or restructure either project merely to satisfy the CLI. Any later source-filename alignment needs its own reviewed change.
4. Replay that combined set in isolation and rerun SQL tests before adopting it. The newest two files change relative order when aligned: hosted subscription `20260906231421` precedes Stripe alerts `20260906232054`, whereas the current app filenames place Stripe first. The prior 94-migration/805-assertion pass used the current app-local order and omitted the separate OS migrations; it does not prove the combined hosted-order replay.
5. From the reviewed combined set, use `supabase migration list` and `supabase db push --dry-run` to verify **zero historical migrations would be reapplied**. Do not run a real push as a verification step. Discover the installed CLI flags with `--help` first.
6. For future deployments, use one version-preserving deployment path for the canonical project history, or capture and reconcile the actual MCP-generated version immediately after a named migration is applied. Keep release receipts explicit about source version versus hosted version.

`migration repair --status reverted` deletes a history record; it does not undo SQL. `--status applied` inserts a history record; it does not prove the SQL was applied. Neither is justified merely to silence these six mismatches or remove the intentionally separate OS entries. Keep schema/history repair as a separately reviewed maintenance action if content comparison finds a genuine discrepancy.

Official references: [db push and dry-run](https://supabase.com/docs/reference/cli/supabase-db-push), [migration repair semantics](https://supabase.com/docs/reference/cli/supabase-migration-repair), [migration workflow](https://supabase.com/docs/guides/deployment/database-migrations).

## Evidence limits

The name/version audit establishes metadata drift and known source ownership. The two newest migrations additionally have the checksum evidence below; the other seven mismatched source files have not had deployed-content equivalence checked. This does not assert every historical body matches or that the current schema has no out-of-band changes. The JSON includes local SHA-256 values for all nine mismatched source files. No private migration body, key, token, customer record or account data is included.


## Newest two deployed-content checks — same read-only pass

The server calculated SHA-256 over each stored migration statement; only hashes and byte counts were returned. `newest-two-hash-verification.json` records the results.

- **Subscription:** hosted `20260906231421` contains one 14,890-byte statement. SHA-256 `71c5ceefaec16ad2f765799ecf7562de294ff559c1ae2d06130196d545c0f9eb` exactly matches local `20260906223935_workloop_subscription_access.sql`. The SQL is byte-identical despite its different history version.
- **Stripe alerts:** hosted `20260906232054` contains one 8,822-byte statement, raw SHA-256 `b3dd619ce451914329ee351c519c8cfcb8f1daa8f2b43bdb523d75ec96769f5d`. Removing only the leading `SET lock_timeout` wrapper and its immediately following whitespace removes 31 bytes. The remaining 8,791-byte SQL has SHA-256 `315a135e06d4393571a92a3547970d15f9892696bff595279ee50d32b8d0af40`, exactly matching local `20260906165210_stripe_payment_received_notifications.sql`. No DDL difference remains after that deployment-only wrapper.

No history repair is needed to make these two SQL changes take effect: they are already applied. Their current local timestamp aliases must not be pushed again. This evidence authorises no file rename or database history mutation tonight.
