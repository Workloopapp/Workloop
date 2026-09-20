# Booking fixes and remote access — 7 September 2026

## Result

- Requested dates/times now prefill confirmation correctly, including existing text-only requests. The reported `2026-09-11 at 07:41` resolves to 11 September at 07:41 in the business timezone; the London UTC payload is `2026-09-11T06:41:00Z`.
- Exact booking links render the target directly. They no longer briefly show Today or add an unnecessary Back step.
- Tomorrow briefing displays normal business-local `HH:mm` without BST/GMT. Actual timezone conversion is preserved. Customer message content and explicit repeated-hour disambiguation retain their relevant timezone information.
- The public website now sends a validated exact timestamp and business timezone for manually entered dates/times. New requests no longer depend solely on display text. General enquiries remain possible; a partial, invalid or ambiguous time cannot silently become another booking time.

## Files and reasons

The [request prefill report](2026-09-07-booking-request-prefill.md) lists the helper, form, repository and regression files. The [direct navigation report](2026-09-07-direct-tomorrow-booking-navigation.md) lists the route, detail accessibility label and Tomorrow changes. `pubspec.yaml` is now `1.0.0+14` to distinguish the corrected local build from uploaded build 13.

The marketing checkout at `/Users/ismaeelsmiley/Documents/Workloop Website` changes the public request form, page and profile typing; adds `app/booking-request-time.ts`, its behavior tests and `docs/BOOKING_REQUEST_TIME.md`; and updates the existing form-wiring assertion to the validated result. No schema, dependency or customer-data rewrite is involved.

## Integrated validation

- `flutter analyze`: clean (`/tmp/workloop-build14-analyze.log`).
- Full `.env` suite: **1,011 passed, six payment-capability tests skipped** (`/tmp/workloop-build14-tests.log`).
- Those gated payment suites rerun with payment collection and subscriptions enabled: **7 passed, zero skips** (`/tmp/workloop-build14-enabled-payment-tests.log`; one existing ungated test is included again).
- Signed iOS profile build succeeded, 76.2 MB, bundle `com.ismaeel.workloop`, version `1.0.0 (14)`. Payment collection, subscriptions and crash reporting enabled, matching the previous candidate configuration. Both location-purpose strings verified in the built Info.plist. Log: `/tmp/workloop-build14-profile.log`.
- App `git diff --check`: clean. Prior dirty work preserved; uploaded build 13's isolated source/artifact untouched.
- Website TypeScript and lint clean. Final production build and **43 tests** passed. Eight additional actual React form/browser fixture checks passed in an America/Los_Angeles browser against a London business, with request writes intercepted. No real customer requests or emails were sent.
- One old website source assertion expected the former `requestedFor: selectedSlot` wiring. It was updated to require the validated time result; the behavior tests separately verify both manual and selected-slot payloads. The final full website run passed.

## Website publication

Public Workloop website version **37**, source commit `d6a86d4d7b6891cee1be5f9157562f64e7f122a8`, deployed successfully to the existing public audience. Project: `appgprj_6a6926a374f881918d8aed9f3b21307e`; deployment: `appgdep_6a9e626ff82481919f3e4507aff72898`.

The live `https://workloop.uk/testshop` response independently returned HTTP 200 and the exact `explicit-business-time-v1` marker. Receipt: `/tmp/workloop-booking-time-live-verification.json`. Browser fixture evidence and the reviewed patch remain in `/Users/ismaeelsmiley/Documents/Workloop Website Review/2026-09-06-launch/booking-time-origin`.

## Device and release limits

Build 14 is compiled locally, **not installed or uploaded to TestFlight**. Installation could not find the phone; a fresh Apple device listing shows it paired but with its tunnel unavailable. iPhone Mirroring reports the phone in use. The user has been asked to restore cable/Wi-Fi connectivity for installation. Physical validation of these fixes therefore remains pending. Build 13 remains the previously uploaded binary.

Existing incorrectly confirmed bookings are not silently moved. Their owner must explicitly correct them. A legacy request with no historical timezone uses its current workspace timezone; an undocumented past timezone change cannot be reconstructed.

## Remote Codex access

The user's Settings screenshot confirmed the iPhone pairing, Allow connections and Keep this Mac awake already enabled. The user opened this task over 5G and subsequently confirmed current messages were working after reopening. No new VPN, public port or account change was needed. Keep the Mac online, plugged in and running ChatGPT; laptop lid open unless using a supported external-display setup. Setup guidance: https://learn.chatgpt.com/docs/remote-connections.

Suggested app commit: `fix: preserve requested booking times and open exact bookings directly`.

## TestFlight upload follow-up — 7 September 2026, 08:31 BST

The user is at work and cannot reconnect the iPhone. The earlier local-only
release status above is superseded by this upload receipt; physical checks remain
pending. No cable connection is required for a later TestFlight installation.

- Frozen clean source: `/Users/ismaeelsmiley/Workloop-Releases/build14-20260907T072221Z/Workloop`, commit `9abee299b88f5fd639c54ca3c2ab9b5184a146d7`. Root dirty work was preserved.
- Signed distribution build **1.0.0 (14)** succeeded from the tested source. Bundle/version, strict signature verification, production APNs entitlement and both location-purpose strings were checked in the exported IPA. No background-location mode is enabled.
- Release configuration matches build 13: payment collection, subscriptions and crash reporting enabled; production APNs; Tap to Pay disabled. Public build configuration SHA-256: `2a5d4f056113a5abcf3031a0021235f9c3d856bc36e9759aa4744a85b0a63bce`.
- Local reviewed IPA: 35,828,145 bytes, SHA-256 `d9c24bee0c4a8be4a6b778e107816971c6cc0f9e96d65f5014a49f2c8a915ea1`. The upload used the same signed archive via Xcode's App Store Connect export; this hash describes the retained local IPA, not an independently retrieved Apple package.
- Xcode upload **succeeded at 08:31:11 BST / 07:31:11 UTC**. Apple reported **“Uploaded package is processing”** and Xcode returned `EXPORT SUCCEEDED`.
- The known nonblocking upstream StripeTerminal dSYM warning remains. It affects symbolication inside that vendor framework; see the [overnight release record](2026-09-07-launch-preparation.md). No location-purpose warning occurred in this upload log; later processing messages have not been independently checked.

**Availability limit:** processing completion and assignment/availability to beta
testers are not yet verified. Safari's App Store Connect session is signed out;
Xcode's existing login worked for upload, but Organizer does not supply the live
build/group status here. No user announcement was sent claiming build 14 is
already installable. No public App Store release was submitted.

Durable build/upload logs, source manifest and `release-verification.json` are
stored beside the frozen checkout in
`/Users/ismaeelsmiley/Workloop-Releases/build14-20260907T072221Z`.
