-- One durable provider operation per invoice while collection is uncertain.
-- Only the authenticated Edge Function can reserve; client DML remains denied.
create table app_private.stripe_collection_reservations (
  invoice_id uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  idempotency_key text not null check (length(idempotency_key) between 16 and 128),
  collection_method text not null check (collection_method in ('payment_link', 'tap_to_pay')),
  amount_minor bigint not null check (amount_minor > 0),
  receipt_email text not null default '',
  created_at timestamptz not null default now(),
  unique(workspace_id, idempotency_key),
  foreign key(workspace_id, invoice_id) references public.invoices(workspace_id, id) on delete cascade
);
alter table app_private.stripe_collection_reservations enable row level security;
revoke all on app_private.stripe_collection_reservations from public, anon, authenticated;
grant select, insert, update, delete on app_private.stripe_collection_reservations to service_role;
create policy service_role_collection_reservations on app_private.stripe_collection_reservations
  to service_role using (true) with check (true);

create or replace function public.reserve_stripe_collection(
  p_workspace_id uuid, p_invoice_id uuid, p_user_id uuid,
  p_idempotency_key text, p_collection_method text,
  p_amount_minor bigint default null, p_receipt_email text default ''
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  invoice public.invoices%rowtype;
  reservation app_private.stripe_collection_reservations%rowtype;
  previous public.payment_transactions%rowtype;
  outstanding bigint;
  requested bigint;
begin
  if not exists(select 1 from public.workspace_members where workspace_id = p_workspace_id and user_id = p_user_id) then
    raise exception 'Workspace access denied';
  end if;
  if length(p_idempotency_key) not between 16 and 128 or p_collection_method not in ('payment_link', 'tap_to_pay') then
    raise exception 'Invalid collection request';
  end if;
  -- All competing devices lock this same row before choosing a provider key.
  select * into invoice from public.invoices where id = p_invoice_id and workspace_id = p_workspace_id for update;
  if not found then raise exception 'Payment record was not found'; end if;
  if invoice.type is distinct from 'invoice' or invoice.status in ('cancelled', 'declined') then
    raise exception 'This record cannot accept a card payment';
  end if;
  outstanding := greatest(0, round(invoice.total * 100) - round(invoice.amount_paid * 100));
  requested := coalesce(p_amount_minor, outstanding);
  if requested <= 0 or requested > outstanding then raise exception 'Amount must not exceed the outstanding balance'; end if;
  if requested < 30 then raise exception 'Card payments must be at least GBP 0.30. Record this payment manually'; end if;

  select * into previous from public.payment_transactions
    where workspace_id = p_workspace_id and idempotency_key = p_idempotency_key;
  if found and (previous.invoice_id <> p_invoice_id or previous.collection_method <> p_collection_method or previous.amount_minor <> requested) then
    raise exception 'Payment request key was already used';
  end if;
  if found and previous.status in ('cancelled', 'failed') then
    p_idempotency_key := gen_random_uuid()::text;
  elsif found and previous.status in ('succeeded', 'partially_refunded', 'refunded', 'disputed') then
    raise exception 'This payment operation is complete. Refresh the payment before trying again';
  end if;

  select * into reservation from app_private.stripe_collection_reservations where invoice_id = p_invoice_id;
  if found then
    select * into previous from public.payment_transactions where workspace_id = p_workspace_id and idempotency_key = reservation.idempotency_key;
    if not found and reservation.created_at < now() - interval '23 hours' then
      raise exception 'A previous payment attempt needs review in Stripe before retrying';
    end if;
    if found and previous.status in ('succeeded', 'partially_refunded', 'refunded', 'disputed', 'cancelled', 'failed') then
      delete from app_private.stripe_collection_reservations where invoice_id = p_invoice_id;
      reservation := null;
    end if;
  end if;
  if reservation.invoice_id is null then
    if (select count(*) from public.payment_transactions where invoice_id = p_invoice_id and status in ('pending', 'processing', 'requires_payment_method')) > 1 then
      raise exception 'Multiple payment attempts need review in Stripe before collecting again';
    end if;
    select * into previous from public.payment_transactions where invoice_id = p_invoice_id and status in ('pending', 'processing', 'requires_payment_method') limit 1;
    insert into app_private.stripe_collection_reservations(invoice_id, workspace_id, idempotency_key, collection_method, amount_minor, receipt_email)
    values(p_invoice_id, p_workspace_id,
      coalesce(previous.idempotency_key, p_idempotency_key),
      coalesce(previous.collection_method, p_collection_method),
      coalesce(previous.amount_minor, requested),
      coalesce(previous.metadata->>'receipt_email', p_receipt_email, ''))
    returning * into reservation;
  end if;
  if reservation.collection_method <> p_collection_method or reservation.amount_minor <> requested or reservation.receipt_email <> coalesce(p_receipt_email, '') then
    raise exception 'A payment is already in progress. Continue the existing payment or wait for it to close';
  end if;
  return jsonb_build_object('idempotencyKey', reservation.idempotency_key, 'amountMinor', reservation.amount_minor);
end;
$$;
revoke all on function public.reserve_stripe_collection(uuid, uuid, uuid, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.reserve_stripe_collection(uuid, uuid, uuid, text, text, bigint, text) to service_role;

-- A shared live payment link must not outlive a manual balance/total change.
-- Provider reconciliation uses service_role and remains the authoritative writer.
create or replace function app_private.guard_open_stripe_collection_invoice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if current_setting('role', true) = 'authenticated'
    and (new.total is distinct from old.total or new.amount_paid is distinct from old.amount_paid
      or (new.status = 'cancelled' and new.status is distinct from old.status))
    and exists (
      select 1 from app_private.stripe_collection_reservations reservation
      left join public.payment_transactions transaction
        on transaction.workspace_id = reservation.workspace_id
        and transaction.idempotency_key = reservation.idempotency_key
      where reservation.invoice_id = old.id
        and (transaction.id is null or transaction.status in ('pending', 'processing', 'requires_payment_method'))
    ) then
    raise exception 'A card payment is in progress. Wait for it to finish or close it in Stripe before changing the balance';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_open_stripe_collection_invoice() from public, anon, authenticated;
create trigger guard_open_stripe_collection_invoice
  before update of total, amount_paid, status on public.invoices
  for each row execute function app_private.guard_open_stripe_collection_invoice();
