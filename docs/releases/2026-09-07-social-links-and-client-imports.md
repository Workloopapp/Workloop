# Social links and client-file interoperability

Website https://workloop.uk now has Instagram, Facebook, TikTok and X footer
icons, matching organisation `sameAs` data, a Works with strip and a guide at
https://workloop.uk/help/connections. Copy distinguishes one-time calendar/CSV
transfers, manual WhatsApp sends, contacts available on the phone, external maps
and eligibility-dependent Stripe payments. It does not advertise the new vCard
feature as already available to installed beta users.

Website source `43c4ab0bc328e686331a939365df82e179035840`, Sites version 38,
deployment `appgdep_6a9ebaa4a3a48191ba77dd6ba08a4a75` succeeded. Independent
HTTPS requests confirmed new homepage/guide content and HTTP 200 for all four
social icons. An initial Python request returned 403; curl subsequently returned
200 with the expected content. Preview handoff was queued; no browser visual QA.

## App changes, local only

- `client_file_import.dart` adds UTF-8 vCard 3.0/4.0 parsing and better CSV header
  recognition. First/last names combine when full name is absent. Google contact
  type/label columns and organisation names are not mistaken for contact values.
- `csv_import_screen.dart` reuses existing repositories, duplicate checks and
  partial retries. The preview allows excluding contacts and showing more than
  twenty records. Only confirmed client records are sent to the backend.
- `import_data_screen.dart` renames Client CSV to Client files with clearer
  Apple/Google contact and spreadsheet guidance.
- `client_file_import_test.dart` covers grouped/folded vCards, escapes, Unicode,
  multiple contacts, extra detail preservation, structured names, CSV mapping,
  malformed/unsupported files and limits.

Extra vCard phone/email/address values are retained in client notes. Photos and
unsupported fields are not imported. vCard 2.1 and older encoded files require
re-export as supported vCard or CSV. Limits: 5 MB, 1,000 contacts, 100 columns.
No new dependencies, migrations, credentials, paid services or OAuth grants.

## Verification

- Website typecheck, lint, production build and 44 tests passed.
- Flutter analysis: no issues; full suite: 1,018 passed, six capability skips.
- After a final error-message correction for deselecting all contacts, analysis
  and all 24 import tests passed again.
- Signed iOS profile build passed on final source (76.2 MB). Existing SPM notices
  for device_calendar and flutter_local_notifications did not block compilation.
- No physical-device import/file-picker test, new TestFlight upload or new Android
  artifact. Frozen Android build 14 remains unchanged. Root dirty work preserved;
  app changes remain uncommitted. Website changes were committed for deployment.

Next: test choosing Google/Apple contact exports on real iPhone and Android
devices before distributing the app change. Live calendar/accounting sync would
need separately defined authentication, data ownership and conflict handling.

Suggested app commit: `Add reviewed vCard imports and improve client CSV mapping`.

## References

- https://support.google.com/contacts/answer/7199294
- https://support.apple.com/en-ca/guide/icloud/mmfba748b2/icloud
- https://www.rfc-editor.org/rfc/rfc6350.html
- Icon assets: https://github.com/simple-icons/simple-icons
- Facebook/X links: existing owner publishing ledger/growth release record.
  Instagram/TikTok links: supplied by the owner earlier in this task.
