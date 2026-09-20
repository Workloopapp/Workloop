-- Return a deliberately capped set of public booking suggestions without
-- exposing appointments, client data, busy intervals, or occupancy counts.
-- These are request suggestions only: nothing is reserved or confirmed here.

alter table app_private.edge_rate_limit_events
  drop constraint if exists edge_rate_limit_events_scope_check;

alter table app_private.edge_rate_limit_events
  add constraint edge_rate_limit_events_scope_check check (
    scope in (
      'booking_source',
      'booking_phone',
      'booking_availability',
      'places_autocomplete',
      'places_details',
      'waitlist_email'
    )
  );

create index if not exists appointments_workspace_schedule_lookup_idx
  on public.appointments(workspace_id, start_time, end_time)
  where status not in ('cancelled', 'no_show');

create or replace function public.get_public_booking_slot_suggestions(
  p_handle text,
  p_service_id uuid,
  p_source_hash text,
  p_extra_duration integer default 0
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_workspace_id uuid;
  v_timezone text;
  v_working_hours jsonb;
  v_duration integer;
  v_notice_hours integer;
  v_window_weeks integer;
  v_buffer_minutes integer;
  v_local_today date;
  v_last_date date;
  v_day date;
  v_day_name text;
  v_short_day text;
  v_day_value jsonb;
  v_blocks jsonb;
  v_block jsonb;
  v_block_start time;
  v_block_end time;
  v_candidate_local timestamp;
  v_candidate_start timestamptz;
  v_candidate_end timestamptz;
  v_days jsonb := '[]'::jsonb;
  v_day_slots jsonb;
  v_day_count integer := 0;
  v_slot_count integer;
  v_rate_count integer;
  v_rate_oldest timestamptz;
  v_retry_after integer;
begin
  if p_handle is null
     or btrim(p_handle) !~ '^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$'
     or p_service_id is null
     or p_source_hash is null
     or p_source_hash !~ '^[0-9a-f]{64}$'
     or p_extra_duration not between 0 and 11520 then
    raise exception 'invalid availability request' using errcode = '22023';
  end if;

  select profile.workspace_id
    into v_workspace_id
    from public.business_profiles profile
   where profile.handle = lower(btrim(p_handle))
     and profile.booking_mode = 'manual'
     and exists (
       select 1
         from public.workspace_members member
        where member.workspace_id = profile.workspace_id
     )
   limit 1;

  if v_workspace_id is null then
    return jsonb_build_object('outcome', 'profile_unavailable');
  end if;

  select service.duration_mins
    into v_duration
    from public.services service
   where service.id = p_service_id
     and service.workspace_id = v_workspace_id
     and service.active = true
     and service.show_on_profile = true
   limit 1;

  if v_duration is null or v_duration not between 5 and 1440 then
    return jsonb_build_object('outcome', 'invalid_service');
  end if;
  v_duration := v_duration + p_extra_duration;

  select
    coalesce(nullif(btrim(settings.timezone), ''), 'Europe/London'),
    coalesce(settings.working_hours, '{}'::jsonb),
    greatest(0, least(coalesce(settings.min_booking_notice_hours, 2), 168)),
    greatest(1, least(coalesce(settings.max_booking_window_weeks, 12), 52)),
    greatest(0, least(coalesce(settings.buffer_mins, 0), 240))
  into
    v_timezone,
    v_working_hours,
    v_notice_hours,
    v_window_weeks,
    v_buffer_minutes
  from public.workspace_settings settings
  where settings.workspace_id = v_workspace_id;

  if v_timezone is null
     or not exists (
       select 1
         from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = v_timezone
     ) then
    return jsonb_build_object('outcome', 'configuration_unavailable');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'workloop:booking-availability:' || v_workspace_id::text || ':' || p_source_hash,
      0
    )
  );

  delete from app_private.edge_rate_limit_events
   where created_at < v_now - interval '1 day';

  select count(*)::integer, min(event.created_at)
    into v_rate_count, v_rate_oldest
    from app_private.edge_rate_limit_events event
   where event.scope = 'booking_availability'
     and event.resource_key = v_workspace_id::text
     and event.subject_key = p_source_hash
     and event.created_at >= v_now - interval '15 minutes';

  if v_rate_count >= 30 then
    v_retry_after := greatest(
      1,
      ceil(extract(epoch from (
        v_rate_oldest + interval '15 minutes' - v_now
      )))::integer
    );
    return jsonb_build_object(
      'outcome', 'rate_limited',
      'retryAfterSeconds', v_retry_after
    );
  end if;

  insert into app_private.edge_rate_limit_events(
    scope,
    resource_key,
    subject_key,
    created_at
  ) values (
    'booking_availability',
    v_workspace_id::text,
    p_source_hash,
    v_now
  );

  v_local_today := (v_now at time zone v_timezone)::date;
  v_last_date := least(
    v_local_today + 27,
    v_local_today + (v_window_weeks * 7)
  );

  for v_day in
    select generated_day::date
      from generate_series(
        v_local_today::timestamp,
        v_last_date::timestamp,
        interval '1 day'
      ) generated_day
  loop
    exit when v_day_count >= 5;

    v_day_name := case extract(isodow from v_day)::integer
      when 1 then 'Monday'
      when 2 then 'Tuesday'
      when 3 then 'Wednesday'
      when 4 then 'Thursday'
      when 5 then 'Friday'
      when 6 then 'Saturday'
      else 'Sunday'
    end;
    v_short_day := left(v_day_name, 3);
    v_day_value := coalesce(
      v_working_hours -> v_day_name,
      v_working_hours -> v_short_day,
      v_working_hours -> lower(v_day_name),
      v_working_hours -> lower(v_short_day)
    );

    if v_day_value is null
       or jsonb_typeof(v_day_value) <> 'object'
       or (
         v_day_value ? 'enabled'
         and coalesce(v_day_value ->> 'enabled', 'false') <> 'true'
       ) then
      continue;
    end if;

    if jsonb_typeof(v_day_value -> 'blocks') = 'array' then
      v_blocks := v_day_value -> 'blocks';
    else
      v_blocks := jsonb_build_array(jsonb_build_object(
        'start', coalesce(v_day_value ->> 'start', v_day_value ->> 'open'),
        'end', coalesce(v_day_value ->> 'end', v_day_value ->> 'close')
      ));
    end if;

    v_day_slots := '[]'::jsonb;
    v_slot_count := 0;

    for v_block in
      select block.value
        from jsonb_array_elements(v_blocks) block
    loop
      exit when v_slot_count >= 6;
      begin
        v_block_start := (v_block ->> 'start')::time;
        v_block_end := (v_block ->> 'end')::time;
      exception when invalid_datetime_format or datetime_field_overflow then
        continue;
      end;

      if v_block_start is null
         or v_block_end is null
         or v_block_end <= v_block_start then
        continue;
      end if;

      v_candidate_local := v_day + v_block_start;
      while v_candidate_local + make_interval(mins => v_duration)
        <= v_day + v_block_end
      loop
        exit when v_slot_count >= 6;
        v_candidate_start := v_candidate_local at time zone v_timezone;
        v_candidate_end := v_candidate_start
          + make_interval(mins => v_duration);

        -- A nonexistent wall-clock value on a spring DST transition does not
        -- round-trip. Never suggest a time the customer cannot actually pick.
        if v_candidate_start at time zone v_timezone = v_candidate_local
           and v_candidate_start >= v_now
             + make_interval(hours => v_notice_hours)
           and v_candidate_start <= v_now
             + make_interval(days => v_window_weeks * 7)
           and not exists (
             select 1
               from public.appointments appointment
              where appointment.workspace_id = v_workspace_id
                and appointment.status not in ('cancelled', 'no_show')
                and appointment.start_time < v_candidate_end
                  + make_interval(mins => v_buffer_minutes)
                and appointment.end_time > v_candidate_start
                  - make_interval(mins => v_buffer_minutes)
           ) then
          v_day_slots := v_day_slots || jsonb_build_array(
            to_char(
              v_candidate_start at time zone 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS"Z"'
            )
          );
          v_slot_count := v_slot_count + 1;
        end if;

        v_candidate_local := v_candidate_local + interval '15 minutes';
      end loop;
    end loop;

    if v_slot_count > 0 then
      v_days := v_days || jsonb_build_array(jsonb_build_object(
        'date', to_char(v_day, 'YYYY-MM-DD'),
        'slots', v_day_slots
      ));
      v_day_count := v_day_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'outcome', 'ok',
    'timezone', v_timezone,
    'durationMinutes', v_duration,
    'generatedAt', to_char(
      v_now at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS"Z"'
    ),
    'days', v_days
  );
end;
$$;

revoke all on function public.get_public_booking_slot_suggestions(
  text,
  uuid,
  text,
  integer
) from public;
revoke all on function public.get_public_booking_slot_suggestions(
  text,
  uuid,
  text,
  integer
) from anon;
revoke all on function public.get_public_booking_slot_suggestions(
  text,
  uuid,
  text,
  integer
) from authenticated;
grant execute on function public.get_public_booking_slot_suggestions(
  text,
  uuid,
  text,
  integer
) to service_role;

comment on function public.get_public_booking_slot_suggestions(
  text,
  uuid,
  text,
  integer
) is
  'Service-role-only, rate-limited public booking suggestions. Returns capped UTC starts without private diary details or reservations.';
