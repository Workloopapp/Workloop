# Backend security remediation — 12 September 2026

The live release audit found that an authenticated user who knew an ownerless
workspace UUID could claim its first membership. It also found that deletion
required a workspace and that ordinary authenticated data access did not check
whether the JWT's session still existed. These changes close those boundaries
without claiming orphaned workspaces, deleting their data, or enabling sales.

## Workspace bootstrap: deployed

`20260912191519_restrict_workspace_bootstrap_to_onboarding.sql` removes the two
direct client INSERT policies and INSERT privileges on `workspaces` and
`workspace_members`. It revokes client execution of the empty-workspace helper
and the unrelated trigger-only push-enqueue function. The existing atomic
`complete_onboarding` RPC remains the supported creation path; both current
Flutter and the frozen build-20 repository already use it. Administrative
service-role creation remains available.

The release lead deployed this migration after independent review. The CLI
originally created version `20260912190938`; the hosted provider recorded
`20260912191519`, and the local file was renamed without changing SQL bytes.
SHA-256: `6222db0adcaf4a9ec056dc070092f48859811af06357145638d70770702591d3`.
Readback confirmed both client INSERT privileges false, zero INSERT policies,
and client execution of the empty-workspace helper false. The eight ownerless
workspaces and their business records were preserved.

## Session, deletion and public-owner boundaries

The second migration was prepared and reviewed under CLI version
`20260912190944`, then deployed as
`20260912193144_account_deletion_and_active_session_boundaries.sql`.
The hosted receipt below records the independent post-deployment checks.

- A shared session predicate checks the server Auth account, verified nonempty
  email, ban/deletion state, matching `auth.sessions` row and its expiration.
  Existing RLS/MFA entry points use it, so revoked or captured stale JWTs no
  longer retain ordinary business access. MFA remains required for accounts
  with an enrolled verified factor. Subscription and push registration retain
  their specific active-session errors and recheck after relevant locks.
- Onboarding and deletion take the same account advisory lock. A late
  onboarding request cannot create a workspace after deletion is accepted.
  Existing verified-email validation and atomic onboarding implementation are
  preserved.
- A service-only deletion RPC resolves zero or one owned workspace, rejects
  foreign/shared/multiple memberships, records the existing deletion request,
  and deletes all the user's Auth sessions in one transaction. Pending deletion
  also blocks newly issued sessions from business access. An Auth ban remains
  a best-effort additional barrier, rather than the sole access guarantee.
- The existing nullable workspace column supports requests before onboarding.
  A partial unique account index prevents duplicate open requests, including
  those with no workspace. The only new recorded provider detail is a bounded
  Apple revocation status; no Apple token or authorization code is persisted.
- Public profile reads, availability and booking submission check a current
  verified, unbanned owner without pending deletion. The final booking insert
  trigger repeats this boundary. A signed-out owner still has a public profile;
  an inactive or ownerless workspace is unavailable. Private records remain.
  This does not implement a content moderation or publication approval system.

The five Edge changes use the existing architecture:

| Function | Change | Preserve `verify_jwt` |
| --- | --- | --- |
| `request-account-deletion` | Optional workspace, active session/MFA/sole-owner prechecks, native Apple revocation, atomic request RPC | `true` |
| `complete-account-deletion` | Account-only completion and cross-workspace recheck before scoped cleanup | `true` |
| `get-public-profile` | Service-only active-owner RPC before public business reads | `true` |
| `create-booking-request` | Active-owner RPC and unavailable response for final insert-time rejection | `true` |
| `get-public-booking-availability` | Active public profile RPC before slot queries | `false` |

## Deletion contract and Apple authorization

The authenticated request accepts
`{workspaceId?: string|null, appleAuthorizationCode?: string|null}`. Omitting a
workspace resolves the caller's actual membership; it cannot skip an owned
workspace. JSON is bounded to 16 KiB and the optional code to 4,096 characters.
An accepted result includes `ok: true`, `requestId`, `status`,
`accessLocked: true` and `appleRevocation` with exactly one of:

