# Native subscription client verification — 7 September 2026

## Client changes

This pass reviewed the new Flutter subscription implementation against its
server-authoritative access contract. It does not enable billing or change any
backend flag, database object, store agreement or live entitlement.

- Store callbacks never grant local access. The signed proof goes to the
  authenticated `workloop-subscription` verifier; access is then reloaded through
  `get_workloop_access`. Empty or rejected proof is never marked complete.
- Verification uses the captured current account token and checks identity and
  disposal again after awaits. Account changes cannot finish an old owner's
  transaction or update the new owner's screen.
- Identical successful callbacks are deduplicated. A different signed proof
  cannot reuse a cached verification merely by sharing a transaction ID.
  Store acknowledgement retries remain distinct from failed server verification.
- Explicit Restore rechecks previously verified proofs against the server,
  allowing current expiry/revocation state to be reflected. An empty restore
  does not claim to have found or verified a subscription.
- A late product query cannot overwrite a newer payment approval or verification
  state. Failed loads clear stale products. Pending approval prevents another
  purchase while leaving Restore available.
- The access gate schedules expiry even when access was already cached before
  mounting. Cached server time advances with a monotonic stopwatch. At expiry,
  retained content loses pointer, focus and accessibility access while the server
  refresh runs. Changing account discards the previous account's subtree.
- The plan screen loads products per account, suppresses purchasing when access
  verification fails, and retains the root implementation's separate export/
  deletion and account/sign-out destinations when access is expired.

Files: `lib/features/subscription/{store_purchase_service,subscription_access,
subscription_gate,subscription_screen}.dart`.

## Test evidence

The final focused batch passed **47/47 tests** with `.env`. It covers the new service, access gate, real mocked
verification-to-access integration, existing account safety and four new visual
baselines. The store fake implements `InAppPurchase`; all HTTP requests use a
local `MockClient`. No purchase, email or customer notification was sent.

- Service cases cover price/account association, missing products, unavailable
  stores, load/purchase races, approval/cancellation/errors, failed/empty proof,
  duplicate events, changed proof, acknowledgement retry, account switch,
  disposal, successful/empty/failed restore and unsupported platforms.
- Gate cases cover unknown access payloads, account switches during RPC,
  loading/error/retry, cached trial expiry, isolated account subtrees, lifetime
  purchase suppression, store-priced plans, and successful verified reopening.
- Export, deletion and sign-out controls are reachable at 320px width and 2x
  text. Existing account safety regressions remain in the focused batch.
- Four light/dark/large-text images were inspected before accepting their new
  baselines; no overflow was present. The initial capture run failed only
  because those new baseline files did not yet exist.

Tests: `test/store_purchase_service_test.dart`,
`test/subscription_access_gate_test.dart`,
`test/support/subscription_fakes.dart`,
`test/golden/subscription_golden_test.dart`,
`test/golden/files/subscription-*.png`.

## App Store Connect evidence and remaining work

Native Safari confirmed the monthly draft exists in Workloop group `22364660`:
Apple ID `6809246089`, product ID `workloop_monthly`, duration one month. UK-only
availability was saved and read back as one of 175 territories. No introductory
offer, review submission, release, paid agreement or financial attestation was
performed by this pass.

The Mac then stopped accepting native input and screenshots were unavailable.
Work stopped at the subscription base-currency menu. Monthly price/localisation,
the annual draft, same-level grouping, outside-app purchasing settings and both
notification URLs still require completion/verification in the unlocked UI.
Do not infer those steps are complete from the Flutter source or mock tests.

Native signed-purchase/sandbox testing, real product lookup, signed builds and
distribution remain parent release tasks. The client tests establish behaviour
under controlled inputs, not a completed live StoreKit purchase. Refer to
`2026-09-07-subscription-backend-verification.md` for separate backend evidence.

Suggested commit message: `Harden native subscription restore and account access lifecycle`.
