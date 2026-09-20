-- A successful provider collection and its owner notification commit together.
-- Keep the durable decision separate from the dismissible notification: retries,
-- a cleared inbox, or re-enabling preferences must never replay an old receipt.
create table app_private.stripe_payment_notification_receipts (
  transaction_id uuid primary key references public.payment_transactions(id)
    on delete cascade,
  notification_id uuid references public.notifications(id) on delete set null
    deferrable initially deferred,
  decision text not null check (decision in (
    'historical', 'queued', 'preferences_disabled', 'settlement_changed'
  )),
  processed_at timestamptz not null default now()
);
create index stripe_payment_notification_receipts_notification_idx
  on app_private.stripe_payment_notification_receipts(notification_id);
alter table app_private.stripe_payment_notification_receipts enable row level security;
revoke all on app_private.stripe_payment_notification_receipts
  from public, anon, authenticated, service_role;
grant select, insert, update on app_private.stripe_payment_notification_receipts
  to service_role;

-- Record the pre-migration baseline without inserting any owner alert or push.
-- Hold concurrent reconciliation writes until the trigger is installed in this
-- migration transaction; otherwise a success can slip past the baseline scan.
lock table public.payment_transactions in share row exclusive mode;
insert into app_private.stripe_payment_notification_receipts(transaction_id, decision)
select id, 'historical' from public.payment_transactions
where paid_at is not null or status in (
  'succeeded', 'partially_refunded', 'refunded', 'disputed'
);

create function app_private.notify_stripe_payment_received()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_notification_id uuid;
  v_decision text;
  v_allowed boolean;
  v_client_name text;
begin
  -- A failed or still-processing attempt can subsequently succeed. Do not
  -- consume its one receipt decision until an authoritative settled state.
  if new.status not in ('succeeded', 'partially_refunded', 'refunded', 'disputed') then
    return new;
  end if;
  -- The reconciler supplies paid_at and the current charge only after checking
  -- the provider's received amount, currency, workspace, invoice and live mode.
  if new.status = 'succeeded' and (
    new.paid_at is null or
    coalesce(new.stripe_payment_intent_id, '') !~ '^pi_[A-Za-z0-9_]+$' or
    coalesce(new.stripe_charge_id, '') !~ '^ch_[A-Za-z0-9_]+$'
  ) then
    return new;
  end if;
  if not exists (
    select 1 from public.workspace_payment_accounts account
    where account.workspace_id = new.workspace_id
      and account.stripe_account_id = new.stripe_account_id
  ) or not exists (
    select 1 from public.invoices invoice
    where invoice.id = new.invoice_id and invoice.workspace_id = new.workspace_id
  ) then
    return new;
  end if;

  select coalesce(preference.all_notifications, true)
         and coalesce(preference.payment_received, true)
    into v_allowed
    from public.notification_preferences preference
   where preference.workspace_id = new.workspace_id;
  v_allowed := coalesce(v_allowed, true);
  v_decision := case
    -- An out-of-order success event can first reveal a refund or dispute. Do
    -- not send a misleading "received" alert about an already reversed charge.
    when new.status <> 'succeeded' or new.amount_refunded_minor <> 0
      then 'settlement_changed'
    when not v_allowed then 'preferences_disabled'
    else 'queued'
  end;
  if v_decision = 'queued' then v_notification_id := gen_random_uuid(); end if;
  insert into app_private.stripe_payment_notification_receipts(
    transaction_id, notification_id, decision
  ) values (new.id, v_notification_id, v_decision)
  on conflict (transaction_id) do nothing;
  if not found or v_decision <> 'queued' then return new; end if;

  select nullif(btrim(contact.name), '') into v_client_name
    from public.invoices invoice
    left join public.contacts contact on contact.id = invoice.contact_id
      and contact.workspace_id = invoice.workspace_id
   where invoice.id = new.invoice_id and invoice.workspace_id = new.workspace_id;

  insert into public.notifications(id, workspace_id, type, title, body, deep_link, dedupe_key)
  values (
    v_notification_id, new.workspace_id, 'payment_received', 'Card payment received',
    '£' || trim(to_char(new.amount_minor::numeric / 100, 'FM999999990.00')) ||
      ' received' || case when v_client_name is not null then ' from ' || v_client_name else '' end ||
      ' by card.',
    '/payments/' || new.invoice_id::text,
    'stripe_payment_received:' || new.id::text
  );
  return new;