- `revoked`: Apple accepted revocation of the matched authorization, including
  an already invalid token.
- `manual_action_required`: deletion proceeds but the user must unlink Workloop
  in their Apple Account settings.
- `not_applicable`: the trusted server Auth identity has no Apple provider.

`_shared/apple_account_revocation.ts` exchanges a fresh native code exactly once,
verifies the returned Apple-signed RS256 ID token (issuer, fixed native audience,
time bounds and trusted linked subject), and only then revokes its refresh
token. The ES256 client secret lasts five minutes. Identity authorization comes
from the authenticated server-returned Apple identity, never editable metadata,
email or a client user ID. Apple credentials exist only during this request.

A valid signed credential for a different Apple subject returns HTTP 409 with
`code: apple_identity_mismatch` before revocation, banning or deletion. Missing
credentials, unavailable configuration, token verification failure and Apple
provider failure produce truthful manual unlink guidance rather than trapping
the user in an undeletable account. The Flutter flow requires another explicit
action after native cancellation before making a request without a code. This
follows [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

The existing deletion cron checks pending requests each minute, with provider
errors and retries able to delay completion. The UI may confirm that the request
is accepted and account access is closed, then promise a completion email. It
must not claim immediate complete erasure or a guaranteed duration. Deleting a
Workloop account does not cancel an App Store subscription.

The release lead configured `APPLE_SIGN_IN_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID`,
`APPLE_SIGN_IN_PRIVATE_KEY`, and `APPLE_SIGN_IN_CLIENT_ID` using the existing
SIWA-capable key and native bundle `com.ismaeel.workloop`. All four provider
secret metadata digests matched the intended values, including the PEM; no
values were printed and the temporary environment file was deleted. The helper
accepts actual or escaped PEM newlines. This proves configuration delivery, not
an actual native Apple authorization exchange or revocation.

## Verification

- **56/56 SQL assertions** across `042_workspace_bootstrap_security`,
  `043_account_deletion_sessions`, and `044_public_active_owner`: known orphan
  and other-owner takeover attempts, real onboarding/idempotency, active and
  revoked sessions, MFA, workspace-less and shared ownership, atomic session
  deletion, captured JWT access, and public read/final insertion denial.
- **63/63 Deno tests**, including 41 new Apple/HTTP/public-owner tests plus the
  existing deletion ownership, Stripe offboarding, storage cleanup and email
  helper tests. Synthetic signed tokens exercise signature, audience, issuer,
  age and subject failures. Mocked providers prove an unverified or unrelated
  Apple token is never revoked, and errors are reported truthfully.
- Five deployed entry-point candidates typecheck; ten changed TypeScript source
  and test files pass formatting and lint checks.
- **34/34 focused Flutter contract tests** pass after replacing obsolete
  membership-query/variable-name assertions with active-owner and actual MFA
  result checks. The full Flutter analysis/test/profile run belongs to the
  release lead and is recorded separately.
- The independent QA runner additionally passed **265 SQL assertions** across
  existing RLS, onboarding, subscription, Sandbox, and new boundary suites.
  Its legacy fixture changes add valid synthetic Auth sessions/verified emails;
  they do not weaken negative assertions or production guards.

The disposable runner is `scripts/qa_backend_security_pglite.mjs --sessions`,
with `WORKLOOP_PGLITE_PATH` pointing to an installed `@electric-sql/pglite`.
It uses the real core/onboarding SQL plus the explicitly labelled
`supabase/tests/fixtures/security_boundary_policies.sql` and minimal Auth
fixtures. It is not a full managed Supabase migration replay or penetration
test. Ignored logs and the exact bundle hash manifest are under
`build/appstore-resumed-20260912/backend-security-remediation-*`.

## Deployment procedure and remaining evidence

1. Recheck live function sources and replaced SQL against the audit snapshots;
   stop on unexpected drift. Confirm no duplicate open deletion requests for
   the new partial unique index. Completion preserves existing nonempty admin
   token compatibility while comparing without content-dependent early exit;
   missing/mismatched credentials fail closed. Any future rotation must remain
   coordinated with the worker using that secret.
2. Apply only the reviewed second migration, then read back its SQL, constraints,
   ACLs and RLS dependencies. Align the local migration version to the provider
   record without changing SQL bytes if needed.
3. Deploy the five functions above with their exact recursive local dependencies,
   `deno.json`, `deno.lock` and unchanged JWT settings, as recorded in the ignored
   `backend-security-remediation-bundle.json` manifest. In particular, include
   the new Apple helper and the availability contract's shared request validator.
4. Recheck security advisors and only rejection-path endpoint probes. Do not
   manually invoke the valid deletion/shared email worker, create a customer
   fixture, delete records or send a real message for this verification.
5. Preserve all 17 lifetime accounts, zero review grants and current global
   flags: beta open; subscription enforcement, Apple sales, Google sales and
   billing reminders disabled. Preserve all orphan records.

The six existing SECURITY DEFINER advisor warnings were individually reviewed
in the audit; their required public wrappers remain with constrained execution
and empty search paths. Their presence does not mean they were ignored or
automatically fixed by this change.

Remaining proof is physical device session-storage/upgrade checks, genuine
native Apple authorization and
the intended Sandbox purchase lifecycle. Public-content reporting/moderation
is a separate product decision. These source tests do not make the app publicly
released, Apple-approved, or free of every possible vulnerability.

Suggested commit: `fix: secure workspace bootstrap and account deletion`.

## Hosted deployment receipt

The release lead applied only the reviewed second migration and deployed the
five functions on 12 September 2026. Live preflight found no meaningful source
drift (only trailing whitespace), zero duplicate open deletion requests, and
zero pending requests. The first Edge deployment attempt failed before deploy
because of an inherited stale absolute import-map path; explicitly selecting
each function's `slug/deno.json` resolved it.

The provider recorded migration `20260912193144`. The local CLI-created file
was renamed and both QA harness references updated, without changing SQL bytes.
SHA-256: `ad879de63d05f809cb3a6f7fb8fdfbea9a8a4d0523798ad6551558621356773f`.
An independent provider readback confirmed **exact statement-byte equality**
for both security migrations, and all **13 new/replaced SQL function bodies**
matched the local source.

| Function | Active deployed version | `verify_jwt` |
| --- | --- | --- |
| `request-account-deletion` | 30 | `true` |
| `complete-account-deletion` | 37 | `true` |
| `get-public-profile` | 31 | `true` |
| `create-booking-request` | 34 | `true` |
| `get-public-booking-availability` | 7 | `false` |

All 20 returned TypeScript/config files matched the reviewed local bundle,
allowing only boundary whitespace. The provider source API does not return
lockfiles; their supplied local hashes remain recorded in the manifest.

Readback at **19:33:52 UTC** confirmed the service-only deletion and public-owner
RPC grants, authenticated-only current-session access, empty search paths,
the new partial unique account index and the active-owner final booking insert
trigger. Client workspace/membership INSERT remains denied with zero INSERT
policies. Counts remained **33 Auth sessions, 8 ownerless workspaces, 17 lifetime
accounts, 0 Sandbox grants and 0 open deletion requests**. All subscription
rollout flags, including their existing timestamp, were unchanged.

Seven rejection-only HTTP probes passed: missing/anonymous deletion credentials
401, malformed deletion body 400, incorrect completion admin credential 401,
and invalid public profile/booking/availability input 400. No authenticated
customer action, valid worker invocation, account creation/deletion, booking,
provider charge or email was performed.

The security advisor still reports the same six individually reviewed
[authenticated SECURITY DEFINER warnings](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
and 26 private-table
[RLS without client policies notices](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
The notices are retained intentionally; this receipt is evidence of the scoped
fixes, not a claim of a complete penetration test or Apple approval.

Ignored evidence is captured in `backend-security-remediation-live.json`,
`backend-security-remediation-comparison.json`,
`backend-security-remediation-probes.json` and the updated bundle manifest under
`build/appstore-resumed-20260912/`. The release candidate must include the final
renamed migration, harness references, source changes and tests.
