-- Exact record routes are part of the saved notification, not inferred by the
-- client from its current screen. Preserve existing public APIs and delivery
-- preferences/session guards; change only routing values and safe recovery.
create function app_private.resolve_notification_entity_route(
  p_workspace_id uuid, p_type text, p_deep_link text, p_dedupe_key text
) returns text language plpgsql stable security invoker set search_path = '' as $$
declare
  v_id uuid;
  v_routes text[];
  v_uuid constant text := '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}';
begin
  -- Keep a saved exact route even if its record was later removed. The
  -- workspace-scoped client detail screen must present its unavailable state.
  if coalesce(p_deep_link,'') ~ ('^/(bookings|booking-requests|payments|tasks|notes)/' || v_uuid || '$') then
    return p_deep_link;
  end if;

  if p_type='booking_request' and coalesce(p_dedupe_key,'') ~ ('^booking_request_(waiting|received):' || v_uuid || '$') then
    v_id := split_part(p_dedupe_key,':',2)::uuid;
    if exists(select 1 from public.booking_requests where id=v_id and workspace_id=p_workspace_id) then
      return '/booking-requests/' || v_id::text;
    end if;
  elsif p_type='invoice_overdue' and coalesce(p_dedupe_key,'') ~ ('^invoice_overdue:' || v_uuid || '$') then
    v_id := split_part(p_dedupe_key,':',2)::uuid;
    if exists(select 1 from public.invoices where id=v_id and workspace_id=p_workspace_id) then
      return '/payments/' || v_id::text;
    end if;
  elsif p_type in ('task','task_due') and coalesce(p_dedupe_key,'') ~ ('^task_due:' || v_uuid || '$') then
    v_id := split_part(p_dedupe_key,':',2)::uuid;
    if exists(select 1 from public.tasks where id=v_id and workspace_id=p_workspace_id) then
      return '/tasks/' || v_id::text;
    end if;
  end if;

  if p_type in ('new_booking','booking') and starts_with(coalesce(p_dedupe_key,''),'workflow:create_booking:') then
    select array_agg(distinct case when appointment.id is not null
      then '/bookings/' || appointment.id::text end)
      into v_routes
      from app_private.workflow_idempotency workflow
      left join public.appointments appointment
        on appointment.id::text = workflow.result -> 'appointment_ids' ->> 0
       and appointment.workspace_id = p_workspace_id
     where workflow.workspace_id=p_workspace_id and workflow.operation='create_booking'
       and workflow.idempotency_key=substr(p_dedupe_key,length('workflow:create_booking:')+1);
  elsif p_type in ('payment_received','payment','invoice_overdue') and starts_with(coalesce(p_dedupe_key,''),'workflow:complete_booking:') then
    select array_agg(distinct case when invoice.id is not null
      then '/payments/' || invoice.id::text
      when nullif(workflow.result ->> 'invoice_id','') is null and appointment.id is not null
      then '/bookings/' || appointment.id::text end)
      into v_routes
      from app_private.workflow_idempotency workflow
      left join public.invoices invoice
        on invoice.id::text=workflow.result ->> 'invoice_id'
       and invoice.workspace_id=p_workspace_id
      left join public.appointments appointment
        on appointment.id::text=workflow.result ->> 'appointment_id'
       and appointment.workspace_id=p_workspace_id
     where workflow.workspace_id=p_workspace_id and workflow.operation='complete_booking'
       and workflow.idempotency_key=substr(p_dedupe_key,length('workflow:complete_booking:')+1);
  end if;
  -- The old dedupe key did not include user_id. A conflicting result from
  -- another member must not choose an arbitrary booking/payment.
  if cardinality(v_routes)=1 and v_routes[1] is not null then return v_routes[1]; end if;
  return p_deep_link;
end;
$$;
revoke all on function app_private.resolve_notification_entity_route(uuid,text,text,text)
  from public,anon,authenticated,service_role;

create or replace function app_private.route_notification_to_entity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_route text;
  v_uuid constant text := '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}';
