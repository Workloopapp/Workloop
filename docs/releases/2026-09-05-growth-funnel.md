# Growth funnel and learning email journey — 5 September 2026

Audience: people who work for themselves, by themselves. Product-specific examples remain grounded in Workloop's client/service workflow.

## Implemented

- Marketing website commit `323108eea1c3457b6a2bcd0b827527d4f0846eae`, Sites version 30, deployment `appgdep_6a9bdec1a1e88191a02b791dd14f7345` succeeded. Custom-domain `/help/welcome` returned the new pack and learning form in an independent HTTP fetch.
- Welcome pack lives under the already reserved `/help` route, avoiding a new root route that could displace a customer's public handle. Optional confirmed email signup and `/help/email-preferences` added. Launch-list consent is checked server-side. Channel attribution is allowlisted and contains no email address or advertising cookie.
- Migrations `20260905091335_consented_learning_email_journey.sql` and `20260905091547_schedule_consented_learning_emails.sql` applied to `imtbyrvsonzvtddswbtb`.
- Separate private contacts/outbox for optional learning series; no existing users or waitlist entries silently enrolled. Confirmation expiry, unsubscribe, signed bounce/complaint suppression, retry leases, idempotency, queue spacing and account-deletion cleanup included.
- `learning-series` v1, `resend-webhook` v10, `drain-booking-confirmation-emails` v25 and `join-waitlist` v14 deployed. Existing drain source preserved except updated account/waitlist welcome content linking to the pack.
- Nine lessons over 28 days, with exploring/using variants. Resend sender hello@workloop.uk, reply-to support@workloop.uk. Existing transactional onboarding also links to the readable pack; this does not subscribe recipients to the series.

## Validation

- Website: 21 tests, typecheck, lint, build, diff checks passed.
- Private database journey: 14 PGlite checks passed, including grants, leases, confirmation, ordering, unsubscribe, suppression and account deletion. Content tests passed through the Node TypeScript runner; this was not a local Deno test invocation. Deployed Edge Functions compiled on Supabase.
- Controlled owner Gmail alias received confirmation and welcome pack. Resend receipt IDs: `43e20d9f-068d-434c-87fd-162f44ff623d` and `9d721b1d-ce19-41c8-b197-4a5fcee74854`. The QA contact was then unsubscribed through the public endpoint; zero pending/processing follow-ups remained.
- Flutter analyze clean; 485 tests passed, 4 skipped; profile iOS build succeeded (73.6 MB). No Flutter feature source was changed for this growth work. This is not evidence of a new TestFlight upload or device installation.

## Incoming mail: unresolved provider gate

Authoritative UK2 DNS resolves normally. Root MX is `mx.stackmail.com` (185.151.28.67). An external Gmail message to support@workloop.uk bounced with SMTP `550 We were unable to find the recipient domain.` This is receiving-host provisioning/routing failure, not proof that the domain is unregistered. Resend Sending is verified; Receiving is disabled.

UK2 CHI account is signed out. User has been asked to sign in so domain/mailbox provisioning can be inspected. Do not replace MX blindly, claim support receives mail, or migrate account login addresses before external delivery and reply are verified. Preserve independent domain/mail-host recovery access.

## Social and campaign deliverables

Files: `/Users/ismaeelsmiley/Documents/Workloop Launch/growth-2026-09`.

- X @workloop789 profile avatar/banner/name/bio/location/link updated and read back.
- Introduction published and pinned: https://x.com/workloop789/status/2096168936878264779
- Practical checklist published: https://x.com/workloop789/status/2096169198409883692
- 28 native X scheduled entries verified individually, 6 September–3 October 2026, 12:15 British Summer Time. This schedule is hosted by X and does not require the Mac or phone to remain connected.
- One relevant public outreach reply published: https://x.com/workloop789/status/2096195798178402764 . No bulk unsolicited DMs sent. Group outreach remains research/permission-dependent.
- 30 X posts, 15 landscape graphics, matching profile banner; six paid-ad copy variants with twelve platform-sized graphics. Paid campaigns are templates only; no budget or spend activated.
- 18 lesson previews plus confirmation, marketing strategy and editable outreach starters. HTML design collection is prepared locally; not yet imported as a new Canva design.

## Follow-up

Repair and verify receiving/replies; then address account-login migration selectively. Continue appropriate community outreach, Facebook-specific scheduling and a measured seven-day campaign review. Keep paid activation behind an explicit spend cap. Monitor the optional queue and signed webhook suppression without enrolling unrelated audiences.

Suggested commit message: `Add consented Workloop learning journey and welcome-pack links`.

## Mailbox purchase follow-up — 5 September

User approved the UK2 2GB mailbox purchase. Order 9019770, invoice 8035104, total £7.20 including VAT for one year. Account Statement records payment and UK2 now shows one available mailbox. The support@workloop.uk creation form is prepared; password creation handed to the owner under computer-use credential rules. Mailbox creation and delivery/reply verification remain pending. Existing MX and root SPF already match Stackmail; no DNS changes made.

## Support mailbox verified — 5 September, 15:42 BST

Owner created the password and saved support@workloop.uk. UK2 now lists the 2GB mailbox, 1 used / 0 remaining. UK2 Manage → Log into Webmail → Authenticate opened the inbox without exposing credentials. External Gmail message `1a0720147da93f53` was read in Stackmail (Inbox UID 1). A reply sent through Stackmail with From support@workloop.uk arrived in the owner Gmail Inbox as `1a0720519c661bc1` at 15:42:10 BST. Incoming and outgoing reply delivery are both verified. Workloop Support display name, Workloop company and plain-text support signature were saved and read back. No DNS changes or account-login migrations. Resend marketing sender remains hello@workloop.uk with replies to support@workloop.uk.

## Authorized evening growth session — 5 September 2026

Eight Facebook-specific posts were created and accepted by Meta's native scheduler for 7, 10, 14, 17, 21, 24 and 28 September and 1 October, all at 18:00 BST. Every full caption, date/time, Facebook destination, Public audience and unboosted state was read back; native IDs were captured from each Post details panel. The records are in `growth-2026-09/facebook/publishing-ledger.json`. These are future scheduled posts, not public publication receipts. No Instagram or Story cross-posting was enabled, and the existing X/TikTok schedules were not duplicated.

The paid pack now contains seven campaign briefs, fourteen creative concepts and fifty-six platform copy rows with matching PNG/SVG exports. `growth-2026-09/ads/launch-review-v2.zip` passed its integrity and asset checks. Caps, dates and activation are unset. The measurement plan explicitly records that channel-level signup attribution does not establish which individual creative converted.

A read-only production email check found zero open optional-learning messages, queue errors, expired leases or unsubscribe leaks. The one original QA contact is unsubscribed; its two sends and eight cancelled follow-ups remain recorded. Recent learning and transactional HTTP responses were successful, and all fifteen recently recorded provider sends had delivery receipts. Earlier afternoon worker failures are preserved in the dated email-health report rather than presented as current failures. This optional series is distinct from normal account lifecycle emails. No recipient was enrolled or emailed by this audit.

The support inbox's earlier external receipt/reply test remains the verification evidence. UK2 and Stackmail were signed out during this evening session. No mailbox, DNS or login migrations were attempted. Community rules were researched and five tailored contributions prepared, with restricted or membership-dependent channels clearly held. No new group post or private message is claimed.

The one-off evening automation session was removed after the attempt, using the automation tool. The same existing heartbeat remains active at 18:30 only through 4 October, preserving its complete Instagram publishing instructions. No Instagram campaign material, TestFlight build, Play build or paid campaign was published during this session.