end;
$$;
revoke all on function app_private.notify_stripe_payment_received()
  from public, anon, authenticated;
grant execute on function app_private.notify_stripe_payment_received() to service_role;

-- PostgreSQL executes same-event row triggers alphabetically. This explicitly
-- follows sync_invoice_after_stripe_transaction, so the destination is current
-- before notification insertion and the existing push enqueue trigger.
create trigger zz_notify_stripe_payment_received
after insert or update of status, amount_minor, amount_refunded_minor, paid_at, stripe_charge_id
on public.payment_transactions
for each row execute function app_private.notify_stripe_payment_received();

create function app_private.guard_stripe_payment_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_invoice_id uuid;
  v_reserved boolean := starts_with(coalesce(new.dedupe_key, ''), 'stripe_payment_received:');
  v_uuid constant text := '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}';
begin
  if new.type <> 'payment_received' and not v_reserved then return new; end if;
  -- This private read must never make a foreign-workspace probe observable
  -- before the normal notifications INSERT RLS policy rejects the request.
  if current_setting('role', true) in ('anon', 'authenticated') and (
    auth.uid() is null or not app_private.is_workspace_member(new.workspace_id)
  ) then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;
  if v_reserved then
    if new.type <> 'payment_received' or
      current_setting('role', true) in ('anon', 'authenticated') or not exists (
      select 1 from app_private.stripe_payment_notification_receipts receipt
      join public.payment_transactions transaction on transaction.id = receipt.transaction_id
      where receipt.notification_id = new.id and receipt.decision = 'queued'
        and transaction.workspace_id = new.workspace_id
        and new.deep_link = '/payments/' || transaction.invoice_id::text
        and new.dedupe_key = 'stripe_payment_received:' || transaction.id::text
    ) then
      raise exception 'Provider payment notifications require a reconciled receipt'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Completing a booking or retrying "mark received" after a wholly-card-funded
  -- invoice is paid adds no new income. Preserve manual/mixed-payment alerts.
  if coalesce(new.deep_link, '') ~ ('^/payments/' || v_uuid || '$') then
    v_invoice_id := split_part(new.deep_link, '/', 3)::uuid;
    if exists (
      select 1 from public.invoices invoice
      where invoice.id = v_invoice_id and invoice.workspace_id = new.workspace_id
        and invoice.stripe_amount_paid > 0
        and invoice.amount_paid <= invoice.stripe_amount_paid
        and exists (
          select 1 from public.payment_transactions transaction
          join app_private.stripe_payment_notification_receipts receipt
            on receipt.transaction_id = transaction.id
          where transaction.invoice_id = invoice.id
            and transaction.workspace_id = invoice.workspace_id
        )
    ) then return null; end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_stripe_payment_notification()
  from public, anon, authenticated, service_role;

-- Route normalization precedes this guard; push is queued only AFTER insert.
create trigger zz_guard_stripe_payment_notification
before insert or update of type, deep_link, dedupe_key on public.notifications
for each row execute function app_private.guard_stripe_payment_notification();

comment on table app_private.stripe_payment_notification_receipts is
  'One durable owner-alert decision per settled Stripe transaction; no customer email or extra payment ledger.';
comment on function app_private.notify_stripe_payment_received() is
  'Service-role reconciliation queues one preference-aware exact-invoice owner alert after invoice synchronization.';
