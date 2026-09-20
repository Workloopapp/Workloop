-- Next-beta booking feedback: preserve an exact requested instant and workspace
-- timezone, and allow an authenticated owner to explicitly accept an overlap.

alter table public.booking_requests
  add column if not exists requested_for timestamptz,
  add column if not exists requested_timezone text;

alter table public.booking_requests
  drop constraint if exists booking_requests_requested_timezone_check;
alter table public.booking_requests
  add constraint booking_requests_requested_timezone_check check (
    requested_timezone is null
    or (
      char_length(requested_timezone) between 3 and 64
      and (
        requested_timezone in ('UTC', 'GMT')
        or requested_timezone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$'
      )
    )
  );

comment on column public.booking_requests.requested_for is
  'Exact requested booking instant, normalized to timestamptz by Postgres.';
comment on column public.booking_requests.requested_timezone is
  'IANA workspace timezone used when the customer chose the requested wall-clock time.';

create or replace function public.create_public_booking_request_v2(
  p_workspace_id uuid,
  p_name text,
  p_phone text,
  p_email text,
  p_service_id uuid,
  p_preferred_time_text text,
  p_requested_for timestamptz,
  p_requested_timezone text,
  p_message text,
  p_source_hash text,
  p_request_token uuid
)
returns table (
  booking_request_id uuid,
  outcome text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_timezone text := btrim(coalesce(p_requested_timezone, ''));
  v_workspace_timezone text;
  v_result record;
begin
  -- Authorization is enforced by the EXECUTE ACL below. Supabase service keys
  -- are mapped to the service_role database role by PostgREST, but branch keys
  -- do not necessarily populate the legacy request.jwt.claim.role setting.
  select coalesce(nullif(btrim(settings.timezone), ''), 'Europe/London')
    into v_workspace_timezone
    from public.workspace_settings settings
   where settings.workspace_id = p_workspace_id;
  if char_length(v_email) not between 3 and 254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or p_requested_for is null
     or p_requested_for < clock_timestamp() - interval '1 day'
     or p_requested_for > clock_timestamp() + interval '366 days'
     or char_length(v_timezone) not between 3 and 64
     or not exists (
       select 1
         from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = v_timezone
     )
     or v_workspace_timezone is null
     or v_timezone <> v_workspace_timezone then
    raise exception 'invalid booking request date, timezone, or email'
      using errcode = '22023';
  end if;

  select request.booking_request_id, request.outcome
    into v_result
    from public.create_public_booking_request_v2(
      p_workspace_id,
      p_name,
      p_phone,
      v_email,
      p_service_id,
      p_preferred_time_text,
      p_message,
      p_source_hash,
      p_request_token
    ) request;

  if v_result.booking_request_id is not null
     and v_result.outcome = 'created' then
    update public.booking_requests
       set requested_for = p_requested_for,
           requested_timezone = v_timezone
     where id = v_result.booking_request_id
       and workspace_id = p_workspace_id;
  end if;

  return query
    select v_result.booking_request_id::uuid, v_result.outcome::text;
end;
$$;

revoke all on function public.create_public_booking_request_v2(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.create_public_booking_request_v2(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid
) to service_role;

comment on function public.create_public_booking_request_v2(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid
) is
  'Service-role-only booking request intake with an exact requested instant and IANA timezone.';

-- Replace the current internal implementation under the name introduced by
-- the confirmation-email wrapper. Conflict rejection remains the default;
-- only payloads carrying allow_overlap=true may insert an overlapping booking.
create or replace function app_private.create_booking_workflow_without_confirmation_email(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
      '/work',
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
$$;


revoke all on function
  app_private.create_booking_workflow_without_confirmation_email(jsonb)
  from public, anon, authenticated;
grant execute on function
  app_private.create_booking_workflow_without_confirmation_email(jsonb)
  to service_role;

comment on function
  app_private.create_booking_workflow_without_confirmation_email(jsonb) is
  'Atomic member booking workflow. Overlap is allowed only after explicit owner confirmation in the client payload.';
