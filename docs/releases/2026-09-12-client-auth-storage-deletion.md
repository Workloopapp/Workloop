# Native session storage and account deletion — 12 September 2026

This change addresses the client findings from the App Store release audit. It
adds no server secret, billing flag or entitlement bypass. Provider configuration
and Supabase deployment are separate release evidence.

## Native sign-in persistence

- Supabase Flutter 2.16.0's supported `LocalStorage` and `GotrueAsyncStorage`
  interfaces now use pinned `flutter_secure_storage` 10.3.3. Version 11 conflicts
  with the existing Windows dependency graph, so this uses the maintained v10
  patch without upgrading unrelated packages.
- The session and PKCE recovery verifier migrate from the SDK's existing
  SharedPreferences keys. Every secure write must read back exactly before
  deleting the corresponding old value. Initial migration retains all legacy
  values until all required secure writes succeed, so a partial failure retries.
  Startup also completes both legacy cleanups after an interrupted installation
  marker commit, without waiting for a later PKCE flow.
- iOS/macOS use first-unlock, device-only Keychain access without iCloud sync or
  a biometric prompt. Android uses the package's RSA OAEP/AES-GCM defaults with
  automatic reset on storage errors disabled. Existing Android backup and
  device-transfer exclusions remain in place.
- A per-installation marker prevents iOS Keychain values surviving an uninstall
  from silently reopening the previous installation's account. Only this
  installation's legacy session is eligible for initial migration.
- Operations are serialized. Sign-out awaits explicit local cleanup and writes
  non-secret removal markers before deleting secure values, preventing a failed
  Keychain delete or queued older refresh from restoring a signed-out account.
  A normal persistence write also marks its prior value unusable until the new
  value verifies: a failed direct account replacement cannot reopen the previous
  account. If persistence fails, a subsequent successful write restores normal
  restart behavior; otherwise the user must sign in again after restarting.
  Initial legacy migration keeps its original retry-preserving behavior.
  Cleanup affects only Workloop's session and PKCE verifier.
- Temporarily inaccessible secure storage shows a retry screen instead of
  treating a saved session as missing. Storage error descriptions are generic
  and never contain a token or native error payload. Web retains the SDK's
  existing browser persistence behavior.
- Empty `keychain-access-groups` arrays are included in the existing iOS/macOS
  entitlements per the package setup. No shared app group is configured.

## Deletion and Sign in with Apple

- Deletion no longer requires completing workspace onboarding. A known workspace
  can be supplied; a missing or unavailable lookup is omitted and the
  authenticated server resolves ownership. The client never sends a user ID.
- Accounts with an Apple identity request a fresh native authorization code.
  This does not call Supabase sign-in or identity-link APIs. The one-use code is
  held only through the authenticated deletion request body, never stored or
  logged. Account/page changes discard the result before deletion.
- The server is responsible for exchanging the code, verifying Apple's signed
  subject against the caller's trusted existing Apple identity, and revoking
  the matching authorization. The client requires `ok=true` and
  `accessLocked=true` before treating the deletion request as accepted.
- Cancelling or failing the Apple confirmation does not request deletion or sign
  out. An explicit secondary action can continue deletion without Apple,
  consistent with Apple's TN3194 guidance. A different Apple identity is shown
  as a recoverable mismatch.
- The accepted result has `appleRevocation` equal to `revoked`,
  `manual_action_required`, or `not_applicable`. Unknown/missing status keeps
  manual unlink guidance. A neutral confirmation route survives local sign-out
  and links to the official Apple Account page with unlink instructions.
- The sheet and confirmation describe the existing once-per-minute pending
  worker and possible provider delays, then promise only completion email;
  they do not state a guaranteed completion duration. They continue to explain
  that account deletion does not cancel an Apple/Google subscription.
- Embedded subscription terms make seven/three-day reminder language conditional
  on availability for the plan, matching the server-controlled reminder flag.

## Verification and remaining evidence

Focused client analysis passed. The focused suite covers secure migration,
partial and silent-write failure, locked-store retry, reinstall protection,
logout/refresh ordering, account replacement, PKCE migration/cleanup, native Apple
cancellation and identity changes, authenticated request payloads, unconfirmed
server results, manual unlink after sign-out, and compact 320px/2x light/dark
confirmation screens. No actual Apple authorization prompt or deletion was
performed by these tests.

The release lead must run the full required Flutter checks and build a new
numbered candidate. A physical iPhone upgrade/restart test must verify the
Keychain migration, session persistence, logout and recovery. Inspect the signed
candidate's effective Keychain entitlements and verify native read/write on the
device; Dart tests do not prove platform storage or signing behavior. Test the
Apple authorization prompt only with the intended review/test identity and do
not invoke real account deletion as a release smoke test.

Primary references:
- [Supabase Dart initialization](https://supabase.com/docs/reference/dart/initializing)
- [flutter_secure_storage package documentation](https://pub.dev/packages/flutter_secure_storage/versions/10.3.3)
- [Apple TN3194: Handling account deletions](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
