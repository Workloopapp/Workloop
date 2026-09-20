# Android beta candidate — 7 September 2026

The owner wants colleagues to test Android today and prefers an official Google
Play beta. Both Android artifacts are prepared from the same frozen, tested
source as iOS build 14. They are not yet distributed through Google Play.

## Build and checks

- Version **1.0.0 (14)**, package `com.ismaeel.workloop`.
- Frozen source commit `9abee299b88f5fd639c54ca3c2ab9b5184a146d7` in
  `/Users/ismaeelsmiley/Workloop-Releases/build14-20260907T072221Z/Workloop`.
- Signed universal APK and signed Play App Bundle built successfully using the
  existing Android release signer, not the emulator debug key. Signing material
  remains ignored and private; the original dirty checkout was preserved.
- Android 8.0/API 26 minimum, target API 36; ARM64, ARM32 and x86-64 included.
  Release is not debuggable. APK signature verified and certificate matches the
  preceding build 13 release certificate.
- Bundletool validation and bundle manifest checks passed. JAR verification
  passed with the previously recorded self-signed/no-timestamp and streaming
  entry-order warnings; Google Play acceptance is not yet established.
- All twelve ARM64 native libraries meet 16KB ELF load-segment alignment.
- Source test evidence is unchanged from the iOS build 14 receipt: clean analysis,
  1,011 full-suite passes with six capability skips, then seven enabled-payment
  passes covering those gated cases. No runtime code changed for Android packaging.
- Actual release APK cold start, sign-in options, native Back and safe bare auth
  callback/reset routing passed on a new isolated Android API 36 ARM64 emulator.
  No account was signed in and no customer data or messages were created. This
  does not replace authenticated signup/verification, Google return or physical
  Android feature testing.

Artifacts, hashes, build/signature logs and `android-release-verification.json`
are beside the frozen checkout. Emulator evidence is in
`/tmp/workloop-android14-qa`, with the completed compact durable copy in
`/Users/ismaeelsmiley/Workloop-Releases/build14-20260907T072221Z/android-qa`.

## Google Play state

Live Play Console still shows new account registration for
`ismaeelsmiley1@gmail.com`. The organisation route is appropriate for Haani
Enterprise Limited; its existing D-U-N-S **232224218** is recorded in the verified
company receipt. The owner has been asked which Google account should permanently
own this registration. No account was created, no registration fee paid, no terms
accepted, no Play app created and no release uploaded during these checks.

Google displays a one-time **US$25** registration fee and company/contact
verification requirements. The proposed first release is an internal test track;
testers join with their phone's Google account. Completion and timing remain
subject to account setup and Google's verification/release processing.

Official references:
- https://support.google.com/googleplay/android-developer/answer/9845334
- https://support.google.com/googleplay/android-developer/answer/13628312
- https://support.google.com/googleplay/android-developer/answer/6112435

Firebase App Distribution was investigated only as a same-day fallback. Existing
Firebase project/app authentication works, but App Distribution activation or
permissions are unverified. No Firebase release, invite or new storage bucket was
created. The prepared APK is not represented as a Play Store beta release.

## Beta access and known limits

Read-only live Supabase checks at 08:43–08:44 BST confirmed beta remains open,
subscription enforcement is off and both store sales switches are off. The
enabled verified-account trigger grants lifetime beta access to ordinary new
verified Workloop accounts on either platform. Colleagues must create and verify
their Workloop account; joining a Play tester list or installing alone does not
create an entitlement. No payment details or purchase are required.

Email/password, email links and browser-based Google are the intended Android
sign-in paths. Android Apple and phone/SMS login, Google store purchases and Tap
to Pay remain disabled. Remote Android push remains pending, respecting the
owner's decision to keep Google's service-account-key policy. Local reminders
are separate and use inexact scheduling.

First physical tester check: verify account, sign in, add one client, create a
booking, record a payment and reopen each record; then check email/Google return,
keyboard/Back behavior and local reminders. No real card charge is required.

Suggested documentation commit: `docs: record Android build 14 beta candidate and Play registration gates`.

## Play registration progress — 7 September 2026 morning

The owner explicitly approved the US$25 registration fee and selected
`support@workloop.uk` for both the permanent Google login and contact email, with
07587043727 for the required public developer/contact phone. The earlier
account-owner-choice and fee-authorisation gates are resolved; payment has not
yet occurred.

Google's live D-U-N-S lookup independently returned **HAANI ENTERPRISE LIMITED,
35 Well Lane, BATLEY WF17 5HQ, United Kingdom**, matching number 232224218. The
payments-profile flow under the former Gmail session was cancelled before
profile creation when the owner selected the support login. No Play account was
created under the personal Gmail address.

