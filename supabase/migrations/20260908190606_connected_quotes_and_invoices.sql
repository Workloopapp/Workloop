-- Quotes and invoice drafts are deliberately outside the payment ledger.
-- Older mobile builds read every invoices row as money owed; only issuance
-- creates one ordinary invoice/line-item set in those existing tables.
create table public.business_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  contact_id uuid,
  appointment_id uuid,
  type text not null check (type in ('quote', 'invoice')),
  status text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'declined', 'paid', 'overdue', 'cancelled')),
  invoice_number text,
  issue_date date not null default current_date,
  due_date date,
  service_date date,
  subtotal numeric(14,2) not null default 0,
  tax_rate numeric not null default 0 check (tax_rate in (0, 5, 20)),
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notes text not null default '' check (length(notes) <= 5000),
  payment_instructions text not null default '' check (length(payment_instructions) <= 3000),
  business_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(business_snapshot) = 'object' and octet_length(business_snapshot::text) <= 12000),
  client_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(client_snapshot) = 'object' and octet_length(client_snapshot::text) <= 12000),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 0 and 100),
  revision integer not null default 1,
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  source_quote_id uuid,
  invoice_id uuid,
  unique(workspace_id, id),
  unique(workspace_id, invoice_number),
  unique(source_quote_id),
  unique(invoice_id),
  foreign key(workspace_id, contact_id) references public.contacts(workspace_id,id) on delete set null (contact_id),
  foreign key(workspace_id, appointment_id) references public.appointments(workspace_id,id) on delete set null (appointment_id),
  foreign key(workspace_id, source_quote_id) references public.business_documents(workspace_id,id),
  foreign key(workspace_id, invoice_id) references public.invoices(workspace_id,id),
  check ((issued_at is null and status = 'draft' and invoice_number is null and invoice_id is null)
    or (issued_at is not null and status <> 'draft' and invoice_number is not null)),
  check (type = 'invoice' or invoice_id is null),
  check (total >= 0 and subtotal >= 0 and tax_amount >= 0)
);
create index business_documents_workspace_created_idx on public.business_documents(workspace_id, created_at desc);
create index business_documents_contact_idx on public.business_documents(workspace_id, contact_id);
create index business_documents_appointment_idx on public.business_documents(workspace_id, appointment_id);
alter table public.business_documents enable row level security;
revoke all on public.business_documents from public, anon, authenticated;
grant select on public.business_documents to authenticated;
grant all on public.business_documents to service_role;
create policy business_documents_member_read on public.business_documents for select to authenticated
  using (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy());

alter table public.invoices add column source_document_id uuid;
alter table public.invoices add constraint invoices_source_document_fk
  foreign key(workspace_id, source_document_id) references public.business_documents(workspace_id,id);
create unique index invoices_source_document_unique_idx on public.invoices(source_document_id) where source_document_id is not null;
create index invoices_workspace_source_document_idx on public.invoices(workspace_id, source_document_id) where source_document_id is not null;

