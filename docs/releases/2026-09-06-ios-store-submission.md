# Workloop — current iPhone App Store submission pack

Prepared 6 September 2026. This is the current working pack; the older content in
[StoreSubmission.md](../StoreSubmission.md) remains historical. It is local
preparation, not an App Store submission or approval.

## Current submission state and launch scope

The current App Store Connect inspection by the lead agent found the public
**iOS 1.0** record in **Prepare for Submission**: **0 of 10 screenshots**, empty
description/promotional text/keywords/support/marketing/copyright fields, no
selected build, and empty public-review contact and login fields. Automatic
release is currently selected. Existing TestFlight reviewer information does
not fill those public-review fields automatically. The most recent observed
external group build is **11**, with 13 testers; it does not include the final
local revision below.

The latest completed local Money receipt is **1.0.0 (12)**: 863 full-suite tests,
76 payment-enabled checks, accepted Money screenshots and successful native
profile builds. It was installed at 02:02 BST; the locked phone prevented final
visual checks. Crash reporting, public legal identity and any further launch
changes being integrated now need their own final verification and signed
distribution artifact. See [the Money receipt](2026-09-06-money-profit-and-timeline.md).

The agreed first public release is **iPhone only**, portrait, iOS 15 or later,
with the Quiet + Warm theme. Workloop is free to download and use, without a
Workloop subscription or digital in-app purchase. Hosted Stripe payment links
are included for eligible businesses. Device Tap to Pay, payment readers, SMS
and phone-number authentication are not launch promises. WhatsApp reminders
prepare a message for the business owner to send. Customer email reminders are
automatic when eligible and enabled. Android public distribution remains out
of this submission.

Release configuration must explicitly enable `PAYMENT_COLLECTION_ENABLED` and
disable `TAP_TO_PAY_ENABLED` and `WORKLOOP_PHONE_AUTH_ENABLED`; the source
capability defaults alone are not the release configuration. Use production
APNs with a distribution-signed App Store archive. Keep the existing App Store
record; confirm version/build compatibility when choosing the new processed
build rather than making a duplicate app record.

## Operator and legal identity — unresolved before publication

