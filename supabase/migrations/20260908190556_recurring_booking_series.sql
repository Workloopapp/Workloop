-- Finite recurring series reuse real appointments and the existing atomic
-- booking workflow. Cancellation/rescheduling updates one persisted occurrence;
-- there is no background expansion that can recreate an exception.
alter table public.appointments add column recurrence_timezone text
  check (recurrence_timezone is null or char_length(recurrence_timezone) between 1 and 100);

create function public.create_recurring_booking_workflow(p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_workspace uuid;
  v_zone text;
  v_business_zone text;
  v_rule text;
  v_interval integer;
  v_occurrences jsonb;
  v_occurrence jsonb;
  v_index integer := 0;
  v_first timestamptz;
  v_start timestamptz;
  v_end timestamptz;
  v_duration interval;
  v_expected timestamp;
  v_result jsonb;
  v_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'A recurring booking payload is required' using errcode = '22023';
  end if;
  v_workspace := (p_payload->>'workspace_id')::uuid;
  if not exists (select 1 from public.workspace_members
      where workspace_id = v_workspace and user_id = auth.uid()) then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;
  v_zone := p_payload->>'recurrence_timezone';
  select timezone into v_business_zone from public.workspace_settings
    where workspace_id = v_workspace;
  if v_zone is null or v_zone is distinct from v_business_zone
      or not exists (select 1 from pg_catalog.pg_timezone_names where name = v_zone) then
    raise exception 'Use the current business timezone for recurring bookings' using errcode = '22023';
  end if;
  v_rule := p_payload->>'recurrence_rule';
  if v_rule is null or v_rule !~ '^FREQ=WEEKLY;INTERVAL=[1-4]$' then
    raise exception 'Repeat every one to four weeks' using errcode = '22023';
  end if;
  v_interval := right(v_rule, 1)::integer;
  v_occurrences := p_payload->'appointments';
  if jsonb_typeof(v_occurrences) is distinct from 'array' then
    raise exception 'Provide between two and 24 bookings' using errcode = '22023';
  end if;
  if jsonb_array_length(v_occurrences) not between 2 and 24 then
    raise exception 'Provide between two and 24 bookings' using errcode = '22023';
  end if;
  -- A public booking request always confirms one requested appointment.
  if nullif(p_payload->>'booking_request_id', '') is not null then
    raise exception 'A booking request cannot create a recurring series' using errcode = '22023';
  end if;
  v_key := btrim(coalesce(p_payload->>'idempotency_key', ''));
  if char_length(v_key) not between 16 and 118 then
    raise exception 'A valid idempotency key is required' using errcode = '22023';
  end if;
  for v_occurrence in select value from jsonb_array_elements(v_occurrences) loop
    v_start := (v_occurrence->>'start_time')::timestamptz;
    v_end := (v_occurrence->>'end_time')::timestamptz;
    if v_start is null or v_end is null or not isfinite(v_start) or not isfinite(v_end)
        or v_end <= v_start or v_end - v_start > interval '24 hours' then
      raise exception 'Recurring booking timing is invalid' using errcode = '22023';
    end if;
    if v_index = 0 then
      v_first := v_start;
      v_duration := v_end - v_start;
    end if;
    v_expected := (v_first at time zone v_zone) + make_interval(days => 7 * v_interval * v_index);
    if (v_start at time zone v_zone) <> v_expected or v_end - v_start <> v_duration then
      raise exception 'Recurring bookings must keep their business time and duration' using errcode = '22023';
    end if;
    v_index := v_index + 1;
  end loop;
  -- The underlying workflow owns MFA, membership, linked-record validation,
  -- schedule locking, conflict detection, item snapshots and retry results.
  -- Namespace the key so a single-booking retry cannot acquire series metadata.
  v_result := public.create_booking_workflow(
    (p_payload - 'recurrence_rule' - 'recurrence_timezone') ||
      jsonb_build_object('idempotency_key', 'recurring:' || v_key)
  );
  update public.appointments set recurrence_rule = v_rule, recurrence_timezone = v_zone
    where workspace_id = v_workspace and recurrence_timezone is null
      and id in (select value::uuid from jsonb_array_elements_text(v_result->'appointment_ids'));
  return v_result;
end;
$$;
revoke all on function public.create_recurring_booking_workflow(jsonb) from public, anon;
grant execute on function public.create_recurring_booking_workflow(jsonb) to authenticated;
comment on column public.appointments.recurrence_timezone is
  'IANA business timezone frozen when this finite recurring series was created. Null on legacy and one-off bookings.';
comment on function public.create_recurring_booking_workflow(jsonb) is
  'Authenticated, MFA-gated atomic creation of 2–24 weekly bookings. Existing RLS applies; retries keep one series; occurrence edits never expand it.';
