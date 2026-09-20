-- A quote may be accepted after its proposed deposit date, or before an invoice
-- whose shorter payment terms end sooner. Clamp only a NEW invoice draft's
-- deposit date to its issue/final-due window. The owner can review that date
-- before issuing; the original quote and existing conversion retries are fixed.
-- No schema, grants, RLS, payment calculation or receipt behavior changes.

create or replace function app_private.business_document_action(
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
  business_zone text;
  deposit_type text;
  deposit_value numeric;
  deposit_amount numeric;
  deposit_due date;
  receipt_date date;
  receipt_time timestamptz;
  prior_receipt_time timestamptz;
  prior_receipt_date date;
  prices_include_vat boolean;
  line_vat numeric;
  extracted_vat numeric := 0;
  is_refund boolean;
  candidate_count integer;
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
  select coalesce((select timezone from public.workspace_settings where workspace_id=p_workspace_id),'Europe/London') into business_zone;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=business_zone) then business_zone := 'Europe/London'; end if;
  business_date := (now() at time zone business_zone)::date;
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
    if p_document ? 'prices_include_vat' and jsonb_typeof(p_document->'prices_include_vat')<>'boolean' then raise exception 'Choose whether prices include VAT'; end if;
    prices_include_vat := coalesce((p_document->>'prices_include_vat')::boolean,d.prices_include_vat,false);
    for item in select value from jsonb_array_elements(p_items) loop
      if jsonb_typeof(item) is distinct from 'object' or coalesce(length(btrim(item->>'description')),0) not between 1 and 500 then raise exception 'Each item needs a description of up to 500 characters'; end if;
      if coalesce(item->>'quantity','') !~ '^[0-9]{1,7}(\.[0-9]{1,2})?$'
        or coalesce(item->>'unit_price','') !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' then raise exception 'Use positive quantities and prices with at most two decimal places'; end if;
      qty := (item->>'quantity')::numeric;
      price := (item->>'unit_price')::numeric;
      if qty <= 0 or qty > 100000 or price < 0 or price > 1000000 then raise exception 'Item quantity or price is outside supported limits'; end if;
      line_amount := round(qty*price,2);
      line_vat := case when prices_include_vat then round(line_amount*tax_rate/(100+tax_rate),2) else 0 end;
      extracted_vat := extracted_vat+line_vat;
      subtotal := subtotal+line_amount-line_vat;
      clean_items := clean_items || jsonb_build_array(jsonb_build_object('description',btrim(item->>'description'),'quantity',qty,'unit_price',price,'line_total',line_amount,'position',item_position) || case when prices_include_vat then jsonb_build_object('net_line_total',line_amount-line_vat,'vat_amount',line_vat,'unit_price_ex_vat',round(price*100/(100+tax_rate),4)) else '{}'::jsonb end);
      item_position := item_position+1;
    end loop;
    if subtotal > 100000000 then raise exception 'Document total is outside supported limits'; end if;
    tax_amount := case when prices_include_vat then extracted_vat else round(subtotal*tax_rate/100,2) end;
    -- Omitted fields from older editors preserve a draft's requested deposit.
    deposit_type := coalesce(p_document->>'deposit_type',d.deposit_type,'none');
    if deposit_type not in ('none','fixed','percentage') then raise exception 'Choose a fixed amount or percentage deposit'; end if;
    if p_document ? 'deposit_value' and coalesce(p_document->>'deposit_value','') !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' then raise exception 'Use a deposit amount or percentage with at most two decimal places'; end if;
    deposit_value := coalesce((p_document->>'deposit_value')::numeric,d.deposit_value,0);
    deposit_due := case when p_document ? 'deposit_due_date' then nullif(p_document->>'deposit_due_date','')::date else d.deposit_due_date end;
    if deposit_type='none' then
      deposit_value := 0; deposit_amount := 0; deposit_due := null;
    else
      if deposit_value<=0 or (deposit_type='percentage' and deposit_value>100) then raise exception 'Deposit must be positive and no more than the invoice total'; end if;
      deposit_amount := case when deposit_type='fixed' then deposit_value else round((subtotal+tax_amount)*deposit_value/100,2) end;
      if deposit_amount<=0 or deposit_amount>subtotal+tax_amount then raise exception 'Deposit must be positive and no more than the invoice total'; end if;
    end if;
    if nullif(p_document->>'contact_id','') is not null and not exists(select 1 from public.contacts where id=(p_document->>'contact_id')::uuid and workspace_id=p_workspace_id) then raise exception 'Client was not found in this business'; end if;
    if nullif(p_document->>'appointment_id','') is not null and not exists(select 1 from public.appointments where id=(p_document->>'appointment_id')::uuid and workspace_id=p_workspace_id) then raise exception 'Booking was not found in this business'; end if;
    desired_content := jsonb_build_object(
      'type',p_document->>'type','contact_id',nullif(p_document->>'contact_id','')::uuid,
      'appointment_id',nullif(p_document->>'appointment_id','')::uuid,
      'issue_date',coalesce(nullif(p_document->>'issue_date','')::date,current_date),
      'due_date',nullif(p_document->>'due_date','')::date,'service_date',nullif(p_document->>'service_date','')::date,
      'subtotal',subtotal,'tax_rate',tax_rate,'tax_amount',tax_amount,'total',subtotal+tax_amount,
      'notes',coalesce(p_document->>'notes',''),'payment_instructions',coalesce(p_document->>'payment_instructions',''),
      'business_snapshot',p_document->'business_snapshot','client_snapshot',p_document->'client_snapshot','items',clean_items,
      'prices_include_vat',prices_include_vat,'deposit_type',deposit_type,'deposit_value',deposit_value,'deposit_amount',deposit_amount,'deposit_due_date',deposit_due);
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
      prices_include_vat=document_action.prices_include_vat,
      deposit_type=document_action.deposit_type,deposit_value=document_action.deposit_value,
      deposit_amount=document_action.deposit_amount,deposit_due_date=deposit_due,
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
      if d.type='invoice' and coalesce(nullif(btrim(d.business_snapshot->>'email'),''),nullif(btrim(d.business_snapshot->>'phone'),'')) is null then raise exception 'Add a business contact email or phone before issuing'; end if;
      if d.deposit_amount>0 and (d.deposit_due_date is null or d.deposit_due_date<d.issue_date or d.deposit_due_date>d.due_date) then raise exception 'Set the deposit due date between the issue date and final payment date'; end if;
      if d.type='invoice' and d.service_date is null then raise exception 'Add the date the services or goods were supplied'; end if;
      if d.due_date is null or d.due_date < d.issue_date then raise exception 'Set a due date on or after the issue date'; end if;
      if d.type='invoice' and d.appointment_id is not null then
        perform 1 from public.appointments where id=d.appointment_id and workspace_id=p_workspace_id for update;
        select count(*) into candidate_count from public.invoices where workspace_id=p_workspace_id and appointment_id=d.appointment_id and status not in ('cancelled','declined');
        if candidate_count>0 then
          select * into inv from public.invoices where workspace_id=p_workspace_id and appointment_id=d.appointment_id and status not in ('cancelled','declined') order by id limit 1 for update;
          if candidate_count<>1 or inv.source_document_id is not null or inv.status not in ('sent','overdue')
            or inv.amount_paid<>0 or inv.stripe_amount_paid<>0 or inv.total<>d.total or inv.contact_id is distinct from d.contact_id
            or exists(select 1 from public.payment_transactions where invoice_id=inv.id)
            or exists(select 1 from app_private.stripe_collection_reservations where invoice_id=inv.id) then
            raise exception 'This booking already has a payment record. Use the existing payment to avoid charging twice';
          end if;
          doc_number := inv.invoice_number;
        end if;
      end if;
      prefix := case when d.type='quote' then 'QUO' else 'INV' end;
      if d.type='invoice' then
        select coalesce(nullif(btrim(invoice_prefix),''),'INV') into prefix from public.workspace_settings where workspace_id=p_workspace_id;
        prefix := coalesce(prefix,'INV');
        if prefix !~ '^[A-Za-z][A-Za-z0-9-]{0,11}$' then prefix := 'INV'; end if;
      end if;
      if inv.id is null then
      loop
        insert into app_private.business_document_counters(workspace_id,type,last_number) values(p_workspace_id,d.type,1)
          on conflict(workspace_id,type) do update set last_number=app_private.business_document_counters.last_number+1 returning last_number into allocated;
        doc_number := upper(prefix)||'-'||lpad(allocated::text,greatest(4,length(allocated::text)),'0');
        exit when not exists(select 1 from public.invoices where workspace_id=p_workspace_id and invoice_number=doc_number)
          and not exists(select 1 from public.business_documents where workspace_id=p_workspace_id and invoice_number=doc_number);
      end loop;
      end if;
      if d.type='invoice' then
        if inv.id is null then
          insert into public.invoices(workspace_id,contact_id,appointment_id,invoice_number,type,status,issue_date,due_date,subtotal,tax_rate,tax_amount,total,amount_paid,notes,source_document_id,deposit_amount,deposit_due_date)
          values(d.workspace_id,d.contact_id,d.appointment_id,doc_number,'invoice','sent',d.issue_date,d.due_date,d.subtotal,d.tax_rate,d.tax_amount,d.total,0,d.notes,d.id,d.deposit_amount,d.deposit_due_date) returning * into inv;
        else
          -- An unpaid booking payment has not yet been issued as a document.
          -- Reuse its identity and number so the booking is never charged twice.
          delete from public.invoice_line_items where invoice_id=inv.id;
          update public.invoices set type='invoice',status='sent',issue_date=d.issue_date,due_date=d.due_date,
            subtotal=d.subtotal,tax_rate=d.tax_rate,tax_amount=d.tax_amount,notes=d.notes,
            source_document_id=d.id,deposit_amount=d.deposit_amount,deposit_due_date=d.deposit_due_date
            where id=inv.id returning * into inv;
        end if;
        insert into public.invoice_line_items(workspace_id,invoice_id,description,quantity,unit_price,line_total,position)
          select d.workspace_id,inv.id,item_value->>'description',(item_value->>'quantity')::numeric,coalesce(item_value->>'unit_price_ex_vat',item_value->>'unit_price')::numeric,coalesce(item_value->>'net_line_total',item_value->>'line_total')::numeric,(item_value->>'position')::integer
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
        insert into public.business_documents(workspace_id,contact_id,appointment_id,type,issue_date,due_date,service_date,subtotal,tax_rate,tax_amount,total,notes,payment_instructions,business_snapshot,client_snapshot,items,source_quote_id,prices_include_vat,deposit_type,deposit_value,deposit_amount,deposit_due_date)
        values(source.workspace_id,source.contact_id,source.appointment_id,'invoice',business_date,business_date+coalesce((select default_payment_terms_days from public.workspace_settings where workspace_id=p_workspace_id),7),source.service_date,source.subtotal,source.tax_rate,source.tax_amount,source.total,source.notes,source.payment_instructions,source.business_snapshot,source.client_snapshot,source.items,source.id,source.prices_include_vat,source.deposit_type,source.deposit_value,source.deposit_amount,
          case when source.deposit_amount > 0 then
            greatest(business_date, least(
              coalesce(source.deposit_due_date, business_date),
              business_date + coalesce((select default_payment_terms_days from public.workspace_settings where workspace_id=p_workspace_id),7)
            ))
          else null end)
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
    elsif p_action in ('payment','refund') then
      if d.type <> 'invoice' or d.invoice_id is null then raise exception 'Issue an invoice before recording payment'; end if;
      if p_value is null or p_value !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' or length(coalesce(p_idempotency_key,'')) not between 16 and 128 then raise exception 'Use a positive payment amount and a unique payment key'; end if;
      is_refund := p_action='refund';
      payment_amount := p_value::numeric * case when is_refund then -1 else 1 end;
      receipt_date := coalesce(nullif(p_document->>'received_date','')::date,business_date);
      select amount,received_at,received_date into previous_amount,prior_receipt_time,prior_receipt_date from app_private.business_document_manual_payments where document_id=d.id and idempotency_key=p_idempotency_key;
      if found then
        if previous_amount <> payment_amount then raise exception 'Payment key already used for a different amount'; end if;
        if p_document ? 'received_date' and coalesce(prior_receipt_date,(prior_receipt_time at time zone business_zone)::date)<>receipt_date then raise exception 'Payment key already used for a different date'; end if;
      else
        if receipt_date<date '2000-01-01' or receipt_date>business_date then raise exception 'Choose the actual received or refunded date, not a future date'; end if;
        receipt_time := case when receipt_date=business_date then now() else (receipt_date+time '12:00') at time zone business_zone end;
        select * into inv from public.invoices where id=d.invoice_id and workspace_id=p_workspace_id for update;
        if is_refund then
          if inv.status not in ('sent','overdue','paid') or payment_amount>=0 or -payment_amount>inv.amount_paid-inv.stripe_amount_paid then raise exception 'Refund must not exceed money received manually. Refund card payments through Stripe'; end if;
        elsif inv.status not in ('sent','overdue') or payment_amount <= 0 or payment_amount > inv.total-inv.amount_paid then
          raise exception 'Payment must not exceed the outstanding balance';
        end if;
        -- Private retry metadata reserves one receipt identity/date in this
        -- transaction. The balance trigger consumes it atomically. Clients
        -- cannot set this context, and provider writes continue to use now().
        insert into app_private.business_document_manual_payments(document_id,idempotency_key,amount,received_at,received_date,receipt_id,transaction_id,receipt_recorded)
          values(d.id,p_idempotency_key,payment_amount,receipt_time,receipt_date,gen_random_uuid(),txid_current(),false);
        update public.invoices set amount_paid=amount_paid+payment_amount,
          status=case when amount_paid+payment_amount=total then 'paid' when due_date<business_date then 'overdue' else 'sent' end,
          income_recorded_at=coalesce(income_recorded_at,receipt_time) where id=inv.id;
      end if;
      select * into d from public.business_documents where id=d.id;
    else raise exception 'Unknown document action';
    end if;
  end if;
  return to_jsonb(d) || jsonb_build_object('amount_paid',coalesce((select amount_paid from public.invoices where id=d.invoice_id),0));
end;
$$;