The owner has now requested **Workloop as a trading name of Haani Enterprise
Limited**. The lead agent's live Companies House inspection found company
**15758586**, registered office **35 Well Lane, Batley, WF17 5HQ**, with status
**Active — Active proposal to strike off**, first accounts overdue from
3 June 2026 and confirmation statement overdue from 16 June 2026.
[Official company record](https://find-and-update.company-information.service.gov.uk/company/15758586).

These are verified register details reported by the lead agent, not confirmation
that the company already operates Workloop, owns its intellectual property or
is the current Apple account holder. Do not publish an invented identity or
silently substitute the registered office for an approved public support address.
The owner and lead agent are resolving the company filings, operating entity,
rights owner and appropriate contact details. Apple membership type and legal
seller identity must also be inspected: a personal developer account cannot be
presented as an organisation simply by changing the app description.

If EU storefronts are selected, complete Apple's applicable trader declaration
and verification using the actual operator's details. A commercial app should
not select non-trader merely to hide an address. Country availability still
needs an explicit final choice; the current product uses pounds and includes
UK-specific address/weather-area choices.
[Apple trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

## Copy-ready English (UK) metadata

| Field | Exact proposed value | Validation/status |
| --- | --- | --- |
| App name | `Workloop: Solo Business OS` | 26 characters; confirm availability in the existing record |
| Subtitle | `Clients, bookings & money` | 25 characters |
| Primary category | Business | Recommendation based on the owner-operated business workflow |
| Secondary category | Productivity | Recommendation |
| Primary language/localisation | English (UK) | Check the existing record before changing primary language |
| Marketing URL | `https://workloop.uk` | Final public content/availability check required |
| Privacy policy URL | `https://workloop.uk/privacy.html` | Current app constant; operator/Crashlytics disclosure update and public verification required |
| Support email | `support@workloop.uk` | Existing Workloop inbox; perform final inbound/reply smoke check |
| Support URL | **Pending a verified public contact/help page** | Do not enter the unverified `/support` route; no such route was found in the inspected website source |
| Privacy choices URL | `https://workloop.uk/help/email-preferences` | Optional; this covers email choices only, so a general privacy/deletion page may be better |
| Account deletion information | `https://workloop.uk/delete-account.html` | Reuse the existing public route after checking its current body |
| Copyright | `2026 [confirmed rights owner]` | Required; proposed company name is not yet a verified rights-ownership statement |
| Price | Free | No Workloop subscription/IAP products to attach for this release |
| Release control | Manual release after approval | Recommended launch control; current Apple selection is automatic |

Apple limits the name and subtitle to 30 characters. Keywords allow 100 bytes;
this ASCII keyword string is **95 bytes/characters**. Promotional text below is
**153 characters**, below 170. The description below is **2,530 characters**,
below 4,000. Review-note draft: **3,539 characters** before access placeholders
are replaced.
[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/),
[version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

Keywords:

```text
selfemployed,freelance,appointments,expenses,payments,reminders,calendar,tasks,notes,soletrader
```

Promotional text:

```text
Your business, one clear day. Keep clients, bookings, income, expenses and follow-ups connected in a warm retro workspace built for working for yourself.
```

Description — paste the plain text inside this block:

```text
Work for yourself. Keep your business together.

Workloop gives people who work for themselves, by themselves one calm place to manage the day. Clients, bookings, tasks, notes and money stay connected, so you can see what is happening, what needs attention and what to do next.

Built around the everyday work of solo service businesses — from cleaners and mobile valeters to tutors, beauty professionals and independent specialists — Workloop brings a warm retro look to practical business tools.

START WITH TODAY
See your next booking, useful reminders and the work that needs attention. Open the relevant booking, request, task or payment straight from the dashboard. Track your monthly income target without digging through separate screens.

KEEP CLIENTS IN CONTEXT
Save contact details, preferences and notes alongside each client's bookings, payments and tasks. Add clients manually or review selected contacts before importing them.

PLAN YOUR WORK
Organise one-off bookings, services and working hours. Keep tasks and notes close to the work they belong to. Share a booking page where customers can send requests for you to review and confirm.

UNDERSTAND YOUR MONEY
Record income and expenses. See net profit from recorded income minus expenses, with week, month and custom-date views. Search a combined Payments timeline, filter income or expenses, and keep outstanding amounts in a separate Owed view. Connect an eligible Stripe account to send hosted card-payment links for your services.

HELP CUSTOMERS REMEMBER
Set up booking emails and customer reminders before appointments, including 24 hours and one hour ahead. Prepare a WhatsApp reminder, check the message and send it yourself. Keep your own alerts, customer messages and Workloop emails easy to tell apart in Settings.

MAKE IT YOUR WORKSPACE
Follow a short first-use guide, choose a light or dark appearance, and keep your business records synced to your account. Optional local weather helps you plan the day. Export your workspace data or request account deletion from Settings.

Workloop is free to download and use, with no Workloop subscription. Card collection requires an eligible connected Stripe account; Stripe's processing fees and terms apply. WhatsApp is optional and reminders are sent by you. Internet access is needed for account services and syncing.

Workloop helps you organise operational business records. Net profit reflects the income and expenses recorded in Workloop; it is not a bank feed, tax calculation or accounting service.
```

## App Review notes and account access

Reuse the dedicated fictional-data reviewer account recorded in the historical
handoff, **after** checking it can sign into the final submitted build. Its
credentials belong only in App Store Connect's secure review fields and the
owner's approved secret store. No credentials are copied into this repository.
Public review fields are currently empty. Supply the actual reviewer contact's
name, phone and monitored email; do not infer them from the company register.

Review notes — paste only after replacing the two explicit access placeholders
with verified instructions; keep credentials in Apple's separate fields:

```text
Workloop is an iPhone business workspace for a single service-business owner. This is a free app with no subscription, paid digital feature, bank account feed or in-app purchase.

Sign in using the dedicated email/password account entered in App Review Information. The account must not require access to a private email inbox or a one-time code during review. It contains fictional clients, bookings, income and expenses. [CONFIRM THE REVIEW ACCOUNT AND FICTIONAL WORKSPACE BEFORE SUBMITTING.]

The five main tabs are Today, Clients, Work, Money and Business. Today opens the next booking and items needing attention. Work contains Schedule, Tasks and Notes. Money > Overview shows received income, net profit from recorded income minus expenses, a monthly income target and a searchable Payments timeline. Spent and Owed have their own search. Payments includes income and expenses; partially paid amounts remain visible in Owed until settled.

Business > Manage booking page opens the owner's booking-page controls. Customers submit booking requests on the website. The business owner reviews and accepts or declines them; this is not automatic booking confirmation. [INSERT THE VERIFIED FICTIONAL REVIEW BOOKING-PAGE URL AND ANY CURRENT ACCESS INSTRUCTIONS.]

Money > Get paid with Workloop provides Stripe-hosted account onboarding and payment links for eligible businesses. These payments are for the business's real-world services, not for access to Workloop or digital content in this app. Card entry is hosted by Stripe; Workloop receives transaction status. Device Tap to Pay and external payment readers are disabled in this release. Do not enter invented identity/bank details to activate the sample business. The submitted review account/payment demonstration must be arranged and verified before review; no real payment or bank account is required to inspect manual money tracking.

Settings > Your alerts controls the owner's in-app and phone alerts. Task/booking phone reminders are local notifications; operational business alerts use remote push when permission and registration are available. Settings > Customer messages controls eligible automatic booking emails and explains manual WhatsApp reminders. A WhatsApp action opens a prepared message; the owner must press Send. SMS and phone-number sign-in are not enabled.

Contacts, calendar import and location are optional. Contacts/events are reviewed before import. Calendar export is a point-in-time ICS file. Local weather is off until chosen; foreground approximate location or a manually chosen UK area can be used. Denying these permissions leaves manual workflows available. Camera/photo purpose strings come from linked file-picker capability; this version's documented import flows are CSV/text/Markdown, not a camera/photo collection feature.

Use Business > Settings > Privacy & data to export the workspace or request account deletion. The deletion flow explains scope, checks ownership and asks for confirmation. For a deletion test, use a separate disposable review account so the main review account remains available.

The design is the current Quiet + Warm light/dark theme. Google sign-in, native Sign in with Apple and email account access must be tested on the submitted build. Account-based workspace records are held in the service, not solely on the phone. Release diagnostics are described in the privacy policy and App Privacy disclosures. Core features remain usable if optional weather, WhatsApp or notification permissions are unavailable.
```

Hosted payment links for services consumed outside the app fit Apple's
outside-app services payment rule. A real, reviewable payment flow is still
required; a restricted fictional merchant is not proof that collection works.
Apple also requires working review access, accurate screenshots and accessible
backend services. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Screenshot story and exact production requirements

Use **six portrait frames** in this order, with one clear headline each. All
screens must be actual current app UI with fictional records. Use cream,
powder blue, warm outlines, restrained yellow and the bundled Manrope type;
follow [Quiet + Warm](../brand/QUIET_WARM_IMPLEMENTATION.md). Avoid the old neon
palette, oversized phone mockups and any wording that implies live slot
booking, automatic WhatsApp, SMS, Tap to Pay or a paid Workloop plan.

| Order / headline | Screen and story | Current authentic reference |
| --- | --- | --- |
| 1. Your day, already organised | Today: next booking and an actionable request | [Today](../../test/golden/files/dashboard-focus-light.png) |
| 2. Every client, all together | Client details, linked work and contact actions | [Client](../../test/golden/files/client-detail-quiet-warm-light.png) |
| 3. Keep your work moving | Work schedule/calendar and linked tasks | [Schedule](../../test/golden/files/work-schedule-light.png), [calendar](../../test/golden/files/bookings-calendar-light.png) |
| 4. See what you actually made | Current net-profit chart and monthly target | [Money overview](../../test/golden/files/money-populated-light.png) |
| 5. Every payment in one timeline | Searchable income/expense history with clear signs | [Payments](../../test/golden/files/money-timeline-light.png), [search](../../test/golden/files/money-timeline-search-light.png), [dark alternative](../../test/golden/files/money-timeline-dark.png) |
| 6. Give customers a clear next step | Business booking page and owner-reviewed requests | [Booking page](../../test/golden/files/booking-page-owner-hub-light.png) |

These assets exist and are generated from current Flutter widgets and
fictional fixtures. The Money and Today references were visually inspected for
this pack; the recent whole-suite receipt verifies the accepted baselines.
**They are 390 × 844 RGBA test renders, not App Store-ready screenshot files.**
Reuse their fixtures and composition, not stretched low-resolution bitmaps.

Capture the final release UI at **430 × 932 logical points with device pixel
ratio 3**, or directly on the connected iPhone 15 Pro Max, to produce
**1290 × 2796** portrait screenshots. Keep all six files at the same dimensions.
Use an isolated fictional-data account; do not upload screenshots from the
owner's populated personal workspace. Export opaque RGB PNG/JPEG with no alpha
channel and check every final frame for clipping, realistic readable data and
accurate selected navigation. Text overlays may explain a real screen, but the
UI must remain clear. No screenshot may claim an unverified collection success.

Apple currently accepts 1290 × 2796 in the 6.9-inch set, allows one to ten
screenshots and rejects image transparency. The iPhone-only target does not
require an iPad-specific set. Optional previews are not needed for this pack.
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

The current [App Store icon](../../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png)
is **1024 × 1024 RGB PNG**, with no alpha channel. Verify the distribution
archive embeds this icon; a separate social-media avatar is not its substitute.

## App Privacy — source-based answer worksheet

The app collects data off the device through Supabase and its operational
providers. Do not choose **Data Not Collected**. Data is generally linked to
the account, workspace or installation. The current inspected design does not
use an advertising SDK, IDFA or cross-app ad matching; answer **not used for
tracking** only after confirming the final SDKs and embedded service pages
retain that behaviour. First-party marketing emails still require their
marketing purpose to be disclosed.

The proposed conservative mapping below covers the release data flows. Optional
permission or a small user population does not make ordinary feature data
exempt. Apple distinguishes payment information from income/expense records;
hosted checkout alone is not enough to claim the payment-data exception if the
developer can access provider payment metadata. [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

| Apple type | Collected / linked | Purpose to declare | Current evidence and bounds |
| --- | --- | --- | --- |
| Name; Email Address | Yes / yes | App Functionality; Developer's Advertising or Marketing for eligible account emails; Product Personalization for tailored onboarding | Auth, business/client records, confirmations and first-party account journeys. Do not imply every customer address is a marketing subscriber. |
| Phone Number; Physical Address | Optional / yes | App Functionality | Business/client/contact details and booking locations. Phone storage does not mean SMS is enabled. |
| Contacts | Optional / yes | App Functionality | Only contacts selected and saved as clients are imported. The saved records then sync. |
| Other User Content | Yes / yes | App Functionality; Product Personalization where setup progress selects guidance | Bookings, notes, tasks, services, public-page content and reviewed calendar/file imports. Generic free text is not a reason to declare every possible sensitive subject. |
| Emails or Text Messages | Yes / yes | App Functionality; Developer's Advertising or Marketing for the account marketing series | Recipients/content of service and account emails held in outboxes/Resend; support correspondence. The app does not read the owner's mail inbox or WhatsApp history. |
| Customer Support | Optional / yes | App Functionality | User-sent support message, contact and app/version/platform diagnostics in the support email draft; received by the support mailbox. |
| Other Financial Info | Yes when used / yes | App Functionality | Income, expenses, balances, refunds, disputes, amounts and provider references. Net profit is computed from recorded amounts. |
| Payment Info | Include for the payment-enabled release / yes | App Functionality | Stripe-hosted entry avoids Workloop collecting full card numbers in its own form, but the server retains full Stripe webhook event payloads under a 30-day retention policy. Method/card/bank metadata must be considered. Revisit only after an audited restricted payload proves an exemption applies. |
| Purchase History | Include conservatively for recorded service transactions/expenses / yes | App Functionality | Customer service payments and business expenditure; this does not imply a Workloop in-app purchase. Confirm final form classification alongside Other Financial Info. |
| Coarse Location | Optional / yes conservatively | App Functionality | Weather coordinates are rounded to two decimals before the authenticated server call. Server cache/provider handling means not claiming ephemeral-only processing. No background weather tracking. |
| Search History | Include conservatively for address/area lookup unless provider retention is excluded / yes conservatively | App Functionality | Google Places receives the lookup query. The new Payments, Spent and Owed searches filter loaded records locally and do not create a server search-history log. |
| User ID | Yes / yes | App Functionality; Developer's Advertising or Marketing and Product Personalization for eligible account journeys | Account/workspace IDs, authentication and lifecycle preferences/activity. |
| Device ID | Yes / yes conservatively | App Functionality | Stored APNs token, Firebase installation/session identifiers and release diagnostic identifiers. No claim that a token is anonymous just because it is not a person's name. |
| Product Interaction | Yes / yes | App Functionality; Product Personalization; Developer's Advertising or Marketing; Analytics where evaluating email engagement | Foreground/hourly activity updates drive inactivity guidance; delivery/open/click events may be recorded when the email provider sends them. Firebase Sessions technical lifecycle data also needs final SDK review. |
| Crash Data; Other Diagnostic Data | Yes in the diagnostic-enabled final release / yes conservatively | App Functionality | Current source includes Firebase Crashlytics. Declare native crash/device/build/session data plus filtered Dart reports; absence of an assigned user ID is not a guarantee of anonymity. Final archive and ingestion checks remain pending. |
| Performance Data | Final archive/provider check required | App Functionality if collected | There is no Firebase Performance integration in the inspected app. Confirm whether final Crashlytics/session/transport metrics meet this category rather than claiming none merely because that package is absent. |

No targeted Photos/Videos, Audio, Health/Fitness, Credit Info, Contacts-wide
automatic upload or Browsing History collection was found in the reviewed
app workflows. Generic notes remain Other User Content. Linked plugin purpose
strings are not themselves evidence that a media-import feature collects data.

For Crashlytics, the current Dart reporter excludes user IDs, record IDs,
request/customer/payment fields, custom free-form logs and raw exception text.
Native reports still carry stack traces and device/OS/app context. Firebase
Messaging also uses installation/APNs identifiers; Sessions and transport can
add technical lifecycle/quality data. Audit all transitive targets in the final
archive. Do not claim that avoiding Analytics removes all SDK collection.
[Firebase's Apple disclosure guide](https://firebase.google.com/docs/ios/app-store-data-collection),
[Firebase privacy](https://firebase.google.com/support/privacy).

Source anchors: [email activity](../../lib/shared/email/email_journey_bootstrap.dart),
[email preferences](../../lib/shared/email/email_preferences_repository.dart),
[push registration](../../lib/shared/repositories/push_token_repository.dart),
[weather](../../lib/features/weather/local_weather_repository.dart),
[Stripe webhook](../../supabase/functions/stripe-webhook/index.ts),
[Stripe payload retention](../../supabase/migrations/20260812120000_enforce_privileged_mfa_and_stripe_retention.sql),
[Resend receipt handling](../../supabase/functions/resend-webhook/index.ts),
[support draft](../../lib/features/settings/support_screen.dart),
[filtered crash reporter](../../lib/shared/diagnostics/crash_reporter.dart).

## Final evidence and submission gates

| Gate | Current action / evidence needed |
| --- | --- |
| Operator and company status | Confirm actual operating/rights-owning entity, resolve the identified company filing/strike-off issue with the owner, verify Apple's seller/membership identity and approved public contact details. |
| Legal/support URLs | Publish the approved operator and all current provider/data/marketing/diagnostics disclosures consistently in app and website. Add/verify a real public support page, incoming email and reply. Current web-tool attempts could not open the public URLs; that is not evidence the pages are broken. |
| Reviewer account | Recover the existing dedicated credential securely, test it on the final build and enter it into the currently empty public-review fields. Verify the fictional public booking-page URL. |
| Genuine card collection | Complete the known genuine-merchant charge/refund/receipt/webhook evidence. Clearview is fictional and restricted. Prepare a safe, working review demonstration; do not invent a bank account or label restricted onboarding as verified collection. |
| Final distribution binary | Finish current crash/legal work, full regression checks, archive/sign/export, verify production APNs, capability flags, embedded icon, version and app entitlements. Use a new build number when required by Apple. The profile build-12 receipt is not an uploaded distribution artifact. |
| Final screenshots | Render/capture all six at the native upload dimensions, remove alpha, inspect final files, then upload. Existing 390 × 844 goldens are reference material. |
| Auth | Complete final-device email confirmation/recovery/link return, Google return and native Apple return/account linking. The September 5 provider/configuration checks are not completion of these journeys. |
| Notifications and diagnostics | Verify a controlled production-APNs foreground/background/terminated alert and exact tap destination; confirm Crashlytics ingestion/symbols without customer data. Do not send a test message to a real customer. |
| Privacy and SDK manifest | Enter the final labels based on this worksheet plus final SDK behaviour; review Xcode's aggregate privacy report and required-reason manifests in the distribution archive. The current profile contains multiple plugin manifests but is not the final crash-enabled archive. |
| App information | Check title availability, category, pricing, English (UK) localisation, content rights, age-rating questionnaire, export-compliance answers and territories. Source declares `ITSAppUsesNonExemptEncryption=false`; verify the final archive and actual encryption use. |
| Accessibility claims | Only select supported Apple accessibility labels after the submitted build's VoiceOver, large text, contrast, colour independence, dark appearance and reduced-motion journeys are manually verified. Automated tests alone do not certify those claims. |
| Publication control | Set and confirm the intended release option; the currently automatic setting can publish after approval. Final approval/submission/release should refer to the concrete selected build and completed metadata. |

No app/backend configuration, user record, email, payment, Apple field or company
filing was changed in preparing this document. No credentials or fabricated
operator/reviewer details were added. Suggested documentation commit:
`Prepare current iPhone App Store submission pack`.

## Later execution receipt — 6 September 2026 evening

This receipt supersedes the initial read-only scope and automatic-release observation above. The owner authorised proceeding with company conversion and launch preparation, with distribution/public launch still pending the concrete release gates.

- Saved the prepared promotional text, description, support URL (`https://workloop.uk/help/welcome`) and marketing URL (`https://workloop.uk`) in the iOS 1.0 draft. Actual saved keywords: `self employed,clients,booking,schedule,invoice,income,expenses,reminders,calendar,tasks,notes` (93 characters).
- Selected **Manual release** and saved; the Save control became disabled after persistence. No Add for Review action, binary selection, screenshot upload, review credential entry or public release occurred.
- Submitted the existing Apple Individual-to-Organisation conversion request for Haani Enterprise Limited. Apple acknowledged receipt and estimated one business day. Conversion and agreements remain pending. Company financial documents and provider details are held in the owner's private company folder, not this repository.
- Built signed iOS profile 1.0.0 (12) with `PAYMENT_COLLECTION_ENABLED=true`, `TAP_TO_PAY_ENABLED=false`, `WORKLOOP_PHONE_AUTH_ENABLED=false`, `WORKLOOP_CRASH_REPORTING_ENABLED=true` plus `.env`. Installed and launched on the paired iPhone 15 Pro Max. These are profile-build/device receipts, not distribution or interactive QA evidence.
- `flutter analyze`: clean. Full payment-enabled test suite: **891 passed**. Targeted default-config payment tests: **17 passed**. `git diff --check`: clean.
- Initial payment-enabled run: 889 passed, two tests failed because they assumed the build flag was always false. `money_create_action_test.dart` now explicitly overrides the payment provider to false for its baseline UI scenario; `stripe_payments_contract_test.dart` checks the actual requested build flag. Enabled and default reruns passed. No runtime code was changed as part of this test correction.
- Physical screen/auth/push checks remain pending because Mirroring reported the phone in use. Final screenshots, review credentials, production APNs/crash verification, genuine connected-merchant payment evidence, company/provider completion and distribution archive remain outstanding. This does not certify public-launch readiness.

Suggested test commit: `Make payment capability tests valid across release configurations`.
