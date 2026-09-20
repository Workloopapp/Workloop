-- A bundle is several selected catalogue services in one booking, not another
-- booking entity. Keep the primary service and legacy RPCs intact, and retain
-- every trusted service/extra value in the existing immutable item snapshots.
alter table public.booking_request_items
  drop constraint booking_request_items_kind_check,
  drop constraint booking_request_items_source_check,
  add constraint booking_request_items_kind_check check (item_kind in ('base', 'service', 'add_on')),
  add constraint booking_request_items_source_check check (
    (item_kind in ('base', 'service') and source_add_on_id is null) or item_kind = 'add_on'
  );
alter table public.appointment_items
  drop constraint appointment_items_kind_check,
  drop constraint appointment_items_source_check,
  add constraint appointment_items_kind_check check (item_kind in ('base', 'service', 'add_on')),
  add constraint appointment_items_source_check check (
    (item_kind in ('base', 'service') and source_add_on_id is null) or item_kind = 'add_on'
  );

create function app_private.booking_service_selection(
  p_workspace_id uuid, p_service_ids uuid[], p_add_on_ids uuid[], p_public boolean
) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  v_service_count integer := coalesce(cardinality(p_service_ids), 0);
  v_add_on_count integer := coalesce(cardinality(p_add_on_ids), 0);
  v_items jsonb;
  v_duration integer;
  v_price numeric;
begin
  if v_service_count not between 1 and 8
     or v_service_count <> (select count(distinct id) from unnest(p_service_ids) id) then
    raise exception 'invalid_service' using errcode = '22023';
  end if;
  -- Lock catalogue rows until all snapshots have been committed. A concurrent
  -- edit cannot change the duration between availability validation and intake.
  perform 1 from public.services s
    where s.workspace_id = p_workspace_id and s.id = any(p_service_ids)
    order by s.id for share;
  if v_service_count <> (select count(*) from public.services s
      where s.workspace_id = p_workspace_id and s.id = any(p_service_ids)
        and s.active and (not p_public or s.show_on_profile)
        and s.duration_mins between 5 and 1440) then
    raise exception 'invalid_service' using errcode = '22023';
  end if;
  if v_add_on_count > 8
     or v_add_on_count <> (select count(distinct id) from unnest(p_add_on_ids) id) then
    raise exception 'invalid_add_on' using errcode = '22023';
  end if;
  perform 1 from public.service_add_ons a
    where a.workspace_id = p_workspace_id and a.id = any(p_add_on_ids)
    order by a.id for share;
  if v_add_on_count <> (select count(*) from public.service_add_ons a
      where a.workspace_id = p_workspace_id and a.id = any(p_add_on_ids)
        and a.service_id = any(p_service_ids) and a.active) then
    raise exception 'invalid_add_on' using errcode = '22023';
  end if;

  select jsonb_agg(to_jsonb(item) order by item.position),
         sum(item.duration_mins)::integer, sum(item.price)
    into v_items, v_duration, v_price
    from (
      select case when selected.ordinality = 1 then 'base' else 'service' end as item_kind,
             s.id as source_service_id, null::uuid as source_add_on_id,
             s.name, s.duration_mins, s.price, selected.ordinality::integer - 1 as position
        from unnest(p_service_ids) with ordinality selected(id, ordinality)
        join public.services s on s.id = selected.id and s.workspace_id = p_workspace_id
      union all
      select 'add_on', a.service_id, a.id, a.name, a.duration_mins, a.price,
             v_service_count + selected.ordinality::integer - 1
        from unnest(p_add_on_ids) with ordinality selected(id, ordinality)
        join public.service_add_ons a on a.id = selected.id and a.workspace_id = p_workspace_id
    ) item;
  if v_duration not between 5 and 1440 or v_price not between 0 and 1000000 then
    raise exception 'invalid_bundle_total' using errcode = '22023';
  end if;
  return jsonb_build_object('items', v_items, 'duration', v_duration, 'price', v_price);
end;
$$;
revoke all on function app_private.booking_service_selection(uuid, uuid[], uuid[], boolean)
  from public, anon, authenticated;
grant execute on function app_private.booking_service_selection(uuid, uuid[], uuid[], boolean) to service_role;

create function public.create_public_booking_request_v4(
  p_workspace_id uuid, p_name text, p_phone text, p_email text,
  p_service_id uuid, p_preferred_time_text text, p_requested_for timestamptz,
  p_requested_timezone text, p_message text, p_source_hash text,
  p_request_token uuid, p_service_ids uuid[], p_add_on_ids uuid[] default '{}'
) returns table (booking_request_id uuid, outcome text)
language plpgsql security definer set search_path = '' as $$
declare
  v_existing uuid;
  v_selection jsonb;
  v_result record;