create table app_private.business_document_counters (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  type text not null check (type in ('quote', 'invoice')),
  last_number bigint not null default 0,
  primary key(workspace_id, type)
);
create table app_private.business_document_manual_payments (
  document_id uuid not null references public.business_documents(id) on delete cascade,
  idempotency_key text not null check (length(idempotency_key) between 16 and 128),
  amount numeric(14,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  primary key(document_id, idempotency_key)
);
alter table app_private.business_document_counters enable row level security;
alter table app_private.business_document_manual_payments enable row level security;
revoke all on app_private.business_document_counters, app_private.business_document_manual_payments from public, anon, authenticated;
grant all on app_private.business_document_counters, app_private.business_document_manual_payments to service_role;

-- Issued commercial content is fixed. Existing payment writers retain their
-- supported amount/status fields, while legacy PAY records retain behaviour.
create function app_private.guard_issued_business_invoice()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.source_document_id is not null and current_user in ('authenticated', 'anon') then
      raise exception 'Issue invoices through the document workflow' using errcode = '42501';
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if old.source_document_id is not null and exists(select 1 from public.workspaces where id=old.workspace_id) then
      raise exception 'Issued invoices must be retained; cancel an unpaid invoice instead';
    end if;
    return old;
  end if;
  if old.source_document_id is not null or new.source_document_id is not null then
    if (to_jsonb(new) - array['amount_paid','stripe_amount_paid','income_recorded_at','status','contact_id','appointment_id'])
       is distinct from (to_jsonb(old) - array['amount_paid','stripe_amount_paid','income_recorded_at','status','contact_id','appointment_id'])
       or (new.contact_id is distinct from old.contact_id and new.contact_id is not null)
       or (new.appointment_id is distinct from old.appointment_id and new.appointment_id is not null) then
      raise exception 'Issued invoice details cannot be changed';
    end if;
    if new.amount_paid < 0 or new.amount_paid > new.total or new.amount_paid <> round(new.amount_paid,2) then raise exception 'Payment must be within the invoice total and use at most two decimal places'; end if;
    if new.status not in ('sent','paid','overdue','cancelled') then raise exception 'Invalid issued invoice status'; end if;
    if new.status = 'cancelled' and new.amount_paid > 0 then raise exception 'An invoice with payments cannot be cancelled'; end if;
    if new.status = 'paid' and new.amount_paid < new.total then raise exception 'Paid invoices must have no outstanding balance'; end if;
    if old.status = 'cancelled' and new.status <> 'cancelled' then raise exception 'Cancelled invoices cannot be reopened'; end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_issued_business_invoice() from public,anon,authenticated;
create trigger guard_issued_business_invoice before insert or update or delete on public.invoices
  for each row execute function app_private.guard_issued_business_invoice();

create function app_private.guard_issued_business_invoice_items()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op in ('UPDATE','DELETE') and exists(select 1 from public.invoices where id=old.invoice_id and source_document_id is not null) then
    raise exception 'Issued invoice items cannot be changed';
  end if;
  if tg_op in ('INSERT','UPDATE') and current_user in ('authenticated','anon')
    and exists(select 1 from public.invoices where id=new.invoice_id and source_document_id is not null) then
    raise exception 'Issued invoice items cannot be changed';
  end if;
  if tg_op in ('INSERT','UPDATE') and exists(select 1 from public.invoices i join public.business_documents d
    on d.id=i.source_document_id where i.id=new.invoice_id and d.issued_at is not null) then
    raise exception 'Issued invoice items cannot be changed';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function app_private.guard_issued_business_invoice_items() from public,anon,authenticated;
create trigger guard_issued_business_invoice_items before insert or update or delete on public.invoice_line_items
  for each row execute function app_private.guard_issued_business_invoice_items();

create function app_private.sync_business_document_payment_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source_document_id is not null then
    update public.business_documents set status=new.status where id=new.source_document_id and workspace_id=new.workspace_id;
  end if;
  return new;
end;
$$;
revoke all on function app_private.sync_business_document_payment_state() from public,anon,authenticated;
create trigger sync_business_document_payment_state after update of status on public.invoices
  for each row when (new.status is distinct from old.status) execute function app_private.sync_business_document_payment_state();

-- The only document writer is private and explicitly verifies current Auth
-- membership. Public invoker wrappers expose narrowly named operations.
create function app_private.business_document_action(
  p_workspace_id uuid, p_action text, p_document_id uuid,
  p_document jsonb default '{}'::jsonb, p_items jsonb default '[]'::jsonb,
  p_expected_revision integer default null, p_value text default null,
  p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
<<document_action>>
declare
  d public.business_documents%rowtype;
  source public.business_documents%rowtype;
  inv public.invoices%rowtype;
  item jsonb;
  clean_items jsonb := '[]'::jsonb;
  qty numeric;
  price numeric;
  line_amount numeric;
  subtotal numeric := 0;
  tax_rate numeric;
  tax_amount numeric;
  allocated bigint;
  prefix text;
  doc_number text;
  item_position integer := 0;
  payment_amount numeric;
  previous_amount numeric;
  desired_content jsonb;
  saved_content jsonb;
  business_date date;
begin
  if auth.uid() is null or not app_private.is_workspace_member(p_workspace_id)
    or not app_private.current_user_meets_mfa_policy() then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;
  -- Serialises document creation/number allocation/conversion for this solo
  -- workspace, including two devices retrying a not-yet-created UUID.
  perform 1 from public.workspaces where id=p_workspace_id for no key update;
  if p_document_id is not null then
    -- Match the provider writer's invoice -> document lock order. Draft issue
    -- inserts a new invoice which cannot be visible to a competing writer.
    select * into d from public.business_documents where id=p_document_id and workspace_id=p_workspace_id;
    if d.invoice_id is not null then
      perform 1 from public.invoices where id=d.invoice_id and workspace_id=p_workspace_id for update;
    end if;
    select * into d from public.business_documents where id=p_document_id and workspace_id=p_workspace_id for update;
  end if;
  if p_action = 'save' then
    if jsonb_typeof(p_document) is distinct from 'object' or jsonb_typeof(p_items) is distinct from 'array'
      or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Add between 1 and 100 invoice items'; end if;
    if d.id is not null and (d.status <> 'draft' or d.issued_at is not null) then raise exception 'Issued documents cannot be edited'; end if;
    if d.id is null and p_expected_revision is not null then raise exception 'Document was not found'; end if;
    if p_document->>'type' not in ('quote','invoice') or p_document->>'type' is null then raise exception 'Choose quote or invoice'; end if;
    if jsonb_typeof(p_document->'business_snapshot') is distinct from 'object' or jsonb_typeof(p_document->'client_snapshot') is distinct from 'object' then raise exception 'Add business and client details'; end if;
    if exists(select 1 from (select value from jsonb_each(p_document->'business_snapshot') union all select value from jsonb_each(p_document->'client_snapshot')) snapshot_values
      where jsonb_typeof(value) not in ('string','null') or length(value#>>'{}')>2000) then
      raise exception 'Business and client details must be text of up to 2000 characters each';
    end if;
    if d.source_quote_id is not null and p_document->>'type' <> 'invoice' then raise exception 'A converted quote must remain an invoice'; end if;
    tax_rate := coalesce(nullif(p_document->>'tax_rate','')::numeric,0);
    if tax_rate not in (0,5,20) then raise exception 'Choose a VAT rate of 0, 5 or 20 percent'; end if;
    for item in select value from jsonb_array_elements(p_items) loop
      if jsonb_typeof(item) is distinct from 'object' or coalesce(length(btrim(item->>'description')),0) not between 1 and 500 then raise exception 'Each item needs a description of up to 500 characters'; end if;
      if coalesce(item->>'quantity','') !~ '^[0-9]{1,7}(\.[0-9]{1,2})?$'
        or coalesce(item->>'unit_price','') !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' then raise exception 'Use positive quantities and prices with at most two decimal places'; end if;
      qty := (item->>'quantity')::numeric;
      price := (item->>'unit_price')::numeric;
      if qty <= 0 or qty > 100000 or price < 0 or price > 1000000 then raise exception 'Item quantity or price is outside supported limits'; end if;
      line_amount := round(qty*price,2);
      subtotal := subtotal+line_amount;
      clean_items := clean_items || jsonb_build_array(jsonb_build_object('description',btrim(item->>'description'),'quantity',qty,'unit_price',price,'line_total',line_amount,'position',item_position));
      item_position := item_position+1;
    end loop;
    if subtotal > 100000000 then raise exception 'Document total is outside supported limits'; end if;
    tax_amount := round(subtotal*tax_rate/100,2);
    if nullif(p_document->>'contact_id','') is not null and not exists(select 1 from public.contacts where id=(p_document->>'contact_id')::uuid and workspace_id=p_workspace_id) then raise exception 'Client was not found in this business'; end if;
    if nullif(p_document->>'appointment_id','') is not null and not exists(select 1 from public.appointments where id=(p_document->>'appointment_id')::uuid and workspace_id=p_workspace_id) then raise exception 'Booking was not found in this business'; end if;
    desired_content := jsonb_build_object(
      'type',p_document->>'type','contact_id',nullif(p_document->>'contact_id','')::uuid,
      'appointment_id',nullif(p_document->>'appointment_id','')::uuid,
      'issue_date',coalesce(nullif(p_document->>'issue_date','')::date,current_date),
      'due_date',nullif(p_document->>'due_date','')::date,'service_date',nullif(p_document->>'service_date','')::date,
      'subtotal',subtotal,'tax_rate',tax_rate,'tax_amount',tax_amount,'total',subtotal+tax_amount,
      'notes',coalesce(p_document->>'notes',''),'payment_instructions',coalesce(p_document->>'payment_instructions',''),
      'business_snapshot',p_document->'business_snapshot','client_snapshot',p_document->'client_snapshot','items',clean_items);
    if d.id is not null then
      saved_content := to_jsonb(d)-array['id','workspace_id','status','invoice_number','revision','issued_at','created_at','source_quote_id','invoice_id'];
      if p_expected_revision is null then
        if saved_content is distinct from desired_content then
          raise exception 'This draft was already saved. Reopen it before editing.';
        end if;
        return to_jsonb(d) || jsonb_build_object('amount_paid',0);
      elsif d.revision <> p_expected_revision then
        if d.revision=p_expected_revision+1 and saved_content=desired_content then
          return to_jsonb(d) || jsonb_build_object('amount_paid',0);
        end if;
        raise exception 'This document changed on another device. Refresh before saving';
      end if;
    end if;
    if d.id is null then
      insert into public.business_documents(id,workspace_id,type)
      values(coalesce(p_document_id,gen_random_uuid()),p_workspace_id,p_document->>'type') returning * into d;
    end if;
    update public.business_documents set
      type=p_document->>'type',
      contact_id=nullif(p_document->>'contact_id','')::uuid,
      appointment_id=nullif(p_document->>'appointment_id','')::uuid,
      issue_date=coalesce(nullif(p_document->>'issue_date','')::date,current_date),
      due_date=nullif(p_document->>'due_date','')::date,
      service_date=nullif(p_document->>'service_date','')::date,
      subtotal=document_action.subtotal, tax_rate=document_action.tax_rate,
      tax_amount=document_action.tax_amount,total=document_action.subtotal+document_action.tax_amount,
      notes=coalesce(p_document->>'notes',''),payment_instructions=coalesce(p_document->>'payment_instructions',''),
      business_snapshot=coalesce(p_document->'business_snapshot','{}'::jsonb),
      client_snapshot=coalesce(p_document->'client_snapshot','{}'::jsonb),items=clean_items,
      revision=case when p_expected_revision is null then 1 else revision+1 end
      where id=d.id returning * into d;
  else
    if d.id is null then raise exception 'Document was not found'; end if;
    if p_action = 'issue' then
      if d.issued_at is not null then
        return to_jsonb(d) || jsonb_build_object('amount_paid',coalesce((select amount_paid from public.invoices where id=d.invoice_id),0));
      end if;
      if p_expected_revision is not null and p_expected_revision <> d.revision then raise exception 'This document changed on another device. Refresh before issuing'; end if;
      if d.status <> 'draft' or d.total <= 0 or jsonb_array_length(d.items)=0 then raise exception 'Add items with a positive total before issuing'; end if;
      if coalesce(length(btrim(d.business_snapshot->>'name')),0)=0 or coalesce(length(btrim(d.business_snapshot->>'address')),0)=0
        or coalesce(length(btrim(d.client_snapshot->>'name')),0)=0 or coalesce(length(btrim(d.client_snapshot->>'address')),0)=0 then
        raise exception 'Add business and client names and addresses before issuing';
      end if;
      if d.tax_rate > 0 and coalesce(length(btrim(d.business_snapshot->>'vat_number')),0)=0 then raise exception 'Add your VAT registration number before charging VAT'; end if;
      if d.type='invoice' and coalesce(length(btrim(d.business_snapshot->>'legal_name')),0)=0 then raise exception 'Add your legal business or sole trader name before issuing'; end if;
      if d.type='invoice' and d.service_date is null then raise exception 'Add the date the services or goods were supplied'; end if;
      if d.due_date is null or d.due_date < d.issue_date then raise exception 'Set a due date on or after the issue date'; end if;
      if d.type='invoice' and d.appointment_id is not null then
        perform 1 from public.appointments where id=d.appointment_id and workspace_id=p_workspace_id for update;
        if exists(select 1 from public.invoices where workspace_id=p_workspace_id and appointment_id=d.appointment_id and status not in ('cancelled','declined')) then
          raise exception 'This booking already has a payment record. Use the existing payment to avoid charging twice';
        end if;
      end if;
      prefix := case when d.type='quote' then 'QUO' else 'INV' end;
      if d.type='invoice' then
        select coalesce(nullif(btrim(invoice_prefix),''),'INV') into prefix from public.workspace_settings where workspace_id=p_workspace_id;
        prefix := coalesce(prefix,'INV');
        if prefix !~ '^[A-Za-z][A-Za-z0-9-]{0,11}$' then prefix := 'INV'; end if;
      end if;
      loop
        insert into app_private.business_document_counters(workspace_id,type,last_number) values(p_workspace_id,d.type,1)
          on conflict(workspace_id,type) do update set last_number=app_private.business_document_counters.last_number+1 returning last_number into allocated;
        doc_number := upper(prefix)||'-'||lpad(allocated::text,greatest(4,length(allocated::text)),'0');
        exit when not exists(select 1 from public.invoices where workspace_id=p_workspace_id and invoice_number=doc_number)
          and not exists(select 1 from public.business_documents where workspace_id=p_workspace_id and invoice_number=doc_number);
      end loop;
      if d.type='invoice' then
        insert into public.invoices(workspace_id,contact_id,appointment_id,invoice_number,type,status,issue_date,due_date,subtotal,tax_rate,tax_amount,total,amount_paid,notes,source_document_id)
        values(d.workspace_id,d.contact_id,d.appointment_id,doc_number,'invoice','sent',d.issue_date,d.due_date,d.subtotal,d.tax_rate,d.tax_amount,d.total,0,d.notes,d.id) returning * into inv;
        insert into public.invoice_line_items(workspace_id,invoice_id,description,quantity,unit_price,line_total,position)
          select d.workspace_id,inv.id,item_value->>'description',(item_value->>'quantity')::numeric,(item_value->>'unit_price')::numeric,(item_value->>'line_total')::numeric,(item_value->>'position')::integer
          from jsonb_array_elements(d.items) item_value;
      end if;
      update public.business_documents set invoice_number=doc_number,status='sent',issued_at=now(),invoice_id=inv.id,revision=revision+1 where id=d.id returning * into d;
    elsif p_action = 'quote_status' then
      if d.type <> 'quote' or d.issued_at is null or p_value not in ('accepted','declined') or p_value is null then raise exception 'Only issued quotes can be accepted or declined'; end if;
      if d.status not in ('sent',p_value) then raise exception 'This quote already has a recorded decision'; end if;
      if p_expected_revision is not null and p_expected_revision <> d.revision and d.status <> p_value then raise exception 'This quote changed on another device. Refresh first'; end if;
      update public.business_documents set status=p_value,revision=revision+case when status=p_value then 0 else 1 end where id=d.id returning * into d;
    elsif p_action = 'convert' then
      if d.type <> 'quote' or d.status <> 'accepted' then raise exception 'Accept the quote before creating an invoice'; end if;
      source := d;
      select * into d from public.business_documents where source_quote_id=source.id and workspace_id=p_workspace_id;
      if d.id is null then
        select (now() at time zone coalesce((
          select zone.name from public.workspace_settings settings
          join pg_catalog.pg_timezone_names zone on zone.name=settings.timezone
          where settings.workspace_id=p_workspace_id
        ),'Europe/London'))::date into business_date;
        insert into public.business_documents(workspace_id,contact_id,appointment_id,type,issue_date,due_date,service_date,subtotal,tax_rate,tax_amount,total,notes,payment_instructions,business_snapshot,client_snapshot,items,source_quote_id)
        values(source.workspace_id,source.contact_id,source.appointment_id,'invoice',business_date,business_date+coalesce((select default_payment_terms_days from public.workspace_settings where workspace_id=p_workspace_id),7),source.service_date,source.subtotal,source.tax_rate,source.tax_amount,source.total,source.notes,source.payment_instructions,source.business_snapshot,source.client_snapshot,source.items,source.id)
        returning * into d;
      end if;
    elsif p_action = 'delete' then
      if d.status <> 'draft' or d.issued_at is not null then raise exception 'Only drafts can be deleted'; end if;
      delete from public.business_documents where id=d.id;
      return jsonb_build_object('id',d.id,'deleted',true);
    elsif p_action = 'cancel' then
      if d.issued_at is null then raise exception 'Delete this draft instead'; end if;
      if d.status='cancelled' then return to_jsonb(d); end if;
      if exists(select 1 from public.business_documents where source_quote_id=d.id) then raise exception 'This quote already has an invoice'; end if;
      if d.invoice_id is not null then
        select * into inv from public.invoices where id=d.invoice_id and workspace_id=p_workspace_id for update;
        if inv.amount_paid > 0 then raise exception 'An invoice with payments cannot be cancelled'; end if;
        update public.invoices set status='cancelled' where id=inv.id;
      end if;
      update public.business_documents set status='cancelled',revision=revision+1 where id=d.id returning * into d;
    elsif p_action = 'payment' then
      if d.type <> 'invoice' or d.invoice_id is null then raise exception 'Issue an invoice before recording payment'; end if;
      if p_value is null or p_value !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' or length(coalesce(p_idempotency_key,'')) not between 16 and 128 then raise exception 'Use a positive payment amount and a unique payment key'; end if;
      payment_amount := p_value::numeric;
      select amount into previous_amount from app_private.business_document_manual_payments where document_id=d.id and idempotency_key=p_idempotency_key;
      if found then
        if previous_amount <> payment_amount then raise exception 'Payment key already used for a different amount'; end if;
      else
        select * into inv from public.invoices where id=d.invoice_id and workspace_id=p_workspace_id for update;
        if inv.status not in ('sent','overdue') or payment_amount <= 0 or payment_amount > inv.total-inv.amount_paid then raise exception 'Payment must not exceed the outstanding balance'; end if;
        insert into app_private.business_document_manual_payments(document_id,idempotency_key,amount) values(d.id,p_idempotency_key,payment_amount);
        update public.invoices set amount_paid=amount_paid+payment_amount,
          status=case when amount_paid+payment_amount=total then 'paid' else status end,
          income_recorded_at=coalesce(income_recorded_at,now()) where id=inv.id;
      end if;
      select * into d from public.business_documents where id=d.id;
    else raise exception 'Unknown document action';
    end if;
  end if;
  return to_jsonb(d) || jsonb_build_object('amount_paid',coalesce((select amount_paid from public.invoices where id=d.invoice_id),0));
end;
$$;
revoke all on function app_private.business_document_action(uuid,text,uuid,jsonb,jsonb,integer,text,text) from public,anon;
grant execute on function app_private.business_document_action(uuid,text,uuid,jsonb,jsonb,integer,text,text) to authenticated;

create function public.save_business_document(p_workspace_id uuid,p_document jsonb,p_items jsonb,p_document_id uuid default null,p_expected_revision integer default null)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'save',p_document_id,p_document,p_items,p_expected_revision); $$;
create function public.issue_business_document(p_workspace_id uuid,p_document_id uuid,p_expected_revision integer default null)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'issue',p_document_id,p_expected_revision=>p_expected_revision); $$;
create function public.set_quote_status(p_workspace_id uuid,p_document_id uuid,p_status text,p_expected_revision integer default null)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'quote_status',p_document_id,p_expected_revision=>p_expected_revision,p_value=>p_status); $$;
create function public.convert_quote_to_invoice(p_workspace_id uuid,p_document_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'convert',p_document_id); $$;
create function public.delete_business_document(p_workspace_id uuid,p_document_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'delete',p_document_id); $$;
create function public.cancel_business_document(p_workspace_id uuid,p_document_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'cancel',p_document_id); $$;
create function public.record_document_payment(p_workspace_id uuid,p_document_id uuid,p_amount numeric,p_idempotency_key text)
returns jsonb language sql security invoker set search_path='' as $$ select app_private.business_document_action(p_workspace_id,'payment',p_document_id,p_value=>p_amount::text,p_idempotency_key=>p_idempotency_key); $$;
revoke all on function public.save_business_document(uuid,jsonb,jsonb,uuid,integer),public.issue_business_document(uuid,uuid,integer),public.set_quote_status(uuid,uuid,text,integer),public.convert_quote_to_invoice(uuid,uuid),public.delete_business_document(uuid,uuid),public.cancel_business_document(uuid,uuid),public.record_document_payment(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.save_business_document(uuid,jsonb,jsonb,uuid,integer),public.issue_business_document(uuid,uuid,integer),public.set_quote_status(uuid,uuid,text,integer),public.convert_quote_to_invoice(uuid,uuid),public.delete_business_document(uuid,uuid),public.cancel_business_document(uuid,uuid),public.record_document_payment(uuid,uuid,numeric,text) to authenticated;

-- Receipt timing is derived from the existing authoritative balance changes.
-- Partial receipts/refunds therefore enter the period in which they happened,
-- while old PAY records keep their original income_recorded_at semantics.
create table public.business_document_receipts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  invoice_id uuid not null,
  amount numeric(14,2) not null check (amount <> 0),
  received_at timestamptz not null default now(),
  foreign key(workspace_id,invoice_id) references public.invoices(workspace_id,id) on delete cascade
);
create index business_document_receipts_invoice_idx on public.business_document_receipts(workspace_id,invoice_id);
create index business_document_receipts_received_idx on public.business_document_receipts(workspace_id,received_at);
alter table public.business_document_receipts enable row level security;
revoke all on public.business_document_receipts from public,anon,authenticated;
grant select on public.business_document_receipts to authenticated;
grant all on public.business_document_receipts to service_role;
create policy business_document_receipts_member_read on public.business_document_receipts for select to authenticated
  using (app_private.is_workspace_member(workspace_id) and app_private.current_user_meets_mfa_policy());
create function app_private.record_business_document_receipt()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.source_document_id is not null and new.amount_paid is distinct from old.amount_paid then
    insert into public.business_document_receipts(workspace_id,invoice_id,amount,received_at)
    values(new.workspace_id,new.id,new.amount_paid-old.amount_paid,now());
  end if;
  return new;
end;
$$;
revoke all on function app_private.record_business_document_receipt() from public,anon,authenticated;
create trigger record_business_document_receipt after update of amount_paid on public.invoices
  for each row execute function app_private.record_business_document_receipt();