begin
  v_route := app_private.resolve_notification_entity_route(
    new.workspace_id,new.type,new.deep_link,new.dedupe_key);
  if v_route is distinct from new.deep_link then
    new.deep_link := v_route;
    return new;
  end if;
  if coalesce(new.deep_link,'') ~ ('^/(bookings|booking-requests|payments|tasks|notes)/' || v_uuid || '$') then
    return new;
  end if;
  -- An explicit but invalid/ambiguous identifier must not be replaced by an
  -- unrelated row from the same transaction.
  if coalesce(new.dedupe_key,'') ~ '^(booking_request_(waiting|received)|invoice_overdue|task_due|workflow:create_booking|workflow:complete_booking):' then
    return new;
  end if;
  -- Legacy single-record producers may still be supported, but never select
  -- one of several rows touched by a batch. Never infer an old alert on UPDATE.
  if tg_op <> 'INSERT' then return new; end if;
  case new.type
    when 'booking_request' then
      select case when count(*)=1 then min(id::text)::uuid end into v_id
        from public.booking_requests where workspace_id=new.workspace_id
          and xmin::text=pg_current_xact_id()::text;
      if v_id is not null then new.deep_link := '/booking-requests/' || v_id::text; end if;
    when 'invoice_overdue','payment_received','payment' then
      select case when count(*)=1 then min(id::text)::uuid end into v_id
        from public.invoices where workspace_id=new.workspace_id
          and xmin::text=pg_current_xact_id()::text;
      if v_id is not null then new.deep_link := '/payments/' || v_id::text; end if;
    when 'new_booking','booking','no_show' then
      select case when count(*)=1 then min(id::text)::uuid end into v_id
        from public.appointments where workspace_id=new.workspace_id
          and xmin::text=pg_current_xact_id()::text;
      if v_id is not null then new.deep_link := '/bookings/' || v_id::text; end if;
    when 'task_due','task' then
      select case when count(*)=1 then min(id::text)::uuid end into v_id
        from public.tasks where workspace_id=new.workspace_id
          and xmin::text=pg_current_xact_id()::text;
      if v_id is not null then new.deep_link := '/tasks/' || v_id::text; end if;
    when 'note' then
      select case when count(*)=1 then min(id::text)::uuid end into v_id
        from public.notes where workspace_id=new.workspace_id
          and xmin::text=pg_current_xact_id()::text;
      if v_id is not null then new.deep_link := '/notes/' || v_id::text; end if;
    else null;
  end case;
  return new;
