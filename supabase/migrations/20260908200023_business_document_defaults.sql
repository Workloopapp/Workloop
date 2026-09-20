-- Canonical defaults extend the existing tenant-owned settings row. Do not
-- backfill from historical documents: those are deliberately frozen snapshots.
-- Existing address, customer email/phone, payment terms and tax rate are reused.
alter table public.workspace_settings
  add column business_structure text
    check (business_structure in ('sole_trader', 'limited_company', 'other')),
  add column business_legal_name text
    check (char_length(business_legal_name) <= 200),
  add column business_company_number text
    check (char_length(business_company_number) <= 40),
  add column business_vat_number text
    check (char_length(business_vat_number) <= 40),
  add column default_payment_instructions text not null default ''
    check (char_length(default_payment_instructions) <= 3000),
  add column default_quote_validity_days integer not null default 30
    check (default_quote_validity_days between 1 and 365);

comment on column public.workspace_settings.business_legal_name is
  'Reviewed proprietor or registered legal business name for new document snapshots.';
comment on column public.workspace_settings.business_structure is
  'Owner-selected structure; null means not reviewed. Does not establish tax eligibility.';
comment on column public.workspace_settings.default_payment_instructions is
  'Customer-visible payment instructions copied into new documents; never account credentials.';
-- No new access path or elevated function. Existing workspace membership/MFA
-- RLS and existing settings grants protect all added columns.
