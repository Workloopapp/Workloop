# Exact notification record routes — 6 September 2026

## Scope and state

The backend change was reviewed and applied to the live Workloop project `imtbyrvsonzvtddswbtb` at **5 September 23:24:36 UTC / 6 September 00:24:36 BST**. No notification has been sent for this routing verification, and no notification preferences have been changed.

The problem was that four server producers saved list destinations and relied on a trigger to infer a record from rows changed in the same transaction. That trigger could select one arbitrary row from a batch. Several client notification inserts also happened after the record transaction had finished, so no row could be inferred at all.

Migration: `supabase/migrations/20260905232436_use_exact_notification_record_routes.sql`. The new local filename was reconciled to its deployed migration receipt; no existing migration history was rewritten. There are no new columns, tables, public APIs or provider settings. The existing four producer bodies come from the current live function definitions; only six destination expressions change. The private resolver and routing trigger provide a bounded compatibility path for older callers and stored notifications.

## Route contract

| Event | Destination |
| --- | --- |
| Public booking request received | `/booking-requests/<returned request ID>` |
| Booking request waiting | `/booking-requests/<that request ID>` |
| Booking created | `/bookings/<returned appointment ID>` |
| Recurring series created | First appointment ID in the workflow's returned series |
| Payment received or left outstanding on completion | `/payments/<returned invoice ID>` |
| Completion without an invoice, including a zero-value booking | `/bookings/<completed appointment ID>` |
| Payment overdue | `/payments/<that invoice ID>` |
| Task or note notification supplied by the app | `/tasks/<task ID>` or `/notes/<note ID>` |
| Morning brief summarising multiple records | `/home` |

`/payments/:id` identifies an invoice record, not a Stripe charge, payment intent or ledger item. Client detail lookup must still enforce current workspace membership and show an unavailable state if the destination has been removed. Existing exact destinations are preserved even when their records have subsequently been deleted.

## Bounded historical repair

Recovery uses a same-workspace request, invoice or task UUID in a recognised deduplication key, or an unambiguous result already saved by a booking workflow. The historical workflow deduplication key omits its user ID, so conflicting member results are treated as ambiguous. A missing competing record does not make a different surviving record a safe match.

The compatibility trigger only infers a transaction-local record on INSERT when exactly one record of the relevant kind exists in that workspace. It never guesses on UPDATE. Invalid or ambiguous structured identifiers cannot fall through to an unrelated transaction-local record. No customer names, notification wording or approximate timestamps are used as matching clues.

The migration's final update changes only `notifications.deep_link`. Read state, creation time, content, ownership and preferences stay unchanged. The push enqueue trigger is INSERT-only; repairing a stored route does not enqueue another delivery or replay old notifications. A delivery not yet claimed reads the repaired canonical route through the unchanged claim function. A payload already handed to a provider cannot be rewritten or recalled.

A read-only live dry run at **5 September 23:21:38 UTC** found:

| Type | Deterministically repairable rows |
| --- | ---: |
| New booking | 14 |
| Booking request | 13 |
| Payment overdue | 62 |
| Payment received | 7 |
| Total | 96 |

Of these, 40 were read and 56 unread. None had a pending/processing push delivery, and the entire pending/processing queue was empty. Remaining generic rows included 282 legitimate morning summaries and 87 other historical alerts whose saved identifiers were absent, missing or ambiguous. Those rows are deliberately not assigned a guessed record. Counts are a point-in-time dry run, not a deployment receipt.

## Live deployment receipt

Migration version **`20260905232436`**, name **`use_exact_notification_record_routes`**, applied successfully. Readback confirmed all six function bodies match the reviewed local SQL, including the four producers, resolver and trigger. Their security modes, restricted search paths and ACLs match the intended contract.

The snapshots at **23:24:27 UTC** before and **23:25:02 UTC** after showed:

| Invariant | Before | After |
| --- | ---: | ---: |
| Notification rows | 472 | 472 |
| Read notification rows | 93 | 93 |
| Exact record destinations | 7 | 103 |
| Push delivery rows | 10 | 10 |
| Pending/processing deliveries | 0 | 0 |
| Notification preference rows | 17 | 17 |

The aggregate checksums of every notification field **except `deep_link`**, every notification preference row and every push-outbox row were unchanged. The deep-link checksum changed, with exactly 96 additional record destinations, matching the read-only dry run. A post-deployment dry run found **zero remaining deterministic repairs**. Existing read/unread states and timestamps were preserved; no old delivery was re-enqueued.

Security advisors remained at 29 existing findings, with no added, removed or substantively changed finding; only their observation timestamps changed. The latest minute worker at **23:25:00 UTC** returned HTTP 200 without a timeout or job failure: push configured, zero claimed/sent/failed/retried. This is scheduler health evidence, not a physical delivery test.

## Security boundaries

The four `CREATE OR REPLACE FUNCTION` definitions retain their existing signatures, security modes, search paths and grants. No member check, MFA gate, notification preference filter, billing operation, workflow result or deduplication rule changes. The delivery session and dispatch-preference migrations remain untouched.

The new resolver is private, security invoker and has an empty search path. Execute is revoked from PUBLIC, anon, authenticated and service_role. The existing security-definer trigger can call it inside its established boundary; it is not a new data API. The routing trigger retains its existing restricted grants.

## Verification

- Full local database replay: **92 migrations, 25 suites, 687 passing assertions**.
- New database route suite: **40 passing assertions** covering real public-request/booking/completion workflows, batched entities, recurring and zero-value bookings, overdue/waiting automations, task/note routes, cross-workspace/ambiguous/malformed recovery, deleted records, UPDATE behaviour, queue invariants and unchanged notification metadata/preferences.
- Push Edge tests: **23 passing tests**, including **12 new payload checks** across APNs and FCM for requests, bookings, payments, tasks, notes and the morning summary. All use synthetic RPC/fetch implementations: no network send, real device token or provider credential.
- New TypeScript test passes Deno formatting; scoped diff whitespace check passes.
- The local database harness uses real PostgreSQL in PGlite. Auth/JWT readers and cron/vault metadata are explicit test fixtures; it does not prove GoTrue, the scheduler daemon, device display or tap navigation.

Physical notification tap validation still depends on the owner's iPhone being available. Android provider activation remains blocked by the owner's decision to keep service-account key creation disabled; this routing work does not change that policy. No TestFlight upload is part of this change.

Suggested commit: `Fix notification destinations to open their exact records`.