end;
$$;
revoke all on function app_private.route_notification_to_entity() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.complete_booking_workflow(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := auth.uid();
  v_workspace_id uuid;
  v_appointment_id uuid;
  v_linked_payment_id uuid;
  v_invoice_id uuid;
  v_contact_id uuid;
  v_idempotency_key text;
  v_payment_mode text;
  v_payment_date date;
  v_existing_result jsonb;
  v_appointment_status text;
  v_service_name text;
  v_client_name text;
  v_price numeric;
  v_invoice_total numeric;
  v_start timestamptz;
  v_notification_allowed boolean := true;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Completion payload must be an object'
      using errcode = '22023';
  end if;
  begin
    v_workspace_id := (p_payload ->> 'workspace_id')::uuid;
    v_appointment_id := (p_payload ->> 'appointment_id')::uuid;
    v_linked_payment_id := nullif(
      p_payload ->> 'linked_payment_id',
      ''
    )::uuid;
  exception when invalid_text_representation then
    raise exception 'A completion record identifier is invalid'
      using errcode = '22023';
  end;
  if not exists (
    select 1
      from public.workspace_members member
     where member.workspace_id = v_workspace_id
       and member.user_id = v_caller_id
  ) then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;

  v_idempotency_key := btrim(coalesce(p_payload ->> 'idempotency_key', ''));
  v_payment_mode := lower(btrim(coalesce(
    p_payload ->> 'payment_mode',
    'skip'
  )));
  if char_length(v_idempotency_key) not between 16 and 128
     or v_payment_mode not in (
       'skip',
       'paid',
       'unpaid',
       'linked_paid',
       'linked_unpaid'
     ) then
    raise exception 'Completion options are invalid' using errcode = '22023';
  end if;
  if v_payment_mode like 'linked_%' and v_linked_payment_id is null then
    raise exception 'A linked payment is required' using errcode = '22023';
  end if;

  insert into app_private.workflow_idempotency(
    workspace_id,
    user_id,
    operation,
    idempotency_key
  ) values (
    v_workspace_id,
    v_caller_id,
    'complete_booking',
    v_idempotency_key
  )
  on conflict (
    workspace_id,
    user_id,
    operation,
    idempotency_key
  ) do nothing;

  if not found then
    select request.result
      into v_existing_result
      from app_private.workflow_idempotency request
     where request.workspace_id = v_workspace_id
       and request.operation = 'complete_booking'
       and request.idempotency_key = v_idempotency_key
       and request.user_id = v_caller_id;
    if v_existing_result is null then
      raise exception 'Completion workflow is already in progress'
        using errcode = '40001';
    end if;
    return v_existing_result;
  end if;

  select
    appointment.contact_id,
    appointment.price,
    appointment.start_time,
    appointment.status,
    coalesce(service.name, appointment.title, 'Booking'),
    coalesce(contact.name, 'a client')
  into
    v_contact_id,
    v_price,
    v_start,
    v_appointment_status,
    v_service_name,
    v_client_name
  from public.appointments appointment
  left join public.services service
    on service.id = appointment.service_id
   and service.workspace_id = appointment.workspace_id
  left join public.contacts contact
    on contact.id = appointment.contact_id
   and contact.workspace_id = appointment.workspace_id
  where appointment.id = v_appointment_id
    and appointment.workspace_id = v_workspace_id
  for update of appointment;

  if not found then
    raise exception 'Booking was not found' using errcode = 'P0002';
  end if;
  if v_appointment_status in ('cancelled', 'no_show') then
    raise exception 'A cancelled booking cannot be completed'
      using errcode = '22023';
  end if;

  begin
    v_payment_date := coalesce(
      nullif(p_payload ->> 'payment_date', '')::date,
      (v_start at time zone 'UTC')::date
    );
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'Payment date is invalid' using errcode = '22023';
  end;

  update public.appointments
     set status = 'completed'
   where id = v_appointment_id
     and workspace_id = v_workspace_id;

  if v_linked_payment_id is not null then
    select invoice.id, invoice.total
      into v_invoice_id, v_invoice_total
      from public.invoices invoice
     where invoice.id = v_linked_payment_id
       and invoice.workspace_id = v_workspace_id
       and invoice.appointment_id = v_appointment_id
     for update;
    if not found then
      raise exception 'Linked payment was not found' using errcode = 'P0002';
    end if;
    if v_payment_mode = 'linked_paid' then
      update public.invoices
         set status = 'paid',
             amount_paid = total,
             income_recorded_at = coalesce(income_recorded_at, now())
       where id = v_invoice_id
         and workspace_id = v_workspace_id;
    end if;
  elsif v_payment_mode in ('paid', 'unpaid') and v_price > 0 then
    select invoice.id, invoice.total
      into v_invoice_id, v_invoice_total
      from public.invoices invoice
     where invoice.workspace_id = v_workspace_id
       and invoice.appointment_id = v_appointment_id
     order by invoice.created_at, invoice.id
     limit 1
     for update;

    if v_invoice_id is null then
      insert into public.invoices(
        workspace_id,
        contact_id,
        appointment_id,
        type,
        status,
        issue_date,
        due_date,
        subtotal,
        tax_rate,
        tax_amount,
        discount_value,
        total,
        amount_paid,
        income_recorded_at,
        notes
      ) values (
        v_workspace_id,
        v_contact_id,
        v_appointment_id,
        'invoice',
        case when v_payment_mode = 'paid' then 'paid' else 'sent' end,
        v_payment_date,
        v_payment_date,
        v_price,
        0,
        0,
        0,
        v_price,
        case when v_payment_mode = 'paid' then v_price else 0 end,
        case when v_payment_mode = 'paid' then now() else null end,
        case
          when v_payment_mode = 'paid'
            then 'Payment received for ' || v_service_name
          else 'Payment due for ' || v_service_name
        end
      )
      returning id into v_invoice_id;
      v_invoice_total := v_price;
    elsif v_payment_mode = 'paid' then
      update public.invoices
         set status = 'paid',
             amount_paid = total,
             income_recorded_at = coalesce(income_recorded_at, now())
       where id = v_invoice_id
         and workspace_id = v_workspace_id;
    end if;
  end if;

  if v_payment_mode in ('paid', 'linked_paid') then
    select coalesce(
      preference.all_notifications and preference.payment_received,
      true
    )
      into v_notification_allowed
      from public.notification_preferences preference
     where preference.workspace_id = v_workspace_id;
    if coalesce(v_notification_allowed, true) then
      insert into public.notifications(
        workspace_id,
        type,
        title,
        body,
        deep_link,
        dedupe_key
      ) values (
        v_workspace_id,
        'payment_received',
        'Payment received',
        '£' || trim(to_char(
          coalesce(v_invoice_total, v_price),
          'FM999999990.00'
        )) ||
          ' from ' || v_client_name || ' is now paid.',
        case when v_invoice_id is not null then '/payments/' || v_invoice_id::text
          else '/bookings/' || v_appointment_id::text end,
        'workflow:complete_booking:' || v_idempotency_key
      )
      on conflict (workspace_id, dedupe_key) do nothing;
    end if;
  elsif v_payment_mode = 'unpaid' then
    select coalesce(
      preference.all_notifications and preference.invoice_overdue,
      true
    )
      into v_notification_allowed
      from public.notification_preferences preference
     where preference.workspace_id = v_workspace_id;
    if coalesce(v_notification_allowed, true) then
      insert into public.notifications(
        workspace_id,
        type,
        title,
        body,
        deep_link,
        dedupe_key
      ) values (
        v_workspace_id,
        'invoice_overdue',
        'Payment pending',
        '£' || trim(to_char(
          coalesce(v_invoice_total, v_price),
          'FM999999990.00'
        )) ||
          ' is outstanding for ' || v_service_name || '.',
        case when v_invoice_id is not null then '/payments/' || v_invoice_id::text
          else '/bookings/' || v_appointment_id::text end,
        'workflow:complete_booking:' || v_idempotency_key
      )
      on conflict (workspace_id, dedupe_key) do nothing;
    end if;
  end if;

  v_existing_result := jsonb_build_object(
    'appointment_id',
    v_appointment_id,
    'invoice_id',
    v_invoice_id,
    'status',
    'completed'
  );
  update app_private.workflow_idempotency request
     set result = v_existing_result
   where request.workspace_id = v_workspace_id
     and request.operation = 'complete_booking'
     and request.idempotency_key = v_idempotency_key
     and request.user_id = v_caller_id;
  return v_existing_result;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.create_booking_workflow_without_confirmation_email(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := auth.uid();
  v_workspace_id uuid;
  v_contact_id uuid;
  v_service_id uuid;
  v_request_id uuid;
  v_idempotency_key text;
  v_existing_result jsonb;
  v_appointments jsonb;
  v_occurrence jsonb;
  v_new_contact jsonb;
  v_task_title text;
  v_task_due_date date;
  v_title text;
  v_notes text;
  v_location text;
  v_recurrence_rule text;
  v_notification_title text;
  v_notification_body text;
  v_payment_note text;
  v_start timestamptz;
  v_end timestamptz;
  v_payment_date date;
  v_price numeric;
  v_appointment_id uuid;
  v_parent_id uuid;
  v_appointment_ids uuid[] := '{}'::uuid[];
  v_create_payment boolean;
  v_reuse_contact boolean;
  v_notification_allowed boolean := true;
  v_request_status text;
  v_allow_overlap boolean;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Booking payload must be an object'
      using errcode = '22023';
  end if;

  begin
    v_workspace_id := (p_payload ->> 'workspace_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'A valid workspace is required' using errcode = '22023';
  end;
  if not exists (
    select 1
      from public.workspace_members member
     where member.workspace_id = v_workspace_id
       and member.user_id = v_caller_id
  ) then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;

  v_idempotency_key := btrim(coalesce(p_payload ->> 'idempotency_key', ''));
  if char_length(v_idempotency_key) not between 16 and 128 then
    raise exception 'A valid idempotency key is required'
      using errcode = '22023';
  end if;

  insert into app_private.workflow_idempotency(
    workspace_id,
    user_id,
    operation,
    idempotency_key
  ) values (
    v_workspace_id,
    v_caller_id,
    'create_booking',
    v_idempotency_key
  )
  on conflict (
    workspace_id,
    user_id,
    operation,
    idempotency_key
  ) do nothing;

  if not found then
    select request.result
      into v_existing_result
      from app_private.workflow_idempotency request
     where request.workspace_id = v_workspace_id
       and request.operation = 'create_booking'
       and request.idempotency_key = v_idempotency_key
       and request.user_id = v_caller_id;
    if v_existing_result is null then
      raise exception 'Booking workflow is already in progress'
        using errcode = '40001';
    end if;
    return v_existing_result;
  end if;

  -- Serialize schedule and contact writes for one workspace.
  perform pg_advisory_xact_lock(
    hashtextextended(v_workspace_id::text, 882001)
  );

  v_appointments := p_payload -> 'appointments';
  if v_appointments is null or jsonb_typeof(v_appointments) <> 'array' then
    raise exception 'Appointments must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(v_appointments) not between 1 and 24 then
    raise exception 'A workflow must contain between 1 and 24 appointments'
      using errcode = '22023';
  end if;

  begin
    v_contact_id := nullif(p_payload ->> 'contact_id', '')::uuid;
    v_service_id := nullif(p_payload ->> 'service_id', '')::uuid;
    v_request_id := nullif(p_payload ->> 'booking_request_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'A linked record identifier is invalid'
      using errcode = '22023';
  end;

  if v_request_id is not null then
    select request.status
      into v_request_status
      from public.booking_requests request
     where request.id = v_request_id
       and request.workspace_id = v_workspace_id
     for update;
    if not found then
      raise exception 'Booking request was not found' using errcode = 'P0002';
    end if;
    if v_request_status not in ('pending', 'contacted') then
      raise exception 'Booking request can no longer be confirmed'
        using errcode = '23505';
    end if;
  end if;

  if v_service_id is not null and not exists (
    select 1
      from public.services service
     where service.id = v_service_id
       and service.workspace_id = v_workspace_id
  ) then
    raise exception 'Service does not belong to this workspace'
      using errcode = '23503';
  end if;

  if v_contact_id is not null then
    if not exists (
      select 1
        from public.contacts contact
       where contact.id = v_contact_id
         and contact.workspace_id = v_workspace_id
    ) then
      raise exception 'Client does not belong to this workspace'
        using errcode = '23503';
    end if;
  else
    v_new_contact := p_payload -> 'new_contact';
    if v_new_contact is null or jsonb_typeof(v_new_contact) <> 'object' then
      raise exception 'A new client is required' using errcode = '22023';
    end if;
    if char_length(btrim(coalesce(v_new_contact ->> 'name', '')))
       not between 1 and 200
       or char_length(coalesce(v_new_contact ->> 'phone', '')) > 64
       or char_length(coalesce(v_new_contact ->> 'email', '')) > 320
       or char_length(coalesce(v_new_contact ->> 'address', '')) > 1000
       or char_length(coalesce(v_new_contact ->> 'notes', '')) > 10000 then
      raise exception 'New client details are invalid' using errcode = '22023';
    end if;

    v_reuse_contact := coalesce(
      (p_payload ->> 'reuse_contact_by_phone')::boolean,
      false
    );
    if v_reuse_contact
       and nullif(btrim(coalesce(v_new_contact ->> 'phone', '')), '') is not null
    then
      select contact.id
        into v_contact_id
        from public.contacts contact
       where contact.workspace_id = v_workspace_id
         and (
           contact.phone = btrim(v_new_contact ->> 'phone')
           or (
             char_length(regexp_replace(
               coalesce(v_new_contact ->> 'phone', ''),
               '[^0-9]',
               '',
               'g'
             )) >= 7
             and regexp_replace(
               coalesce(contact.phone, ''),
               '[^0-9]',
               '',
               'g'
             ) = regexp_replace(
               coalesce(v_new_contact ->> 'phone', ''),
               '[^0-9]',
               '',
               'g'
             )
           )
         )
       order by contact.created_at, contact.id
       limit 1
       for update;
    end if;

    if v_contact_id is null then
      insert into public.contacts(
        workspace_id,
        name,
        phone,
        email,
        address,
        notes,
        status,
        preferred_contact_method,
        last_activity_at
      ) values (
        v_workspace_id,
        btrim(v_new_contact ->> 'name'),
        nullif(btrim(coalesce(v_new_contact ->> 'phone', '')), ''),
        nullif(btrim(coalesce(v_new_contact ->> 'email', '')), ''),
        nullif(btrim(coalesce(v_new_contact ->> 'address', '')), ''),
        nullif(btrim(coalesce(v_new_contact ->> 'notes', '')), ''),
        'active',
        case
          when nullif(btrim(coalesce(v_new_contact ->> 'phone', '')), '')
            is not null then 'phone'
          when nullif(btrim(coalesce(v_new_contact ->> 'email', '')), '')
            is not null then 'email'
          else 'phone'
        end,
        now()
      )
      returning id into v_contact_id;
    end if;
  end if;

  v_title := btrim(coalesce(p_payload ->> 'title', 'Booking'));
  v_notes := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  v_location := nullif(btrim(coalesce(p_payload ->> 'location', '')), '');
  v_recurrence_rule := nullif(
    btrim(coalesce(p_payload ->> 'recurrence_rule', '')),
    ''
  );
  v_notification_title := btrim(
    coalesce(p_payload ->> 'notification_title', 'New booking created')
  );
  v_notification_body := btrim(
    coalesce(
      p_payload ->> 'notification_body',
      'A booking was added to your schedule.'
    )
  );
  v_payment_note := nullif(
    btrim(coalesce(p_payload ->> 'payment_note', '')),
    ''
  );
  v_create_payment := coalesce(
    (p_payload ->> 'create_payment_due')::boolean,
    false
  );
  v_allow_overlap := coalesce(
    (p_payload ->> 'allow_overlap')::boolean,
    false
  );

  begin
    v_price := (p_payload ->> 'price')::numeric;
    v_task_due_date := nullif(p_payload ->> 'task_due_date', '')::date;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Booking amount or task date is invalid'
      using errcode = '22023';
  end;

  if char_length(v_title) not between 1 and 200
     or char_length(coalesce(v_notes, '')) > 10000
     or char_length(coalesce(v_location, '')) > 1000
     or char_length(v_notification_title) not between 1 and 200
     or char_length(v_notification_body) not between 1 and 1000
     or v_price is null
     or v_price::text = 'NaN'
     or v_price < 0
     or v_price > 1000000
     or (
       v_recurrence_rule is not null
       and v_recurrence_rule not in (
         'FREQ=WEEKLY;INTERVAL=1',
         'FREQ=WEEKLY;INTERVAL=2',
         'FREQ=MONTHLY;INTERVAL=1'
       )
     ) then
    raise exception 'Booking details are outside allowed bounds'
      using errcode = '22023';
  end if;

  for v_occurrence in
    select value from jsonb_array_elements(v_appointments)
  loop
    if jsonb_typeof(v_occurrence) <> 'object' then
      raise exception 'An appointment entry is invalid'
        using errcode = '22023';
    end if;
    begin
      v_start := (v_occurrence ->> 'start_time')::timestamptz;
      v_end := (v_occurrence ->> 'end_time')::timestamptz;
      v_payment_date := coalesce(
        nullif(v_occurrence ->> 'payment_date', '')::date,
        (v_start at time zone 'UTC')::date
      );
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'An appointment date is invalid' using errcode = '22023';
    end;

    if v_start is null
       or v_end is null
       or v_end <= v_start
       or v_end - v_start > interval '24 hours'
       or v_start < now() - interval '5 years'
       or v_start > now() + interval '5 years' then
      raise exception 'Appointment timing is outside allowed bounds'
        using errcode = '22023';
    end if;

    if not v_allow_overlap and exists (
      select 1
        from public.appointments appointment
       where appointment.workspace_id = v_workspace_id
         and appointment.status not in ('cancelled', 'no_show')
         and appointment.start_time < v_end
         and appointment.end_time > v_start
    ) then
      raise exception 'Appointment overlaps an existing booking'
        using errcode = '23P01';
    end if;

    v_appointment_id := gen_random_uuid();
    insert into public.appointments(
      id,
      workspace_id,
      contact_id,
      service_id,
      title,
      start_time,
      end_time,
      price,
      status,
      notes,
      location,
      recurrence_rule,
      recurrence_parent_id
    ) values (
      v_appointment_id,
      v_workspace_id,
      v_contact_id,
      v_service_id,
      v_title,
      v_start,
      v_end,
      v_price,
      'scheduled',
      v_notes,
      v_location,
      v_recurrence_rule,
      v_parent_id
    );
    if v_parent_id is null and jsonb_array_length(v_appointments) > 1 then
      v_parent_id := v_appointment_id;
    end if;
    v_appointment_ids := array_append(
      v_appointment_ids,
      v_appointment_id
    );

    if v_create_payment and v_price > 0 then
      insert into public.invoices(
        workspace_id,
        contact_id,
        appointment_id,
        type,
        status,
        issue_date,
        due_date,
        subtotal,
        tax_rate,
        tax_amount,
        discount_value,
        total,
        amount_paid,
        income_recorded_at,
        notes
      ) values (
        v_workspace_id,
        v_contact_id,
        v_appointment_id,
        'invoice',
        'sent',
        v_payment_date,
        v_payment_date,
        v_price,
        0,
        0,
        0,
        v_price,
        0,
        null,
        v_payment_note
      );
    end if;
  end loop;

  if p_payload -> 'task_titles' is not null then
    if jsonb_typeof(p_payload -> 'task_titles') <> 'array'
       or jsonb_array_length(p_payload -> 'task_titles') > 20 then
      raise exception 'Task titles must be an array of at most 20 items'
        using errcode = '22023';
    end if;
    for v_task_title in
      select value
        from jsonb_array_elements_text(p_payload -> 'task_titles')
    loop
      v_task_title := btrim(v_task_title);
      if char_length(v_task_title) not between 1 and 500 then
        raise exception 'A task title is invalid' using errcode = '22023';
      end if;
      insert into public.tasks(
        workspace_id,
        contact_id,
        appointment_id,
        title,
        priority,
        due_date,
        status,
        reminder_timing
      ) values (
        v_workspace_id,
        v_contact_id,
        v_appointment_ids[1],
        v_task_title,
        'medium',
        v_task_due_date,
        'open',
        'none'
      );
    end loop;
  end if;

  if v_request_id is not null then
    update public.booking_requests
       set status = 'confirmed'
     where id = v_request_id
       and workspace_id = v_workspace_id;
  end if;

  select coalesce(
    preference.all_notifications and preference.new_booking,
    true
  )
    into v_notification_allowed
    from public.notification_preferences preference
   where preference.workspace_id = v_workspace_id;

  if coalesce(v_notification_allowed, true) then
    insert into public.notifications(
      workspace_id,
      type,
      title,
      body,
      deep_link,
      dedupe_key
    ) values (
      v_workspace_id,
      'new_booking',
      v_notification_title,
      v_notification_body,
      '/bookings/' || v_appointment_ids[1]::text,
      'workflow:create_booking:' || v_idempotency_key
    )
    on conflict (workspace_id, dedupe_key) do nothing;
  end if;

  v_existing_result := jsonb_build_object(
    'appointment_ids',
    to_jsonb(v_appointment_ids),
    'contact_id',
    v_contact_id
  );
  update app_private.workflow_idempotency request
     set result = v_existing_result
   where request.workspace_id = v_workspace_id
     and request.operation = 'create_booking'
     and request.idempotency_key = v_idempotency_key
     and request.user_id = v_caller_id;
  return v_existing_result;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.run_business_automations(p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_booking_requests integer := 0;
  v_overdue_payments integer := 0;
  v_morning_briefs integer := 0;
  v_notifications_removed integer := 0;
  v_tokens_removed integer := 0;
  v_webhook_payloads_scrubbed integer := 0;
  v_open_alerts integer := 0;
begin
  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select request.workspace_id,
         'booking_request',
         'Booking request waiting',
         request.name || ' has been waiting for your reply.',
         '/booking-requests/' || request.id::text,
         'booking_request_waiting:' || request.id::text
    from public.booking_requests request
    left join public.notification_preferences preference
      on preference.workspace_id = request.workspace_id
   where request.status = 'pending'
     and request.created_at <= p_now - interval '4 hours'
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.booking_request, true)
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_booking_requests = row_count;

  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select invoice.workspace_id,
         'invoice_overdue',
         'Payment overdue',
         'A payment of £' ||
           trim(to_char(greatest(invoice.total - coalesce(invoice.amount_paid, 0), 0),
             'FM999999990.00')) || ' needs attention.',
         '/payments/' || invoice.id::text,
         'invoice_overdue:' || invoice.id::text
    from public.invoices invoice
    left join public.notification_preferences preference
      on preference.workspace_id = invoice.workspace_id
    left join public.workspace_settings settings
      on settings.workspace_id = invoice.workspace_id
   where invoice.type = 'invoice'
     and invoice.status in ('sent', 'overdue')
     and invoice.due_date is not null
     and invoice.due_date < (p_now at time zone coalesce(settings.timezone, 'UTC'))::date
     and invoice.total > coalesce(invoice.amount_paid, 0)
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.invoice_overdue, true)
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_overdue_payments = row_count;

  insert into public.notifications(
    workspace_id, type, title, body, deep_link, dedupe_key
  )
  select workspace.id,
         'morning_digest',
         'Your morning brief',
         format(
           '%s booking%s today · %s open task%s · %s payment%s to collect.',
           counts.booking_count,
           case when counts.booking_count = 1 then '' else 's' end,
           counts.task_count,
           case when counts.task_count = 1 then '' else 's' end,
           counts.payment_count,
           case when counts.payment_count = 1 then '' else 's' end
         ),
         '/home',
         'morning_digest:' || counts.local_date::text
    from public.workspaces workspace
    left join public.workspace_settings settings
      on settings.workspace_id = workspace.id
    left join public.notification_preferences preference
      on preference.workspace_id = workspace.id
    cross join lateral (
      select
        (p_now at time zone coalesce(settings.timezone, 'UTC'))::date as local_date,
        extract(hour from p_now at time zone coalesce(settings.timezone, 'UTC'))::integer as local_hour,
        (select count(*) from public.appointments appointment
          where appointment.workspace_id = workspace.id
            and appointment.status = 'scheduled'
            and (appointment.start_time at time zone coalesce(settings.timezone, 'UTC'))::date =
              (p_now at time zone coalesce(settings.timezone, 'UTC'))::date) as booking_count,
        (select count(*) from public.tasks task
          where task.workspace_id = workspace.id and task.status = 'open') as task_count,
        (select count(*) from public.invoices invoice
          where invoice.workspace_id = workspace.id
            and invoice.type = 'invoice'
            and invoice.status in ('sent', 'overdue')
            and invoice.total > coalesce(invoice.amount_paid, 0)) as payment_count
    ) counts
   where counts.local_hour = 7
     and coalesce(preference.all_notifications, true)
     and coalesce(preference.morning_digest, true)
     and not (
       coalesce(preference.quiet_sundays, false)
       and extract(isodow from counts.local_date) = 7
     )
  on conflict (workspace_id, dedupe_key) do nothing;
  get diagnostics v_morning_briefs = row_count;

  delete from public.notifications
   where (read and created_at < p_now - interval '90 days')
      or created_at < p_now - interval '1 year';
  get diagnostics v_notifications_removed = row_count;

  delete from public.push_tokens
   where last_seen_at < p_now - interval '90 days';
  get diagnostics v_tokens_removed = row_count;

  delete from app_private.edge_rate_limit_events
   where created_at < p_now - interval '1 day';

  v_webhook_payloads_scrubbed :=
    app_private.scrub_expired_stripe_webhook_payloads();
  v_open_alerts := app_private.refresh_operational_alerts(p_now);

  return jsonb_build_object(
    'booking_request_notifications', v_booking_requests,
    'overdue_payment_notifications', v_overdue_payments,
    'morning_briefs', v_morning_briefs,
    'notifications_removed', v_notifications_removed,
    'push_tokens_removed', v_tokens_removed,
    'webhook_payloads_scrubbed', v_webhook_payloads_scrubbed,
    'open_operational_alerts', v_open_alerts
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_public_booking_request(p_workspace_id uuid, p_name text, p_phone text, p_service_id uuid, p_preferred_time_text text, p_message text, p_source_hash text, p_request_token uuid)
 RETURNS TABLE(booking_request_id uuid, outcome text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'app_private'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_phone_normalized text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_existing_id uuid;
  v_request_id uuid;
  v_source_count integer;
  v_phone_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  if p_workspace_id is null
    or p_request_token is null
    or p_source_hash is null
    or p_source_hash !~ '^[0-9a-f]{64}$'
    or char_length(btrim(coalesce(p_name, ''))) not between 1 and 80
    or char_length(btrim(coalesce(p_phone, ''))) not between 7 and 32
    or char_length(v_phone_normalized) not between 7 and 32
    or (
      p_preferred_time_text is not null
      and char_length(p_preferred_time_text) > 160
    )
    or (p_message is not null and char_length(p_message) > 1000)
  then
    raise exception 'invalid booking request' using errcode = '22023';
  end if;

  -- A workspace lock makes the rolling count and insert one serial operation.
  -- Workloop workspaces are single-owner and public-request volume is low, so
  -- this deliberately favours correctness over per-key lock complexity.
  perform pg_advisory_xact_lock(
    hashtextextended('workloop:booking:' || p_workspace_id::text, 0)
  );

  select request.id
  into v_existing_id
  from public.booking_requests as request
  where request.workspace_id = p_workspace_id
    and request.request_token = p_request_token
  limit 1;

  if v_existing_id is not null then
    return query select v_existing_id, 'duplicate'::text;
    return;
  end if;

  if not exists (
    select 1
    from public.business_profiles as profile
    where profile.workspace_id = p_workspace_id
      and profile.booking_mode = 'manual'
  ) then
    return query select null::uuid, 'profile_unavailable'::text;
    return;
  end if;

  if p_service_id is not null and not exists (
    select 1
    from public.services as service
    where service.id = p_service_id
      and service.workspace_id = p_workspace_id
      and service.show_on_profile = true
      and service.active = true
  ) then
    return query select null::uuid, 'invalid_service'::text;
    return;
  end if;

  delete from app_private.edge_rate_limit_events
  where created_at < v_now - interval '1 day';

  select count(*)::integer
  into v_source_count
  from app_private.edge_rate_limit_events
  where scope = 'booking_source'
    and resource_key = p_workspace_id::text
    and subject_key = p_source_hash
    and created_at >= v_now - interval '15 minutes';

  if v_source_count >= 5 then
    return query select null::uuid, 'rate_limited_source'::text;
    return;
  end if;

  select count(*)::integer
  into v_phone_count
  from app_private.edge_rate_limit_events
  where scope = 'booking_phone'
    and resource_key = p_workspace_id::text
    and subject_key = v_phone_normalized
    and created_at >= v_now - interval '15 minutes';

  if v_phone_count >= 3 then
    return query select null::uuid, 'rate_limited_phone'::text;
    return;
  end if;

  insert into public.booking_requests (
    workspace_id,
    name,
    phone,
    service_id,
    preferred_time_text,
    message,
    status,
    source_hash,
    request_token
  )
  values (
    p_workspace_id,
    btrim(p_name),
    btrim(p_phone),
    p_service_id,
    nullif(btrim(coalesce(p_preferred_time_text, '')), ''),
    nullif(btrim(coalesce(p_message, '')), ''),
    'pending',
    p_source_hash,
    p_request_token
  )
  returning id into v_request_id;

  insert into app_private.edge_rate_limit_events(
    scope,
    resource_key,
    subject_key,
    created_at
  )
  values
    ('booking_source', p_workspace_id::text, p_source_hash, v_now),
    ('booking_phone', p_workspace_id::text, v_phone_normalized, v_now);

  insert into public.notifications(
    workspace_id,
    type,
    title,
    body,
    deep_link
  )
  values (
    p_workspace_id,
    'booking_request',
    'New booking request',
    btrim(p_name) || ' requested a booking.',
    '/booking-requests/' || v_request_id::text
  );

  return query select v_request_id, 'created'::text;
end;
$function$;

-- Repair only routes recoverable from a same-workspace durable identifier.
-- No title/name/date matching, read-state changes, new inbox rows or re-sends.
update public.notifications notification
   set deep_link=app_private.resolve_notification_entity_route(
     notification.workspace_id,notification.type,notification.deep_link,notification.dedupe_key)
 where app_private.resolve_notification_entity_route(
     notification.workspace_id,notification.type,notification.deep_link,notification.dedupe_key)
       is distinct from notification.deep_link;

comment on function app_private.route_notification_to_entity() is
  'Preserves producer-supplied record routes and resolves only unambiguous legacy identifiers; client detail lookup remains workspace scoped.';
notify pgrst, 'reload schema';
