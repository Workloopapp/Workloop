# Account access methods — 5 September 2026

This is source/configuration evidence, not a claim that every external account
journey has been completed on a device. No TestFlight upload is part of this pass.

## App changes

- Retain email/password sign-in, explicit account creation, recovery, native
  Apple on iPhone, and Google OAuth.
- Add a compact additional-methods sheet. It offers a one-use email sign-in
  link; existing-account mode uses `shouldCreateUser: false`. New-account mode
  first shows the existing email notice and sends the explicit choice as signup
  metadata. Existing user preferences are not overwritten.
- Keep the sign-in form close to the top, with a compact brand row and account
  creation after the sign-in choices. Standard and small-phone tests require the
  first field within 240 logical pixels; enlarged text and the keyboard retain
  scroll access.
- Implement SMS code send/verify/resend, explicit international phone numbers,
  bound verification recipient, pending-state guards and a 60-second resend
  cooldown. SMS controls stay hidden unless both the release flag and the live
  Supabase phone provider are enabled. Autoconfirm is not accepted as real SMS.
- Implement Apple OAuth for Android/web behind its separate release flag and
  live Apple-provider capability. Native Apple continues using a nonce and ID
  token. Optional name persistence can no longer turn successful Apple sign-in
  into a false failure message.
- Add `AuthContactEmailScreen` and `accountNeedsVerifiedEmail`. AuthGate must show
  this before workspace access for a session without a verified email. The
  screen uses Supabase email-change verification and refreshes the real session;
  it does not use a local verification flag. This preserves account recovery,
  receipt and email-lifecycle requirements for future phone identities.
- Read only the public `/auth/v1/settings` endpoint, using the public project
  key. Discovery failure shows a retry, and the send action rechecks current
  capabilities. No private provider credentials are shipped to Flutter.
- Repair Android's missing `workloop://auth-callback` intent filter. Keep both
  native platforms' Auth links owned by Supabase/app_links, with Flutter's
  competing default handler disabled. A waiting Auth screen also listens for
  the actual SDK sign-in event before returning to the workspace route.

## Live checks made during this pass

| Method | Observed configuration | Remaining evidence |
| --- | --- | --- |
| Email | Provider enabled; signup allowed; email confirmation required. Existing branded magic-link template links through Supabase confirmation. | Fresh external inbox delivery and link return on the final build. |
| Google | Provider enabled. Public authorize endpoint redirects to `accounts.google.com` with the expected Supabase callback. | Complete sign-in/account linking and verify consent-screen public status. |
| Apple native | Apple provider enabled; app uses native ID-token flow. | Complete Apple authorization on the final signed iPhone build. |
| Apple Android/web | Public authorize endpoint returned `Unsupported provider: missing OAuth secret`. | Configure/verify Apple Services ID and OAuth secret, then complete browser sign-in and callback. |
| Phone | Provider disabled. Public settings include the label `twilio`, which does not prove working credentials. Owner confirmed no SMS provider account exists yet. | Configure a real funded provider, sender, delivery/rate controls and verified-email gate; test send/verify/expiry/recovery before release. |

Release flags default **false**:

```
WORKLOOP_PHONE_AUTH_ENABLED
WORKLOOP_APPLE_OAUTH_ENABLED
```

Enabling a flag is not provider activation. Keep both false until the respective
external journey is verified. SMS spend was not enabled. Other disabled OAuth
providers are not advertised through nonfunctional buttons.

Migration `20260905184601_require_verified_email_for_workspace_setup.sql` adds the same
verified-email requirement to the existing onboarding RPC after its identity,
deletion and MFA checks. It calls the unchanged transactional implementation and
preserves retries. It is deployed in Supabase under version `20260905184601`,
with the local filename reconciled to that version without changing its SQL.
Phone signup remains gated until its provider/device checks are complete; the
app gate alone is not a database authorization boundary.

## Verification

`test/auth_access_methods_test.dart` covers explicit signup vs sign-in,
capability/release gates, SMS verification type, missing-session rejection,
phone normalization, contact verification and the additional-methods UI.
Existing compact, auth-validation, metadata, and sign-out tests remain relevant.

The scoped run passed **27 tests** across `auth_access_methods_test.dart`,
`auth_screen_compact_test.dart`, `auth_metadata_test.dart`,
`auth_sign_out_recovery_test.dart` and `core_audit_auth_import_test.dart`.
Scoped Dart analysis, `plutil -lint ios/Runner/Info.plist`, and the scoped
`git diff --check` also passed. Initial runs exposed and corrected a compact
layout regression; no golden images were automatically rewritten.

Full local migration replay in PGlite passed the **19 assertions** in
`supabase/tests/database/021_auth_verified_email_onboarding.test.sql`. These
exercise PostgreSQL functions and the actual welcome/journey triggers: initial
email verification for a phone-first identity queues one welcome and the existing
nine-step account journey, while an opt-out stays unsubscribed. PGlite stubs the
Supabase Auth table/JWT readers and scheduler metadata; this is not SMS delivery,
GoTrue verification or production deployment evidence.