begin
  -- The service-role-only EXECUTE ACL is the ingress authorization boundary.
  -- Existing tokens are replayed before consulting mutable catalogue values.
  select r.id into v_existing from public.booking_requests r
    where r.workspace_id = p_workspace_id and r.request_token = p_request_token;
  if v_existing is not null then
    return query select v_existing, 'duplicate'::text;
    return;
  end if;
  if p_service_id is distinct from p_service_ids[1] then
    return query select null::uuid, 'invalid_service'::text;
    return;
  end if;
  begin
    v_selection := app_private.booking_service_selection(p_workspace_id, p_service_ids, p_add_on_ids, true);
  exception when sqlstate '22023' then
    return query select null::uuid, sqlerrm::text;
    return;
  end;
  select r.booking_request_id, r.outcome into v_result
    from public.create_public_booking_request_v2(
      p_workspace_id, p_name, p_phone, p_email, p_service_id,
      p_preferred_time_text, p_requested_for, p_requested_timezone,
      p_message, p_source_hash, p_request_token
    ) r;
  if v_result.outcome = 'created' then
    -- The legacy insert trigger supplied the primary row. Replace it within
    -- this same transaction with the complete locked catalogue selection.
    delete from public.booking_request_items i where i.booking_request_id = v_result.booking_request_id;
    insert into public.booking_request_items(
      workspace_id, booking_request_id, item_kind, source_service_id,
      source_add_on_id, name, duration_mins, price, position
    ) select p_workspace_id, v_result.booking_request_id, item.*
      from jsonb_to_recordset(v_selection -> 'items') as item(
        item_kind text, source_service_id uuid, source_add_on_id uuid,
        name text, duration_mins integer, price numeric, position integer
      );
  end if;
  return query select v_result.booking_request_id::uuid, v_result.outcome::text;
end;
$$;
revoke all on function public.create_public_booking_request_v4(
  uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[],uuid[]
) from public, anon, authenticated;
grant execute on function public.create_public_booking_request_v4(
  uuid,text,text,text,uuid,text,timestamptz,text,text,text,uuid,uuid[],uuid[]
) to service_role;

