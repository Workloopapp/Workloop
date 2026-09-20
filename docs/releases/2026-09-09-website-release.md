# Website release — 9 September 2026

The owner requested the new Workloop features be uploaded to TestFlight and the
website updated, then explicitly authorized distribution to the existing beta
testers. This receipt records the website portion; Apple distribution is recorded
separately in `2026-09-09-build19-testflight.md`.

## Published content

The existing website design and broad audience were preserved. The home, product,
FAQ, how-it-works and pricing pages now describe connected quotes and invoices,
deposits, recurring bookings, receipt reading/review and mileage. Tax language is
limited to the implemented 2026/27 planning estimate for eligible non-VAT sole
traders in England, Wales and Northern Ireland; it does not promise HMRC filing.
Existing prices and beta access terms were preserved. No job-profit feature was
introduced or advertised.

The public privacy notice now explains business-document/tax inputs, on-device
receipt reading, reviewed expense details and private receipt-attachment storage,
with an effective date of 9 September 2026. Metadata, JSON-LD and changed-page
sitemap dates match. Two current Money screenshots use fictional test fixtures.

## Source and validation

- Source: `/Users/ismaeelsmiley/Documents/Workloop Website`.
- Commit pushed: `6483e058373b448bb55ebf6652d03a09c3977dec`.
- Twelve changed files: README, six page/layout files, privacy, sitemap, two
  product screenshots and the existing rendered-HTML test.
- The canonical source was copied to a temporary build directory and hash-checked
  against the committed files. Existing untracked files with ` 2` suffixes were
  preserved in the real checkout and excluded from the release.
- TypeScript, ESLint, production build and all **44 website tests** passed.
- Existing dependencies and lock files were retained. The pnpm wrapper initially
  refused a noninteractive dependency reinstall in the copied directory; the
  existing local command binaries completed the same checks without reinstalling.

## Deployment and live proof

- Sites project: `appgprj_6a6926a374f881918d8aed9f3b21307e`.
- Saved version: **39**, ID
  `appgprj_6a6926a374f881918d8aed9f3b21307e~appgver_a637f670e2a48191bc28fedd9451fd0d`.
- Package SHA-256:
  `5c19a3dee1ef22374fc205c8c1ead45e7ca058ac7f2981574c89e4713638a8fc`.
- Deployment: `appgdep_6aa0fd5bcd28819188e894d9af25d4e2`, **succeeded** at
  06:33:31 UTC. Existing public access was preserved.
- Public origin: **https://workloop.uk**. Cache-busted fetches returned HTTP 200
  for the home, product, FAQ, privacy, sitemap and both new screenshots. Feature,
  tax-year and privacy-date markers were present in the appropriate pages.
- Live Money screenshot SHA-256:
  `8a1c44ae06cbd14483c9898a051aea1a2f0d9364793df3ed9b3b25bd4587e58b`.
- Live Payments screenshot SHA-256:
  `bca60b9c912a97f1d0b9b23b29b9b97912f3848212ade3dd5549362281b6c2d5`.
  Both exactly match the validated fictional app screenshots.

The first Python-default-agent fetch received HTTP 403; normal browser-agent
requests succeeded. No authentication bypass was used for this public proof.
The temporary development server was stopped after publication. This release did
not change public App Store availability, social posts, paid campaigns or testers.

Evidence: `/private/tmp/workloop-site-live-verification-20260909.json`,
`/private/tmp/workloop-site-sept9-*.log` and
`/private/tmp/workloop-site-release-20260909.tar.gz`.

## Final help-page alignment — version 40

A final targeted check found three stale navigation directions. Connections help
now says **Client files**, owner email help says **Settings → Emails to you**, and
booking-reminder help says **Settings → Customer messages → Booking reminders**.
These are copy corrections in two existing help pages, with the connections
sitemap date updated. No additional product functionality was invented.

- Final source commit: `e04623c17cd3f858bc88a6cf8e6ef725704a20dd`.
- Final saved version: **40**, ID
  `appgprj_6a6926a374f881918d8aed9f3b21307e~appgver_4afda214ccb881918c28f0cead436f19`.
- Final deployment: `appgdep_6aa1012ff7748191963c24732c5e2eed`, succeeded at
  **06:48:28 UTC**.
- Local compressed package SHA-256:
  `49d941a2c31da2e19a1a806489cad47ca5afeccf745976615abdb738785af3ca`.
- Sites stored archive content hash:
  `35d52d92848a752d72067631f09611266e01e7a655534b56096c84e966867eb2`.
- TypeScript, ESLint, production build and all **44 tests** passed again following
  these changes. The initial shell omitted the bundled Node path; rerunning with
  that configured runtime resolved the tool invocation without dependency edits.

Automatic approval review initially rejected the source push as an unverified
destination. Read-only checks then proved the Sites-returned source repository
matched this exact hosting project, the current owner/public workloop.uk account,
and the already published version 39 commit. The same push was approved after
that evidence; no alternate destination, credential storage or bypass was used.

Release packages, logs and live fetch proof are retained under
`build/release-build19-20260909/website/` in the Workloop checkout. All existing
untracked duplicate files remain untouched.

Final cache-busted public fetches verified all three corrected help directions,
the updated sitemap date and the unchanged receipt-reading privacy disclosure
on workloop.uk with HTTP 200. The receipt is
`build/release-build19-20260909/website/live-help-verification.json`.
