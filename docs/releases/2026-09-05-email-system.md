# Workloop email system — 5 September 2026

## Behaviour

- Support: support@workloop.uk is the UK2/Stackmail inbox. Incoming Gmail and an actual support reply were verified earlier today. Workloop account/tips mail uses hello@workloop.uk; booking mail uses bookings@workloop.uk. Workloop replies route to support; new customer reminder replies route to a verified business owner, falling back to support.
- New eligible account signups default to the account journey after verification, with a clear opt-out offered before signup. Existing unconsented users are not backfilled; previous unsubscribes and finite-series scope are preserved. This is required for UK soft opt-in, including qualifying free-trial enquiries. Unsubscribe is in every marketing email; security/account service emails remain separate.
- Account journey: existing immediate account welcome, nine practical onboarding emails on days 2/4/6/9/12/16/20/25/30, then weekly tips for active users. Twelve rotating topics cover clients, scheduling, pricing, payment follow-up, marketing, recommendations and referring another solo owner to Workloop. Inactivity emails at 14/30/60 days stop when the user returns; long-inactive accounts pause. Messages have HTML and text bodies, delivery caps, idempotency, unsubscribe and bounce/complaint suppression.
- Customer reminders: configurable 24-hour, 2-hour and 1-hour intervals. New workspaces default to 24 hours and 1 hour. Existing workspaces must choose timings first, avoiding unexpected sends for imported beta bookings. A valid recipient email is required. Newly accepted requests retain the requester's actual email even when phone matching finds another contact address. Cancelled/rescheduled bookings, changed recipients, disabled settings and unsubscribes are rechecked before delivery. Expired reminder windows are not replayed.
- App: Settings → Notification preferences has Customer booking emails and Emails for you. The signup review presents the notice before email/social account creation. Activity reporting is best-effort, authenticated and does not block app use.
- 64 Workloop template variants are catalogued, including auth/security, account lifecycle, booking confirmation/reminders, launch/welcome journeys, weekly advice and inactivity. Stripe payment receipts remain processor-managed; human support uses the configured signature.

## Implementation and deployment

App source: auth screen/repository, main bootstrap, shared/email, settings email section, privacy text. Backend: three deployed Edge Functions (learning-series, drain-booking-confirmation-emails, resend-webhook), shared account/reminder templates, dated migrations 20260905145541 / 20260905151826 / 20260905152125. Schema contract and regression tests document the new settings and private queues.

Production is imtbyrvsonzvtddswbtb. No broad auth.users permission was granted. Live QA revealed that hosted service_role lacks direct Auth-table privileges and auth.users.email is varchar(255); narrow private definer worker helpers and an explicit text cast repaired those assumptions. Public RPC wrappers remain invokers and service-only. The local replay now models the hosted email type; regression tests revoke Auth table access before running the worker calls.

Public website version 31 is live from source 7026371fa7fa3d8d8c561c2e4313d0d33b9d4e99. Cache-busted workloop.uk/help/email-preferences returned the new customer-reminder and inactivity guidance. Privacy wording also updated.

## Verification

- Flutter: full suite 485 passing / 4 skipped before three additional email-settings tests; all three new tests pass. Static analysis passed. Signed iOS profile build passed. Final Build 12 validation/distribution recorded below when complete.
- Database: full migration replay and 18 suites, 436 assertions pass in PGlite/pgTAP. Auth/cron/vault bootstrap is simulated; real scheduling was verified separately against production HTTP responses, not merely cron's enqueue success.
- Email content/worker unit checks: 7 pass, covering all 24 account templates, reminder intervals/timezones, escaping, private-note exclusion, revoked claims, retries and stable idempotency.
- Website: production build, typecheck, lint and 21 rendered tests pass.
- Live controlled QA alias received account welcome, first account onboarding email, and one-hour booking reminder. Gmail IDs: 1a0721f7e7f3eea8, 1a07227833651766, 1a0722993447700f. Onboarding Resend ID 5aa9a163-e959-4b08-9c03-6fbaaea34cf7; reminder b6508b6a-6c59-4213-8ed0-46d340acb5c8. SPF, DKIM and DMARC passed. Marketing Reply-To was support; reminder Reply-To was the test business owner's verified email.
- GET unsubscribe pages did not alter preferences. Both one-click POSTs returned 200; marketing became unsubscribed with zero pending/processing future messages; reminders stopped while the booking remained scheduled. Temporary QA workspace/account were then deleted; no real customer received a test.
- Scheduled worker returned repeated HTTP 200 with no failed jobs after the fixes. Existing private-table RLS warnings are informational; no new public definer exposure was introduced.

Preview collection: /Users/ismaeelsmiley/Documents/Workloop Launch/growth-2026-09/emails/full-catalog/index.html.

## Remaining release boundary

At this report's initial capture, backend and website changes are live, but Build 12 is being prepared. Build 11 does not contain the new email controls. Android store availability still depends on the outstanding new Google Play account requirements. No live-card collection readiness claim is made by these email tests.

Suggested commit: feat(email): add customer reminders and consent-aware account journeys

## Release hold requested by owner — 5 September 2026
Do not upload Build 12 to TestFlight yet. The owner wants further improvements before distribution. No Build 12 upload occurred. Final Flutter verification: 488 passing / 4 skipped; static analysis has no issues. Local signed profile build passed. The initial isolated archive attempt stopped at dependency resolution because its environment selected an older Flutter SDK; no distribution artifact was produced. Any later release must explicitly use /Users/ismaeelsmiley/flutter and include the owner's additional changes before capture/build/upload.

Latest preserved source snapshot: /Users/ismaeelsmiley/Workloop-Releases/build12-20260905T153844Z/Workloop, commit 1508959beb17b7fab3677b93c73a93a707ba0d25. This is a local source snapshot, not a TestFlight release. Backend/website/email delivery and unsubscribe verification remain complete.