create function public.get_public_booking_slot_suggestions_v4(
  p_handle text, p_service_id uuid, p_source_hash text,
  p_service_ids uuid[], p_add_on_ids uuid[] default '{}', p_target_date date default null
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_workspace_id uuid;
  v_selection jsonb;
  v_primary_duration integer;
begin
  select p.workspace_id into v_workspace_id from public.business_profiles p
    where p.handle = lower(btrim(p_handle)) and p.booking_mode = 'manual'
      and exists (select 1 from public.workspace_members m where m.workspace_id = p.workspace_id);
  if v_workspace_id is null then
    return jsonb_build_object('outcome', 'profile_unavailable');
  end if;
  if p_service_id is distinct from p_service_ids[1] then
    return jsonb_build_object('outcome', 'invalid_service');
  end if;
  begin
    v_selection := app_private.booking_service_selection(v_workspace_id, p_service_ids, p_add_on_ids, true);
  exception when sqlstate '22023' then
    return jsonb_build_object('outcome', sqlerrm);
  end;
  v_primary_duration := (v_selection -> 'items' -> 0 ->> 'duration_mins')::integer;
  return app_private.get_public_booking_slot_suggestions_core(
    p_handle, p_service_id, p_source_hash,
    (v_selection ->> 'duration')::integer - v_primary_duration, p_target_date
  );
end;
$$;
revoke all on function public.get_public_booking_slot_suggestions_v4(text,uuid,text,uuid[],uuid[],date)
  from public, anon, authenticated;
grant execute on function public.get_public_booking_slot_suggestions_v4(text,uuid,text,uuid[],uuid[],date) to service_role;

-- Preserve existing single-service/custom booking semantics and immutable
-- replay results. Bundles compose server-owned totals before the same atomic
-- booking/payment/notification workflow runs.
alter function app_private.create_booking_workflow(jsonb)
  rename to create_booking_workflow_single_service_items;
create function app_private.create_booking_workflow(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_workspace_id uuid;
  v_request_id uuid;
  v_service_ids uuid[];
  v_add_on_ids uuid[] := '{}';
  v_selection jsonb;
  v_items jsonb;
  v_result jsonb;
  v_appointments jsonb;
  v_duration integer;
  v_price numeric;
  v_title text;
  v_idempotency_key text := btrim(coalesce(p_payload ->> 'idempotency_key', ''));
  v_caller_id uuid := auth.uid();
begin
  begin
    v_workspace_id := nullif(p_payload ->> 'workspace_id', '')::uuid;
    v_request_id := nullif(p_payload ->> 'booking_request_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Booking item identifiers are invalid' using errcode = '22023';
  end;
  if v_caller_id is null or not exists (select 1 from public.workspace_members m where m.workspace_id = v_workspace_id and m.user_id = v_caller_id) then
    raise exception 'Workspace access denied' using errcode = '42501';
  end if;
  if exists (select 1 from app_private.workflow_idempotency i
      where i.workspace_id = v_workspace_id and i.user_id = v_caller_id
        and i.operation = 'create_booking' and i.idempotency_key = v_idempotency_key and i.result is not null) then
    return app_private.create_booking_workflow_single_service_items(p_payload);
  end if;
  if v_request_id is not null then
    -- A request with additional base services is immutable: catalogue changes
    -- and caller-supplied price/service arrays cannot rewrite its composition.
    if not exists (select 1 from public.booking_request_items i where i.workspace_id = v_workspace_id
        and i.booking_request_id = v_request_id and i.item_kind = 'service') then
      return app_private.create_booking_workflow_single_service_items(p_payload);
    end if;
    select jsonb_agg(to_jsonb(i) order by i.position), sum(i.duration_mins)::integer, sum(i.price)
      into v_items, v_duration, v_price from public.booking_request_items i
      where i.workspace_id = v_workspace_id and i.booking_request_id = v_request_id;
  elsif p_payload ? 'service_ids' then
    if jsonb_typeof(p_payload -> 'service_ids') is distinct from 'array'
       or (p_payload ? 'add_on_ids' and jsonb_typeof(p_payload -> 'add_on_ids') is distinct from 'array') then
      raise exception 'Booking service IDs must be an array' using errcode = '22023';
    end if;
    begin
      select array_agg(value::uuid order by ordinality) into v_service_ids
        from jsonb_array_elements_text(p_payload -> 'service_ids') with ordinality;
      select coalesce(array_agg(value::uuid order by ordinality), '{}'::uuid[]) into v_add_on_ids
        from jsonb_array_elements_text(coalesce(p_payload -> 'add_on_ids', '[]'::jsonb)) with ordinality;
    exception when invalid_text_representation then
      raise exception 'Booking item identifiers are invalid' using errcode = '22023';
    end;
    if nullif(p_payload ->> 'service_id', '')::uuid is distinct from v_service_ids[1] then
      raise exception 'invalid_service' using errcode = '22023';
    end if;
    v_selection := app_private.booking_service_selection(v_workspace_id, v_service_ids, v_add_on_ids, false);
    v_items := v_selection -> 'items';
    v_duration := (v_selection ->> 'duration')::integer;
    v_price := (v_selection ->> 'price')::numeric;
  else
    return app_private.create_booking_workflow_single_service_items(p_payload);
  end if;

  select string_agg(item ->> 'name', ' + ' order by (item ->> 'position')::integer)
    into v_title from jsonb_array_elements(v_items) item where item ->> 'item_kind' <> 'add_on';
  select jsonb_agg(appointment || jsonb_build_object(
      'end_time', ((appointment ->> 'start_time')::timestamptz + make_interval(mins => v_duration))
    ) order by ordinality) into v_appointments
    from jsonb_array_elements(p_payload -> 'appointments') with ordinality a(appointment, ordinality);
  p_payload := p_payload || jsonb_build_object(
    'price', v_price, 'title', left(v_title, 120), 'appointments', v_appointments,
    'service_id', v_items -> 0 -> 'source_service_id'
  );
  if v_request_id is not null then
    return app_private.create_booking_workflow_single_service_items(p_payload);
  end if;
  v_result := app_private.create_booking_workflow_without_item_snapshots(p_payload);
  insert into public.appointment_items(
    workspace_id, appointment_id, item_kind, source_service_id,
    source_add_on_id, name, duration_mins, price, position
  ) select v_workspace_id, appointment_id::uuid, item.*
    from jsonb_array_elements_text(v_result -> 'appointment_ids') appointment_id
    cross join jsonb_to_recordset(v_items) as item(
      item_kind text, source_service_id uuid, source_add_on_id uuid,
      name text, duration_mins integer, price numeric, position integer
    )
    on conflict on constraint appointment_items_appointment_id_position_key do nothing;
  return v_result;
end;
$$;
revoke all on function app_private.create_booking_workflow(jsonb) from public, anon, authenticated;
grant execute on function app_private.create_booking_workflow(jsonb) to service_role;
comment on table public.service_add_ons is 'Optional extras scoped to one catalogue service; multiple services and their extras may be selected for one booking.';
