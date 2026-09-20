-- Reject invalid enabled hours before the onboarding transaction writes records.
-- Closed days may keep unfinished times; active blocks must be same-day and
-- non-overlapping. Both legacy open/close and current blocks payloads are valid.
-- Existing authenticated wrapper, SECURITY INVOKER, grants and retry semantics
-- remain unchanged. No rows are rewritten and no schema columns are added.

create or replace function app_private.complete_onboarding_implementation(
  business_name text,
  industry_name text,
  profile_handle text,
  service_rows jsonb,
  working_hours_value jsonb,
  revenue_target_value numeric,
  first_booking_value jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_workspace_id uuid;
  new_workspace_id uuid := gen_random_uuid();
  booking_contact_id uuid;
  booking_service_id uuid;
  booking_service_name text;
  booking_start timestamptz;
  booking_end timestamptz;
  service_row jsonb;
  hours_day record;
  hours_blocks jsonb;
  hours_block jsonb;
  hours_start text;
  hours_end text;
  start_minute integer;
  end_minute integer;
  day_ranges int4range[];
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  -- Serialise retries for one account. A completed first call is returned
  -- unchanged; a failed call rolls back fully before the lock is released.
  perform pg_advisory_xact_lock(hashtextextended(caller_id::text, 0));

  select wm.workspace_id
    into existing_workspace_id
    from public.workspace_members wm
   where wm.user_id = caller_id
   order by wm.created_at, wm.id
   limit 1;

  if existing_workspace_id is not null then
    return existing_workspace_id;
  end if;

  business_name := btrim(coalesce(business_name, ''));
  industry_name := btrim(coalesce(industry_name, ''));
  profile_handle := lower(btrim(coalesce(profile_handle, '')));
  service_rows := coalesce(service_rows, '[]'::jsonb);
  working_hours_value := coalesce(working_hours_value, '{}'::jsonb);
  revenue_target_value := coalesce(revenue_target_value, 0);

  if char_length(business_name) not between 2 and 120 then
    raise exception 'Business name must be between 2 and 120 characters';
  end if;
  if char_length(industry_name) > 80 then
    raise exception 'Industry must be at most 80 characters';
  end if;
  if profile_handle !~ '^[a-z0-9][a-z0-9_-]{2,39}$' then
    raise exception 'Handle must be 3-40 lowercase letters, numbers, underscores, or hyphens';
  end if;
  if jsonb_typeof(service_rows) <> 'array'
     or jsonb_array_length(service_rows) > 50 then
    raise exception 'Services must be an array containing at most 50 items';
  end if;
  if jsonb_typeof(working_hours_value) <> 'object' then
    raise exception 'Working hours must be an object';
  end if;
  for hours_day in select key, value from jsonb_each(working_hours_value)
  loop
    if hours_day.key not in ('Mon','Tue','Wed','Thu','Fri','Sat','Sun',
        'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')
       or jsonb_typeof(hours_day.value) is distinct from 'object'
       or jsonb_typeof(hours_day.value -> 'enabled') is distinct from 'boolean' then
      raise exception '%: choose whether this is a working day.', hours_day.key
        using errcode = '22023';
    end if;
    if hours_day.value -> 'enabled' = 'false'::jsonb then
      continue;
    end if;
    hours_blocks := case when hours_day.value ? 'blocks'
      then hours_day.value -> 'blocks'
      else jsonb_build_array(jsonb_build_object(
        'start', coalesce(hours_day.value -> 'start', hours_day.value -> 'open'),
        'end', coalesce(hours_day.value -> 'end', hours_day.value -> 'close')))
      end;
    if jsonb_typeof(hours_blocks) is distinct from 'array' then
      raise exception '%: add at least one working block.', hours_day.key
        using errcode = '22023';
    end if;
    if jsonb_array_length(hours_blocks) = 0 then
      raise exception '%: add at least one working block.', hours_day.key
        using errcode = '22023';
    end if;
    day_ranges := array[]::int4range[];
    for hours_block in select value from jsonb_array_elements(hours_blocks)
    loop
      hours_start := hours_block ->> 'start';
      hours_end := hours_block ->> 'end';
      if jsonb_typeof(hours_block -> 'start') is distinct from 'string'
         or jsonb_typeof(hours_block -> 'end') is distinct from 'string'
         or hours_start !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
         or hours_end !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception '%: use valid times such as 09:00.', hours_day.key
          using errcode = '22023';
      end if;
      start_minute := split_part(hours_start, ':', 1)::integer * 60
        + split_part(hours_start, ':', 2)::integer;
      end_minute := split_part(hours_end, ':', 1)::integer * 60
        + split_part(hours_end, ':', 2)::integer;
      if end_minute <= start_minute then
        raise exception '%: closing time must be after opening time.', hours_day.key
          using errcode = '22023';
      end if;
      if exists (select 1 from unnest(day_ranges) as r
          where r && int4range(start_minute, end_minute, '[)')) then
        raise exception '%: working blocks must not overlap.', hours_day.key
          using errcode = '22023';
      end if;
      day_ranges := array_append(day_ranges,
        int4range(start_minute, end_minute, '[)'));
    end loop;
  end loop;
  if revenue_target_value < 0 then
    raise exception 'Revenue target cannot be negative';
  end if;

  insert into public.workspaces(id, name, industry)
  values (new_workspace_id, business_name, nullif(industry_name, ''));

  insert into public.workspace_members(workspace_id, user_id)
  values (new_workspace_id, caller_id);

  insert into public.workspace_settings(
    workspace_id,
    working_hours,
    revenue_target
  ) values (
    new_workspace_id,
    working_hours_value,
    revenue_target_value
  );

  insert into public.business_profiles(workspace_id, handle)
  values (new_workspace_id, profile_handle);

  for service_row in select value from jsonb_array_elements(service_rows)
  loop
    if jsonb_typeof(service_row) <> 'object'
       or char_length(btrim(coalesce(service_row ->> 'name', ''))) not between 1 and 120
       or coalesce((service_row ->> 'duration_mins')::integer, 0) not between 1 and 1440
       or coalesce((service_row ->> 'price')::numeric, -1) < 0 then
      raise exception 'A service contains invalid values';
    end if;

    insert into public.services(
      workspace_id,
      name,
      duration_mins,
      price,
      description
    ) values (
      new_workspace_id,
      btrim(service_row ->> 'name'),
      (service_row ->> 'duration_mins')::integer,
      (service_row ->> 'price')::numeric,
      nullif(regexp_replace(
        service_row ->> 'description',
        '^[[:space:]]+|[[:space:]]+$', '', 'g'
      ), '')
    );
  end loop;

  if first_booking_value is not null
     and first_booking_value <> 'null'::jsonb then
    if jsonb_typeof(first_booking_value) <> 'object' then
      raise exception 'First booking must be an object';
    end if;

    booking_service_name := nullif(btrim(first_booking_value ->> 'service_name'), '');
    booking_start := (first_booking_value ->> 'start_time')::timestamptz;
    booking_end := (first_booking_value ->> 'end_time')::timestamptz;

    if char_length(btrim(coalesce(first_booking_value ->> 'client_name', ''))) not between 1 and 120
       or booking_start is null
       or booking_end is null
       or booking_end <= booking_start then
      raise exception 'First booking contains invalid values';
    end if;

    if booking_service_name is not null then
      select s.id
        into booking_service_id
        from public.services s
       where s.workspace_id = new_workspace_id
         and s.name = booking_service_name
       order by s.created_at, s.id
       limit 1;
    end if;

    insert into public.contacts(workspace_id, name, status)
    values (
      new_workspace_id,
      btrim(first_booking_value ->> 'client_name'),
      'active'
    )
    returning id into booking_contact_id;

    insert into public.appointments(
      workspace_id,
      contact_id,
      service_id,
      title,
      start_time,
      end_time,
      price,
      status
    ) values (
      new_workspace_id,
      booking_contact_id,
      booking_service_id,
      coalesce(booking_service_name, 'Booking'),
      booking_start,
      booking_end,
      coalesce(
        (select s.price from public.services s where s.id = booking_service_id),
        0
      ),
      'scheduled'
    );
  end if;

  return new_workspace_id;
end;
$$;
