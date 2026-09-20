# Workloop Store Submission Draft

> **Current pack — 9 September 2026:** use the
> [build 19 metadata pack](#current-metadata-pack--9-september-2026-build-19) below.
> It supersedes all earlier current-pack pointers and free-app/payments-off copy.
> See [the build 19 release record](releases/2026-09-09-build19-testflight.md)
> for artifact evidence; store upload and tester availability are separate claims.

> **Current pack — 6 September 2026:** use
> [the iPhone App Store submission pack](releases/2026-09-06-ios-store-submission.md).
> It supersedes the historical copy below for the iPhone-only, Quiet + Warm,
> free-app launch with hosted payment links, manual WhatsApp and no Tap to Pay
> or SMS. It records the current empty public-submission fields, proposed
> operator/legal identity gate, privacy worksheet and screenshot requirements.
> The older payments-off/neon drafts and beta handoffs remain here as history.

Last updated: 2026-09-05

This copy is a launch draft, not a substitute for App Store Connect, Play
Console, privacy, or trade-mark review.

## Listing identity

- Product name: `Workloop`
- Recommended store title: `Workloop: Solo Business OS`
- iOS subtitle: `Run your service business`
- Android short description:
  `Clients, bookings, money and follow-ups in one calm daily business loop.`
- Primary category: Productivity
- Secondary iOS category: Business
- Support email: `support@workloop.uk`
- Privacy URL: `https://workloop.uk/privacy.html`
- Terms URL: `https://workloop.uk/terms.html`
- Account deletion URL: `https://workloop.uk/delete-account.html`
- Launch device scope: iPhone portrait on iOS; portrait orientation on Android.
  iPad and landscape layouts are not part of the 1.0 store promise.

Reserve the final title before producing screenshots. Similar Workloop names
already exist in both stores.

## Promotional text

Know what is happening, what needs attention, and what to do next. Workloop
connects the daily operation of a solo service business without the clutter of
generic business software.

## Full description

Workloop is the calm business operating system for solo service professionals.
It brings clients, bookings, money, tasks, and notes into one connected daily
workflow, so the next useful action is always clear.

START WITH TODAY

- See today’s bookings and business priorities.
- Surface overdue follow-ups and unpaid work.
- Move directly from attention to action.

KEEP CLIENT CONTEXT TOGETHER

- Store contact details, relationship notes, tags, and client history.
- See linked bookings, tasks, notes, and payments in context.
- Import only the contacts you choose.

RUN BOOKINGS WITH CONFIDENCE

- Create and manage focused one-off bookings. Existing historic recurring
  records remain readable, but new recurring-series creation is outside V1.
- Track status, service, location, price, and client details.
- Export your schedule as a standard calendar file.

UNDERSTAND THE MONEY

- Record income, outstanding amounts, and expenses.
- Review useful week, month, and custom-period summaries.
- Keep operational money context linked to clients and bookings.

FOLLOW THROUGH

- Create tasks, on-device reminders, checklists, and reusable templates.
- Keep business notes and client context close to the work.
- Use focused notifications without turning Workloop into another noisy feed.

BUILT FOR TRUST

- Exact icon-neon accents across Light and OLED dark appearances.
- Workspace export and a protected sole-owner account-deletion workflow.
- Optional contact, calendar, and file imports stay under your control.

Workloop organises business records; it is not a bank, accountant, or
replacement for professional advice.

The default beta build sets `PAYMENT_COLLECTION_ENABLED=false`. Do not add a
Stripe collection claim, payment screenshot, or payment reviewer instruction
unless the submitted build explicitly enables that capability and every
payment release gate has passed.

## Suggested iOS keywords

`business,booking,client,solo,service,task,invoice,expense,calendar,organiser`

Recheck the 100-character App Store limit when entered in App Store Connect.

## Screenshot story

Use real in-app screens with fictional data. Do not composite features that the
release does not contain.

1. **Know what needs attention** — Today with the schedule and next action.
2. **Every client in context** — client overview with linked history.
3. **Bookings without the admin** — booking list and focused detail.
4. **See what you earned** — Money summary with received and outstanding.
5. **Follow through calmly** — tasks/checklist/reminder view.
6. **Your business, one loop** — Business showing the booking page, services,
   working hours, business profile, and Settings; Work keeps Schedule, Tasks,
   and Notes together.

Use the exact icon neon `#C1FF72`, restrained dark or neutral backgrounds, large
legible copy, and no more than one claim per frame.

## Permissions and reviewer explanation

| Permission | User-triggered purpose | If denied |
| --- | --- | --- |
| Contacts | Review and import selected contacts as clients | Manual client entry remains available |
| Calendar | Review and import selected events as bookings. Android's calendar provider grants the package's required read/write permission pair, but Workloop's launch flow does not modify device events. | Manual booking entry and `.ics` export remain available |
| Files | Select supported exports for reviewed import or save an export | Clipboard/manual entry remains available where offered |
| Notifications | Deliver opted-in business attention and schedule on-device task and booking reminders | Workloop remains usable; activity stays visible in-app |
| Location | Optional current-location weather after the owner chooses Use my location; eligible Stripe collection also uses location in payment-enabled builds | Choose a UK area manually for weather, leave weather off, or keep manual payment records |
| Bluetooth / NFC | Connect to an eligible Stripe reader or Tap to Pay flow only in a payment-enabled build on supported hardware | Manual payment records remain available |
| Internet | Secure authentication, workspace sync, public booking, address lookup and optional local forecasts | Clear retry/error states are shown |

Reviewer notes should explicitly say:

- Contacts and calendar are optional and never imported automatically.
- The Android calendar plugin requires the platform read/write permission pair;
  Workloop V1 only reads events the user reviews for import and does not modify
  the device calendar.
- Google Places is optional; addresses can be entered manually.
- Local weather starts off. Tap the weather beside the Today greeting, then
  choose Use my location to request foreground location. Approximate permission
  works; weather requests no background location. A UK area can instead be
  selected with existing Places search, or weather can stay off. A failed
  forecast must not block bookings or show invented conditions.
- The iOS file-picker dependency links camera/photo chooser support, which is
  why the binary includes purpose strings. Workloop V1 exposes only reviewed
  CSV, text and Markdown imports plus ICS/JSON export; it does not expose a
  camera or photo-library import workflow.
- “Money” records operational income/expense information and does not connect
  to a bank feed. In the default beta, Stripe collection entry points are off.
  In a separately approved payment-enabled build, Stripe processes collection
  for an eligible connected business and Workloop does not store full card
  numbers.
- Calendar export is point-in-time `.ics`, not live two-way sync.
- Remote notifications are operational business attention requested through
  the user's Workloop preferences; they are not advertising or marketing.
  Task and booking reminders remain scheduled on-device.
- Public booking is a request that the owner reviews and confirms; V1 does not
  advertise live slot selection or automatic confirmation. Payment collection
  must be described only if the submitted build and connected-account operation
  have completed their payment release gates.
- The iOS review build is iPhone-only and both platform builds are
  portrait-oriented; do not supply landscape or iPad marketing media.

## Apple privacy declaration working map

Review the final App Store Connect definitions before submission.

| Data type | Collected | Linked to user | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| Name and email | Yes | Yes | No | Account, public booking requests and confirmations, app functionality, and optional Stripe receipt delivery when payment collection is enabled |
| Phone/address | Optional | Yes | No | Business/client workflow |
| Contacts | Optional | Yes | No | User-selected client import |
| User content | Yes | Yes | No | Notes, tasks, bookings, support, business records |
| Other financial info | Optional | Yes | No | User-entered income/expense tracking and payment status/provider references |
| User ID | Yes | Yes | No | Authentication and security |
| Calendar events | Optional | Yes | No | User-selected booking import |
| Coarse location (weather) | Optional | Yes during the authenticated request | No | Local current-hour forecast; device or manually selected coordinates are reduced to two decimal places before leaving the device |
| Diagnostics | Support-only, user initiated | Potentially | No | Troubleshooting |

The current source has no advertising SDK and no cross-app tracking SDK.
Supabase, Stripe, Resend, Google OAuth, Google Places and MET Norway are service providers;
their actual processing must be reflected in the public privacy policy and
store answers.

## Google Play Data safety working map

- Data is encrypted in transit.
- Account deletion can be requested in-app and through the public deletion URL.
- Data collected for account/app functionality may include personal info,
  contacts, calendar events, files selected for import, user-generated content,
  and user-entered financial records. A payment-enabled build may additionally
  process connected-account identity, provider transaction/refund/dispute
  references, a public booking requester's email used for confirmation through
  Resend, and a customer email supplied for receipt delivery through Stripe.
- Contacts, calendar, files, and notifications are optional.
- Weather location is optional and used only for app functionality. The
  Workloop proxy receives reduced-precision coordinates through an authenticated
  request, then calls MET Norway without forwarding the owner's identity or
  device IP. Manual UK area lookup sends the typed query to Google Places.
  Weather is not used for advertising or cross-app tracking.
- Do not assume Apple's Coarse Location classification maps directly to Play.
  Apple defines precision using decimal places; Google defines Approximate
  Location as an area of at least 3 km². Weather's two-decimal coordinate grid
  can resolve a smaller area when the OS supplies a precise fix. Conservatively
  include **Precise location** for Android weather as well as Approximate
  Location where applicable, and separately audit Stripe's location processing
  in the submitted payment-enabled build. The manifest already retains Stripe's
  fine-location permission; weather accepts approximate permission.
- Do not automatically claim purely ephemeral processing. Weather forecast
  responses have a reusable warm-server cache, and MET Norway's request logs
  can contain the reduced-precision coordinates. Confirm actual final provider
  handling before selecting the ephemeral-only or not-shared options.
- No data is sold and the current source has no advertising SDK.
- Confirm Play’s current distinction between service-provider processing and
  “sharing” before answering the form.

Source definitions checked 5 September 2026:
[Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/),
[Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469),
[MET Norway privacy policy](https://www.met.no/en/About-us/privacy).

## Accessibility evidence to capture

Do not claim a store accessibility feature until the release candidate is
manually exercised:

- VoiceOver and TalkBack announce navigation destinations and icon actions.
- Dynamic text does not clip primary workflows at large system sizes.
- Reduced-motion settings suppress non-essential UI motion.
- Contrast remains readable in light and OLED dark appearances.
- Every workflow is usable without relying on colour alone.

## TestFlight beta 4 handoff draft

Build name: `Workloop 1.0.0 (4) - Payments-off beta`

### Plain-English release notes

This beta strengthens Workloop's connected Today -> Client -> Work -> Money ->
Repeat workflow. It includes the five-part Today, Clients, Work, Money and
Business workspace, improved booking-request and calendar recovery, clearer
first-run account and legal access, responsive Light/Dark layouts, and safer
workspace export and account-deletion boundaries.

Card collection, Tap to Pay and payment links are intentionally unavailable.
Money records remain manual, and customer booking submissions are requests that
the business owner reviews rather than automatic confirmations.

### What to Test

- Create an account, confirm the email, sign in and complete business setup.
- Add and edit a client; create, edit, complete and cancel one-off bookings.
- Use Work > Schedule, Tasks and Notes and confirm each retained view keeps its
  place and context.
- Record received, outstanding and expense entries manually; verify Today,
  Money and client history stay aligned.
- Configure and share the booking page; submit a signed-out request and approve
  or decline it as the owner.
- Exercise reminder settings, calendar import/export, support, Terms, Privacy,
  workspace export, sign-out and password recovery.
- Confirm no Stripe setup, Tap to Pay, card collection or payment-link entry
  point is visible.

Report the screen, action, expected result, actual result, screenshot, device,
OS version and Workloop build number to `support@workloop.uk`.

## TestFlight beta 5 handoff draft

Build name: `Workloop 1.0.0 (5) - Booking confirmations`

### Plain-English release notes

This build adds customer email to public booking requests. A request is still
not a booking: after the business accepts and schedules it, Workloop sends the
customer a confirmation with the agreed service, date/time and location. Email
delivery is queued safely if the provider is temporarily unavailable.

### Additional What to Test

- Submit a signed-out booking request with a real controlled email address and
  confirm the receipt says nothing is booked yet.
- As the owner, verify the same email is shown, choose the agreed date/time and
  create the booking.
- Confirm the customer receives exactly one accurate email and the new client
  record retains the address.
- Retry a submission or confirmation after a connection interruption and
  report any duplicate request, booking or email.

Card collection, payment links and Tap to Pay remain disabled for this beta.
Do not distribute Build 5 until the backend migration, three booking functions,
Resend secrets and scheduled retry worker have passed the controlled-inbox
staging gate.

## TestFlight beta 6 handoff draft

Build name: `Workloop 1.0.0 (6) - Business alerts`

### Plain-English release notes

This build adds optional push notifications for important Workloop activity,
including booking requests, booking/payment updates, overdue-payment attention
and the morning brief. Alert previews keep customer and payment detail private;
tapping opens the relevant Workloop screen. Existing task and booking reminder
choices continue to run on the device.

### Additional What to Test

- Update from Build 5 through TestFlight; confirm the same account, workspace
  and business data remain available without reinstalling.
- Turn notifications on, close Workloop, and confirm a controlled booking
  request or payment update arrives once with privacy-safe preview text.
- Tap the alert and confirm it opens the correct signed-in Workloop screen.
- Repeat once while Workloop is open and confirm the in-app notification centre
  refreshes without a duplicate foreground banner.
- Sign out, use another test account on the same phone, and confirm no alert
  from the previous account appears.

Card collection, payment links and Tap to Pay remain disabled for this beta.
Use the existing TestFlight groups and public link after the processed Build 6
has passed the internal physical-iPhone push smoke.

### 2026-08-31 live TestFlight handoff

- Build 6 is uploaded, processed and marked `Testing` in both `Workloop
  Internal Beta` and `Workloop Private Beta`.
- The saved What to Test copy covers the Build 5 update path, privacy-safe
  background alerts, alert routing, foreground duplicate suppression and
  two-account token isolation.
- The private group retains all 9 testers. Automatic tester notification is
  enabled, so existing testers can install Build 6 as an in-place TestFlight
  update; no new invitation or reinstall is required.
- The controlled public link remains
  `https://testflight.apple.com/join/1ycJPHWx`.
- A physical iPhone registered a live token and visibly received a controlled
  sandbox alert. Tap routing, quiet-hour behaviour, foreground suppression and
  two-account reassignment remain tester checks rather than completed claims.
- A separate Build 7 upload is `Ready to Submit` but is not attached to the
  external group. Build 6 remains the selected beta.

### Known beta limitations

- One-off booking creation only; historic recurring records remain readable.
- Public booking is a request, not live availability or automatic confirmation.
- Calendar export is point-in-time ICS, not live two-way sync.
- Task and booking reminders are on-device. Business-activity remote push is a
  Build 6 beta capability and remains optional.
- Card collection, payment links and Tap to Pay are disabled.
- No bank feed, accounting replacement, staff/team operation or AI workflow.
- iPhone portrait is the TestFlight layout promise; iPad and landscape are not.

### App Store Connect completion checklist

- App Privacy: use the data map above and recheck Apple's current definitions.
- Export compliance: `ITSAppUsesNonExemptEncryption=false`; answer that the app
  does not use non-exempt encryption.
- Reviewer contact: the owner must enter a monitored name, phone and
  `support@workloop.uk`; do not invent those details in source.
- Review access: provide a dedicated fictional-data account only after its Auth
  confirmation/recovery journey passes and it is intentionally created for
  Apple.
- Internal testers: prepare the existing internal group, but do not attach the
  build or add testers until upload approval and processing succeed.
- External testers: defer until internal smoke, support monitoring, legal
  controller details and external-beta review information are complete.

### 2026-08-15 live TestFlight handoff

- Build 5 is uploaded, processed, attached to `Workloop Private Beta`, and
  marked `Waiting for Review` after successful Beta App Review submission.
- What to Test, beta description, feedback email, marketing/privacy URLs and
  honest payments-off/request-only review notes are entered.
- `Workloop Private Beta` exists as the external group and contains Build 5.
- A confirmed dedicated reviewer account is entered with credentials retained
  only in App Store Connect and the owner's local Keychain. Production Auth now
  redirects web confirmations to `workloop.uk`; the retired `workloop.app`
  allow-list entry has been removed.
- The owner's monitored reviewer contact is saved with the dedicated reviewer
  login, and Apple has accepted the build for Beta App Review.
- The controlled 50-tester public link is
  `https://testflight.apple.com/join/1ycJPHWx`. Share it with the intended
  tester cohort after Apple approves the build; Apple keeps it closed until
  then.


## Subscription launch revision — 7 September 2026

The earlier free-app submission draft is superseded by the requested subscription model: exact30-day server trial with no payment details, then native-store £14.99/month or £149.99/year; existing verified beta accounts retain lifetime access. The app remains free to download. Do not submit the older review notes claiming no paid Workloop plan. Use the current trial/lifetime flow, product IDs `workloop_monthly` and `workloop_yearly`, and the matching subscription/privacy/terms screens when completing review metadata. Products, receipt verification, notification lifecycle and first-subscription review must be completed before billing enforcement/public release. Current sales flags are off.

App Privacy must include purchase history linked to the account for app functionality: store/platform, product, transaction IDs, expiry/refund status and app-account association. Card numbers remain with Apple/Google; Workloop does not receive store card details. Do not change the store questionnaire or certify its answers until the complete final data inventory is reviewed. No public-submission action occurred in this pass.


## Current metadata pack — 9 September 2026, build 19

This is the current copy for the reviewed build 19 release. It supersedes the
earlier free-app, payments-off, one-off-booking-only and no-camera/OCR descriptions
above. Historical sections remain unchanged. The owner has authorised release
to the existing private beta testers; this note does not claim Apple processing,
review approval, tester assignment or public release.

The same exact five copy fields are prepared in
`/private/tmp/workloop-build19-store-copy.json` for App Store Connect entry.
Character counts: description 3112; promotional text
147 (limit 170); beta description 1076;
What to Test 1891; review notes 2636.

### Current factual limits and access

- Build 19's frozen production defines enable payment collection, subscriptions
  and crash reporting; Tap to Pay is disabled. Stripe payment links require an
  eligible verified connected business; no payment demonstration or live charge
  is implied by this copy.
- Live subscription configuration checked on 9 September: beta access open,
  enforcement disabled, Apple and Google purchases unavailable. Planned UK
  terms remain 30 days without payment details, then £14.99 monthly or £149.99
  yearly. The server trial is separate from store purchase; it does not
  automatically convert into a charge. Existing eligible beta accounts retain
  lifetime access. The copy does not promise purchasable plans in this beta.
- Repeat bookings are finite, 2–24 visits at one- to four-week intervals.
  Changes affect one occurrence. Quotes are accepted manually; deposits stay
  on the same invoice balance. No recurring billing or profit-per-job claim.
- Receipt text is read locally and requires review. Raw recognised text is not
  stored or sent to an OCR service; selected details become expense data and
  saved originals use private workspace storage. Supported attachments are
  PDF/JPEG/PNG up to 10 MiB; recognition reads at most five PDF pages and reports
  partial results. Manual entry remains available. Camera/photo access is
  optional and requested after deliberate capture selection.
- The 2026/27 tax estimate supports the stated eligible non-VAT sole-trader,
  England/Wales/Northern Ireland, cash-basis scope. In-app eligibility excludes
  other taxable income and unsupported reliefs/circumstances. It does not file
  with HMRC, cover Scotland/company tax, or establish that a receipt is allowable.
- The supplied dedicated reviewer identity was checked without signing in or
  retrieving credentials: one confirmed, unbanned user; no pending deletion;
  zero workspace memberships; no existing access record or lifetime entitlement.
  The live read-only access helper returns `state=beta`, `has_access=true`
  under the current beta configuration. This is metadata evidence, not a
  verified password login or completed onboarding. Review notes must not claim
  a populated demo workspace or verified end-to-end reviewer access.
- Public App Privacy answers still need to reflect the current financial records,
  saved receipt originals, purchase history and crash diagnostics. This copy
  update does not certify or change the store privacy questionnaire.

Sources: [build 19 artifact and defines](releases/2026-09-09-build19-testflight.md),
[build 18 workflow/native evidence](releases/2026-09-08-build18-refinement.md),
[documents/deposits review](releases/2026-09-08-business-workflow-review.md),
[receipt and tax scope](releases/2026-09-08-expense-records-tax.md),
`lib/features/subscription/subscription_access.dart`,
`lib/features/subscription/subscription_screen.dart`,
`lib/core/workloop_capabilities.dart` and the live subscription configuration.

### App Store description

```text
Workloop is a calm business operating system for people who work for themselves, by themselves. Keep clients, bookings, work and money connected, so you can see what is happening, what needs attention and what to do next.

Start the day with Today
See upcoming bookings, tasks and useful follow-ups in one place. Move from the next action to the client or job behind it.

Keep the client context
Find contact details, bookings, tasks, notes, quotes, invoices and payment history without searching across separate apps.

Plan one-off and repeat work
Create individual bookings or a series of 2–24 visits, repeating every one to four weeks. Move or cancel one visit when plans change. Keep tasks and notes beside the schedule, and share a booking page where customers can send requests for you to review.

From the quote to the payment
Create itemised quotes and invoices using client and service details. Record a quote’s acceptance and turn it into an invoice draft. Request a fixed or percentage deposit, then track actual payments and the remaining balance on the same invoice. Preview PDFs in Workloop before sharing them.

Know where your money stands
See payments needing attention first, followed by money received, recorded spending, net profit and recent activity. Search income and expenses, review amounts still owed and follow your monthly target. Eligible businesses can use Stripe payment links with a verified connected account; Stripe requirements and processing fees apply.

Keep the supporting records
Attach receipt photos or PDFs to expenses. Workloop reads them on your device and asks you to review suggested details before applying them. Keep manual control of categories, open the original receipt in the app, and record business mileage with journey details and CSV export.

Plan for tax within a clear scope
Review annual figures to estimate 2026/27 Income Tax, Class 4 National Insurance and money still to set aside. This planning tool is for eligible non-VAT-registered sole traders in England, Wales or Northern Ireland, with one cash-basis business, a 5 April year end and no other taxable income. Further eligibility conditions apply. It does not cover Scotland, companies or unsupported reliefs, and it does not file a return with HMRC. Recorded net profit and receipt suggestions are not a calculation of allowable taxable profit.

Keep control
Choose what to import, preview documents before sharing, and export your workspace when needed. Workloop does not provide a bank feed or live two-way calendar sync.

Plans and access
The app is free to download. Planned UK public launch terms are 30 days free without payment details, then £14.99 per month or £149.99 per year. The trial does not charge automatically. Paid plans are being prepared; purchase availability and the confirmed price are shown in the app. Existing eligible beta accounts keep free lifetime access. When purchased, subscriptions renew automatically until cancelled through your Apple subscription settings.

Privacy: https://workloop.uk/privacy
Terms: https://workloop.uk/terms
Support: support@workloop.uk
```

### App Store promotional text

```text
Quotes, invoices, deposits and repeat bookings, with reviewed receipt details, mileage and a clearer Money view. Keep your solo business connected.
```

### TestFlight beta app description

```text
Workloop connects clients, bookings, work and money for people who work for themselves, by themselves.

This private beta adds quotes and invoices with deposits, finite repeat bookings, receipt photos/PDFs with reviewed on-device reading, business mileage and a scoped 2026/27 sole-trader tax estimate. Documents open inside the app. Money puts payment attention, received/spent figures and recent activity before planning and setup.

Tax planning supports eligible non-VAT sole traders in England, Wales or Northern Ireland with one cash-basis business and no other taxable income; further conditions apply. It does not support Scotland, companies or HMRC filing.

Existing eligible beta accounts retain free lifetime access. Planned public launch terms are a 30-day trial without payment details, then £14.99/month or £149.99/year; paid plans are not yet available. Card payment links require an eligible, verified Stripe account. Tap to Pay is unavailable.

Please use TestFlight feedback or support@workloop.uk. Leave private client details out of screenshots and reports.
```

### TestFlight What to Test — build 19

```text
Build 19 brings the reviewed business tools and Money improvements to the private beta.

1. Update using your existing Workloop account. Check that your clients, bookings, money records and beta access remain available.

2. In Money > Invoices, create a clearly labelled test quote or draft invoice. Reuse a client/service, review business details, prices and any VAT, and try a fixed or percentage deposit. Check that a deposit request is separate from money received. Do not make live card charges just to test.

3. Open an invoice or quote PDF in Workloop. Try scrolling and zooming, then open and cancel the share sheet. Check that cancelling leaves the document unchanged.

4. Create a short repeat-booking series. Check the dates and local times, then move or cancel one visit. The other visits should stay unchanged.

5. Add an expense receipt using a sample photo or PDF. Review the suggested amount, date and notes; try correcting a suggestion or keeping your existing entry. Check camera/photo permission denial, picker cancellation and manual entry. Reopen the saved receipt.

6. Log a business journey and review its date, vehicle, purpose and distance. Try mileage export. Mileage should not appear as a second cash expense.

7. If eligible, open Tax planning, read its scope and review the annual figures. Check the estimate and in-app report. Changing inputs should require an updated result. Do not use this beta estimate as an HMRC bill or filing.

8. Check Money with empty records, normal activity and larger text. Outstanding payments, received/spent amounts and recent activity should be clear. Tell us about clipped fields, confusing actions, failed retries or lost changes.

Use fictional details for test records and remove them when finished. Send the steps, device model, app version and a privacy-safe screenshot through TestFlight feedback or support@workloop.uk.
```

### App Review notes — build 19

```text
Build 19 is an iPhone portrait private-beta update. Sign in with the dedicated credentials supplied separately in App Review Information. If first-run setup appears, follow the onboarding steps using fictional business and client details. No populated demo workspace is promised.

Navigation: Today, Clients, Work, Money and Business. Work contains Schedule, Tasks and Notes. Money contains Overview, Invoices (including quotes), Spent and Owed. Invoice setup is available when creating documents; review required business details before issuing.

This build enables Stripe payment collection and hosted payment links for eligible businesses with a verified connected Stripe account. It does not enable Tap to Pay. Invoice creation, deposits and manual payment records can be reviewed without connecting Stripe. Do not make a live card payment solely for this review. Requesting a deposit does not record income; only actual received payments reduce the balance.

Receipt capture offers camera, selected photos and Files. These optional permissions are requested only after the user chooses the corresponding action; manual entry remains available. Receipt text is read on the device, with suggestions reviewed before application. Raw recognised text is not stored or sent to an OCR service. A saved receipt attachment uses private workspace storage. PDFs/images can be viewed in the app; sharing opens the system share sheet and does not automatically contact a customer.

Recurring bookings are finite: 2–24 visits at one- to four-week intervals. An individual occurrence can be changed or cancelled. There is no recurring billing or edit-all-series promise.

Tax is a 2026/27 planning estimate for eligible non-VAT-registered sole traders in England, Wales or Northern Ireland with one cash-basis business, a 5 April year end and no other taxable income. The app presents further exclusions and requires review. Scotland, companies, unsupported income/reliefs and HMRC filing are not supported.

Subscription access is enabled in the app. The current backend keeps beta access open, billing enforcement off and Apple purchases unavailable. Existing eligible beta accounts retain lifetime access. Planned public terms are a 30-day trial without payment details, followed by £14.99/month or £149.99/year. This beta does not require a purchase; it is not a subscription-purchase review.

Contacts/calendar import and notifications are optional. Calendar export is a snapshot, not live two-way sync. Customer booking requests require owner confirmation. Privacy, export, account deletion and support are available from Business settings.
```


### Reviewer access and billing test boundary

Source inspection shows that an account without a workspace enters onboarding
before `SubscriptionGate` is constructed (`lib/main.dart`). Once a workspace
exists, `get_workloop_access` requires a verified active session, creates the
account-access record if needed, and returns the current beta entitlement.
The dedicated review address is intentionally excluded from automatic lifetime
grants; that exclusion does not block its current `beta` access. A password
login and completed onboarding have not been exercised in this metadata pass.

No entitlement or credential change is necessary for the current open beta.
The minimum reviewer preparation is to use the existing supplied credentials
and finish the normal onboarding with fictional business details. Do not reset
the password or modify any customer workspace. A future explicit lifetime grant
would affect only this identity's access row, but would make it unsuitable for
trial/billing QA; it is not needed or performed for this release.

No dedicated persistent reviewer-preparation script was found under `scripts/`.
The existing `/private/tmp/workloop_review_qa.py` is a disposable integration
harness that creates and deletes QA accounts and financial records. It is not
a safe shortcut for populating the persistent Apple reviewer identity.

Apple's [TestFlight purchase environment](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)
uses sandbox In-App Purchases. In this app, however, the current `beta` state
does not present purchase choices, Apple sales are disabled, and the separate
30-day server trial has not begun for this reviewer. The verification source
recognises signed Sandbox transactions and shows a test-purchase message, while
the paid-access query deliberately considers Production subscriptions only.
Neither this metadata pack nor this beta release claims a verified sandbox
purchase-to-paid-access flow. Subscription purchase review needs a separately
prepared billing test account and a defined, tested sandbox-access policy; do
not enable global sales or enforcement merely to unlock the current reviewer.


## 12 September 2026 — Approved subscription model supersedes earlier drafts

The earlier planned no-card 30-day trial and annual new-purchase copy are superseded by the approved Apple one-month free introductory offer, then £14.99/month automatic renewal. Eligibility must be confirmed by StoreKit. The app remains free to download; existing lifetime beta access is preserved. Do not submit build 20 or prior review notes as implementing this new journey. Use the newly built compatible candidate and the 12 September trial/terms disclosure. Public submission stays paused. Detailed source/provider evidence and remaining Apple/Sandbox/reminder gates: `releases/2026-09-12-apple-trial-customer-journey.md`.