Google reported that support@workloop.uk did not yet have a Google account. The
free existing-email signup route is now at **Verify your email address**, after
using the owner's confirmed account-holder details. The owner has been asked for
the code sent to the support inbox. UK2 is signed out and the old Stackmail
session reports an IMAP connection failure; no password or mailbox setting was
changed. No paid Google Workspace subscription, DNS change, duplicate D-U-N-S
request, Play release or tester invitation has been made.

Next: complete the support Google login, resume Haani organisation registration,
review the remaining details/terms, pay the approved fee, complete Google's
required verification and publish the prepared bundle to an internal test once
the account allows it. Distribution and same-day availability remain unconfirmed.

### Email verification completed

The owner-supplied Google email verification code was accepted. Signup is now at
**Create a strong password**. No password has been generated, entered or saved;
the computer-use credential handoff rule requires the owner to complete the
password entry, confirmation and submission. The signup tab is retained for
that step. Google account creation, terms acceptance, the registration payment
and Play distribution are still pending.

### Registration resumed with the existing Gmail login

After the remote signup link expired and the phone showed a paid Workspace
offer, the owner chose to use `ismaeelsmiley1@gmail.com` for Play Console access.
`support@workloop.uk` remains the intended public developer/app-support and
Google-contact email. No Workspace plan was purchased. The support Google
signup was not completed by this agent.

The organisation flow was resumed under the existing Gmail session, with the
public developer name **Workloop**. Google matched D-U-N-S 232224218 to Haani
Enterprise Limited at its current registered address. After confirmation,
Google explicitly reported **Your payments profile was created and added to
your account**. This is a payments identity profile, not evidence that the Play
registration fee has been paid or that organisation verification is complete.

The organisation page was saved with size 1–10, https://workloop.uk and the
owner-authorised +447587043727 number. The public-profile form has
`support@workloop.uk` and that same authorised public number entered. Google has
sent a new six-digit verification code to the support address; entry is pending.
The public-profile acknowledgement is not checked. Later registration pages,
terms, payment, document verification and internal release remain unfinished.

### Public email verified; final registration terms reached

The replacement owner-supplied email code was accepted. Google now shows
**Email address verified** for support@workloop.uk and reused that verification
for the private Google-contact address. The public-profile acknowledgement was
checked for the already authorised company details and phone number.

Saved background: first Play developer account, Workloop developed with Flutter,
iOS TestFlight beta and Android emulator validation; no other Play Console
accounts, consistent with the owner's earlier answers. Saved app plans: one app
in the next 12 months, revenue through subscriptions. The broad registration
survey category **Any other financial products or services not listed above**
was selected because Workloop manages business money and offers merchant card
collection. This is an interpretation of Google's broad policy and is distinct
from the eventual store category and detailed Financial features declaration.
See the frozen release's PLAY-DECLARATIONS-ADDENDUM.md for rationale and limits.

Saved private contact: Muhammad Ismaeel, support@workloop.uk,
+447587043727, English (United Kingdom). The form has reached **Terms**. Both
mandatory agreement checkboxes and optional feedback/marketing checkboxes remain
unchecked. The computer-use rule requires confirmation at the point of accepting
binding agreements; the owner is being asked to approve the Developer
Distribution Agreement and Play Console Terms of Service on Haani's behalf.
The existing US$25 payment approval remains in force. No registration charge,
completed developer account, document verification or Play release is claimed.

### Agreements authorised; card setup required

The owner explicitly approved accepting both Google agreements on Haani's
behalf. Both required checkboxes were checked and **Create account and pay**
was clicked. Google's checkout displays **Developer Registration Fee US$25.00**
and requires a new credit/debit card; no charge or completed registration is
confirmed. Optional marketing/feedback remained unchecked.

A separate read-only check of the generic Play Console URL starts a fresh
registration form, so the in-progress checkout link is not being offered as a
reliable phone handoff. Instead, Google Payments was opened under the authorised
Gmail login and the **HAANI ENTERPRISE LIMITED** profile selected. The company
profile has no payment methods and no activity. Its stable card-management page
is https://payments.google.com/gp/w/home/paymentmethods. The owner is being asked
to add the intended card directly to that company profile from their phone,
using the card's actual billing details, then notify the agent. No card details
have been requested in chat, entered, saved or charged by the agent.

The registration checkout and company Payments tab are retained. After the
owner adds a card, recheck the exact US$25 checkout and finish the already
authorised payment, then verify actual account/identity/release status.

### Registration paid; organisation verification in progress

