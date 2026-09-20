# Workloop email operator disclosure

Effective 6 September 2026, Workloop email footers identify **Haani Enterprise
Limited**, registered in England and Wales, company **15758586**, registered
office **35 Well Lane, Batley, WF17 5HQ, England**. The product remains Workloop;
outbound and support addresses remain `hello@workloop.uk` and
`support@workloop.uk`. No unfiled address is used.

## Implementation

`supabase/functions/_shared/workloop_operator_email.ts` provides one shared
HTML/plaintext disclosure. Pure email renderers append it without changing their
subjects, content, business contact details, reply addresses, unsubscribe links,
data selection or delivery rules. Composition through the existing `emailFrame`
is idempotent, so nested renderers show the disclosure once. Customer emails
continue to identify and provide contact details for the customer's own business;
Haani is identified as the Workloop platform operator, not their service provider.

The updated renderer families are booking confirmations/reminders, customer
events, account welcome/deletion/journeys, contextual owner emails, waitlist
welcome, learning-series emails, internal operations and prepared exceptions.
All 13 static Auth templates have the same HTML footer. The offline
`scripts/email/sync_operator_templates.mjs --check` checks parity with the shared
footer. The catalogue/review scripts include both operations variants and render
readable Auth text companions for review; those companions are not a claim about
Supabase Auth's delivered MIME format.

No schema, triggers, consent, email activation flags, payment reconciliation,
provider credentials or connected-merchant identities were changed.

## Production rollout verified

Deployment was explicitly authorised after review of isolated live-source
bundles. The checkout contains other pending work, so it was **not deployed
wholesale**. Each approved bundle started from its exact downloaded live source;
only renderer wrappers and the shared disclosure were added. Entrypoints, JWT
settings, import maps, push/SMS helpers and business-contact helpers were preserved.

| Function | Previous version | Verified deployed version |
| --- | ---: | ---: |
| `drain-booking-confirmation-emails` | 30 | 31 |
| `confirm-booking-request` | 18 | 19 |
| `join-waitlist` | 15 | 16 |
| `learning-series` | 5 | 6 |

All **34 downloaded runtime files** match the approved payload byte for byte.
Three unmodified type-only support files in the waitlist preparation are omitted
by its deployed runtime bundle, as expected. Existing local source refinements
were deliberately excluded from this content-only rollout.

The separate Auth Management API update patched exactly **13 HTML content
fields**, after comparing a fresh hosted baseline with the reviewed templates.
Re-reading the configuration verified all 13 expected hashes and **230 other
configuration fields unchanged**, including subjects, SMTP, OAuth/URLs and all
seven enabled security-notification flags. No sample emails were sent.

## Validation and evidence

- **40 focused Deno tests passed**, including coverage of 89 non-Auth variants,
  the 13 Auth templates, preserved business contacts, original variables and
  idempotent composition.
- All four isolated entrypoints passed Deno typechecks; **107 staged live-renderer
  parity comparisons** passed, preserving original content outside the footer.
- The offline catalogue contains **102 templates**. Compared with the prior
  catalogue, the existing 100 subjects/HTML bodies and non-Auth plaintext retain
  their previous content outside the disclosure; two internal operations samples
  complete the catalogue. Prepared exception samples remain prepared, not newly
  activated automated messages.
- Four representative mobile previews at 390 × 844 were inspected: Auth,
  booking reminder, owner learning email and operations. There is no horizontal
  overflow and the operator disclosure appears once after the main message.
- Scoped `git diff --check` and static Auth-template parity checks passed.

Preview gallery:
`/Users/ismaeelsmiley/Documents/Workloop Launch/growth-2026-09/emails/operator-2026-09-06/index.html`.
Trigger guide is in the adjacent `operator-2026-09-06-review/TRIGGERS.md`.
Durable deployment receipts, per-file hashes, Auth configuration proof, test log
and the changed-file list are under
`/Users/ismaeelsmiley/Documents/Haani Enterprise Limited/2026-09-06-company-preservation/email-operator-rollout/`.

## Remaining boundaries

This verifies rendered source and live configuration, not a newly received
end-to-end email in a customer's inbox. No review/sample messages were sent.
Stripe-generated merchant receipts, support-mailbox signatures and provider
legal-account conversions are separate surfaces. This change must not be used
to overwrite a connected business's own legal identity. Future app/store uploads
and unrelated pending functions/migrations remain separate release steps.

Suggested commit: `Identify Haani Enterprise Limited in all Workloop email footers`.