### Adversarial retry and account-switch pass

The follow-up pass adds seven regressions in
`test/auth_onboarding_edge_cases_test.dart`. A signup confirmation received on
the direct `/auth` route now enters the app; password-recovery events keep their
separate routing. Once workspace creation commits, a failed or unresponsive
first-name metadata update no longer reports the whole setup as failed. Account
identity is checked before metadata and before returning the saved workspace.
Persistent setup errors also offer **Review setup** so the owner can correct a
booking-link conflict rather than endlessly retrying identical data.

The combined auth, onboarding and guide run passed **31 tests**, including a
delayed guide lookup after an account change. Initial new test runs exposed
fixture API mismatches and missing mock storage/HTTP response metadata; those
fixtures were corrected before the clean run. This remains local test evidence,
not proof of live OAuth or SMS delivery.

The final integration review also identified delayed invalid-session cleanup
as a sign-out race. `AuthRepository.signOutLocal(expectedUserId: ...)` now checks
the expected account before and after its push-cleanup wait. Two regressions
prove that a new account is retained when an old cleanup finishes, while normal
matching-account sign-out still works. The sign-out, existing workspace-gate and
onboarding edge suites passed **18 tests** together. AuthGate must supply the
identity captured when verification failed, before scheduling its cleanup.

The integrated AuthGate now supplies that captured identity. A widget regression
delays old-account draft cleanup, verifies a different account, then releases
the old cleanup and confirms the new workspace stays open without a sign-out.
The final sign-out and workspace-gate run passed **12 tests** together.


### Final small-phone layout recovery

The full application suite caught a real first-run discoverability regression:
**Create account** appeared after all social buttons, below a 320×568 viewport.
It now sits immediately after **Sign in**. The existing no-scroll account-action
assertions remain unchanged; the standard iPhone form still fits and the first
email field remains within 240 pixels of the top. Notification settings wording
was already correct; its test now scrolls to each precise label rather than
assuming the newer, longer settings page needs only one short drag.

The targeted beta UI, complete launch responsive matrix, compact auth and auth
onboarding edge-case suites passed **18 tests**. Log:
`/tmp/workloop-auth-layout-recovery.log`. The login golden requires review for the
intentional account-action relocation.

## References

- [Supabase passwordless email](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Supabase phone login](https://supabase.com/docs/guides/auth/phone-login)
- [Flutter OTP send](https://supabase.com/docs/reference/dart/auth-signinwithotp)
- [Flutter OTP verification](https://supabase.com/docs/reference/dart/auth-verifyotp)
- [Supabase Sign in with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Flutter plugin-based deep linking](https://docs.flutter.dev/ui/navigation/deep-linking)

Apple's browser OAuth secret requires rotation at least every six months;
native ID-token sign-in does not use that OAuth secret.


## Apple provider configuration completed during integration

Registered the Services ID `com.ismaeel.workloop.web` with customer-facing name
Workloop, grouped with native `com.ismaeel.workloop`. Apple has the Supabase
project domain and HTTPS Auth callback registered. A dedicated Sign in with
Apple key was stored outside the repository with private filesystem permissions;
no private key or OAuth secret is included in the app or this document.

Supabase now has the Services ID first and preserves the native bundle ID as an
accepted client. The previously missing OAuth secret is configured. A live
public authorize request returns HTTP 302 to Apple with the correct service ID
and callback, and Apple's real sign-in page renders. This proves provider
configuration and the authorization handoff, not the completed identity/token
exchange or return on a physical Android device. The browser-flow release flag
stays false pending that final journey.

The current OAuth secret expires **4 March 2027 at 18:44:46 UTC**. Rotate it
before that date (preferably with at least 30 days margin). The key/rotation
metadata is held under the owner's private local Workloop configuration folder;
there is no scheduled automatic rotation. Native Apple ID-token sign-in does
not depend on this browser OAuth secret.

## Google public access and branding verified, 5 September 2026

The final Google Cloud check found that project `workloop-502614` was still
External/Testing with one test user, and its incomplete branding prevented
publication. Added the live Workloop home, privacy and terms links (each
returned HTTP 200), registered `workloop.uk` alongside the existing Supabase
callback domain, and declared only the basic email, profile and OpenID scopes.
The existing OAuth client and callback were preserved.

Google Auth Platform now reports **In production**. The Verification centre
confirms that data-access verification is not required for these non-sensitive
scopes. The separate branding check passed and was published; the dashboard
now says the verified branding is being shown to users. No additional account
data scopes or new provider credentials were introduced.

This removes the test-user restriction and verifies the live provider/branding
configuration. It does not substitute for completing Google authorization,
account linking and return to the final native build with a user account.
No TestFlight upload was made. Phone sign-in remains disabled following the
owner's decision to pause SMS on cost.