The owner added a card to the Haani company Google Payments profile and
confirmed completion. The saved company payment method was verified in the
registration checkout. A single **Buy** action completed the already authorised
**US$25 Developer Registration Fee**. Google displayed **Developer account
created** and stated that the receipt was sent to ismaeelsmiley1@gmail.com.

The new **Workloop organisation account** is **5962688167835351396**, under
Haani Enterprise Limited. This is confirmed account creation and payment, not
completed developer verification or an uploaded Android beta.

Google requires organisation and representative identity verification, website
ownership verification, and then public/private phone verification. **Create
app is disabled until account verifications complete.**

Both original Companies House certificates were visually checked. The upload
control accepts one file; the original, unmodified **2025-03-31-change-of-name.pdf**
(Certificate of Incorporation on Change of Name, company 15758586, current name
HAANI ENTERPRISE LIMITED) was uploaded. The organisation details matched the
existing DUNS payments profile. Google now labels the **Organisation** step
**Submitted**; approval has not been confirmed. The earlier incorporation PDF,
under STORY PLUS MARKETING LTD, remains available if Google requests further
evidence. No document was altered or combined.

The authorised representative step requires photo ID. Its consent screen
explains ID/personal-information processing and offers **Agree** or **Decline**.
Neither was clicked; no representative ID has been provided or submitted.
The owner must complete this personal verification directly in Google on their
phone, using the existing Gmail account and this account's home page:
https://play.google.com/console/u/0/developers/5962688167835351396/app-list.

Website verification for **https://workloop.uk** completed successfully via
**Send verification request** in Account details. Google immediately displayed
**Website verified** and a notification confirming Search Console ownership.
No DNS, website code or deployment changes were needed.

The phone verification page confirms that both public and Google-contact
numbers must be verified after organisation/identity documents are approved.
That step remains disabled. Android build 14 remains prepared locally; no
Play app, internal-testing release or tester installation is claimed yet.

### Owner identity submitted; Google review pending

After the owner confirmed completing personal verification on their phone,
the Play Console home page was refreshed. It now explicitly states **Google
is verifying your identity** and **Documents were uploaded**. Google says the
account owner will receive an email when review completes and that this may
take a few days. This confirms submission, not approval.

Phone verification remains gated by approval, and **Create app** remains
disabled. No duplicate identity submission was started. The next sequence is
Google approval, verify public/private contact phone numbers, then create the
Workloop app and upload the prepared build 14 to internal testing. No beta
availability or same-day distribution is claimed.

### Identity and phone verification completed; app created

On 7 September 2026 the live Console notification confirmed identity verification
successful. Both Contact phone number and Developer phone number showed **Phone
number verified**. Saved changes; Console confirmed **Your changes have been
saved**, and account-level verification gates disappeared.

Created **Workloop: Solo Business OS**, package `com.ismaeel.workloop`, app ID
`4972602374192401232`, English (United Kingdom), App, free download. This is
internal beta setup; it does not activate subscription billing or public release.
Required app-creation declarations were accepted within the authorised Play setup;
Play app signing and default automatic protection were enabled.

The frozen build 14 AAB SHA-256 was rechecked against the release evidence and
matches `c3457334dabbd7184eafa4a953a97df5ee3e9ec002667c87998b3ca95467aedd`.
An internal release upload has begun with the prepared factual beta release notes.
Upload, release availability and tester access remain separate checks below.

### Build 14 published to Google Play internal testing

Console accepted the uploaded AAB as **14 (1.0.0)**, minimum API 26, target SDK
36, with ReTrace mapping and native debug symbols attached. The only release
warning was that no testers were selected; there were no blocking bundle errors.
Published the internal release, and Console now shows **Available to internal
testers**, released 7 September at 18:27 (Console display time), **Not reviewed**.
Release detail:
https://play.google.com/console/u/0/developers/5962688167835351396/app/4972602374192401232/tracks/4701478391135695716/releases/1/details

Created and selected **Workloop internal beta**, initially containing only the
owner's authorised Google account, and saved the track. Track summary now shows
**Active**. Colleagues' Google-account addresses have been requested and are not
yet supplied or added.

Official invitation:
https://play.google.com/apps/internaltest/4701478391135695716

Opened that invitation in the signed-in owner session: Google displays **You're
invited to test com.ismaeel.workloop (unreviewed)** and an **Accept invite** button.
The invitation was not accepted on the owner's behalf. This verifies access to
the invitation, not installation on a physical Android phone. Google uses the
temporary package-name label until full app setup/review is complete. Public
production release remains separate and incomplete. No paid plans were enabled,
no new registration charge made, and no Android push security exception applied.

This Play build is the frozen build 14; newer local client-file/vCard import
changes from the website/integrations task are not part of it.
