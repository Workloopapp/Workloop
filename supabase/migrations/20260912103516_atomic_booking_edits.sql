-- The detail editor changes an existing booking and its service-item snapshot
-- in one transaction. Catalogue history is retained for ordinary edits; an
-- explicit service/name replacement creates the newly chosen work snapshot.
-- Issued documents have independent immutable items and are never updated here.
create function app_private.edit_booking_workflow(
  p_appointment_id uuid, p_values jsonb, p_replace_service_items boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_booking public.appointments;
  v_saved public.appointments;
  v_base_id uuid;
  v_other_price numeric;
  v_item_count integer;
  v_duration integer;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not app_private.current_user_meets_mfa_policy() then
    raise exception 'Multi-factor authentication is required' using errcode = '42501';
  end if;
  select * into v_booking from public.appointments
    where id = p_appointment_id
      and app_private.is_workspace_member(workspace_id)
    for update;
  if not found then
    raise exception 'Booking unavailable' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object'
     or not (p_values ?& array['contact_id','service_id','title','start_time',
       'end_time','location','notes','price'])
     or (p_values - array['contact_id','service_id','title','start_time',
       'end_time','location','notes','price']) <> '{}'::jsonb then
    raise exception 'Invalid booking edit' using errcode = '22023';
  end if;
  if p_values->>'contact_id' is not null and not exists (
    select 1 from public.contacts where id = (p_values->>'contact_id')::uuid
      and workspace_id = v_booking.workspace_id
  ) then
    raise exception 'Client unavailable' using errcode = '42501';
  end if;
  if p_values->>'service_id' is not null and not exists (
    select 1 from public.services where id = (p_values->>'service_id')::uuid
      and workspace_id = v_booking.workspace_id
  ) then
    raise exception 'Service unavailable' using errcode = '42501';
  end if;
  if not coalesce(p_replace_service_items, false)
     and (p_values->>'service_id')::uuid is distinct from v_booking.service_id then
    raise exception 'Changed service requires a new snapshot' using errcode = '22023';
  end if;
  v_duration := extract(epoch from ((p_values->>'end_time')::timestamptz -
    (p_values->>'start_time')::timestamptz)) / 60;
  if v_duration is null or v_duration not between 1 and 1440
     or (p_values->>'price')::numeric is null
     or (p_values->>'price')::numeric not between 0 and 1000000
     or nullif(btrim(p_values->>'title'), '') is null then
    raise exception 'Enter a valid booking name, duration and price' using errcode = '22023';
  end if;

  update public.appointments set
    contact_id = (p_values->>'contact_id')::uuid,
    service_id = (p_values->>'service_id')::uuid,
    title = btrim(p_values->>'title'),
    start_time = (p_values->>'start_time')::timestamptz,
    end_time = (p_values->>'end_time')::timestamptz,
    location = nullif(btrim(p_values->>'location'), ''),
    notes = nullif(btrim(p_values->>'notes'), ''),
    price = (p_values->>'price')::numeric
  where id = p_appointment_id returning * into v_saved;

  select count(*) into v_item_count from public.appointment_items
    where appointment_id = p_appointment_id;
  if coalesce(p_replace_service_items, false) or v_item_count = 0 then
    if char_length(v_saved.title) > 80 then
      raise exception 'Use a service name of 80 characters or fewer' using errcode = '22023';
    end if;
    delete from public.appointment_items where appointment_id = p_appointment_id;
    insert into public.appointment_items(workspace_id, appointment_id,
      item_kind, source_service_id, name, duration_mins, price, position)
    values (v_saved.workspace_id, v_saved.id, 'base', v_saved.service_id,
      v_saved.title, v_duration, v_saved.price, 0);
  elsif v_saved.price is distinct from v_booking.price then
    -- The editor changes the booking total. Retain selected extras/other
    -- services at their agreed prices and apply the change to the base item.
    select id into v_base_id from public.appointment_items
      where appointment_id = p_appointment_id and item_kind = 'base';
    select coalesce(sum(price), 0) into v_other_price
      from public.appointment_items
      where appointment_id = p_appointment_id and id <> v_base_id;
    if v_base_id is null or v_saved.price < v_other_price then
      raise exception 'The total must cover the other booked services and extras. Change the service to replace the item breakdown.'
        using errcode = '22023';
    end if;
    update public.appointment_items set price = v_saved.price - v_other_price
      where id = v_base_id;
  end if;
  if v_item_count = 1 and not coalesce(p_replace_service_items, false) then
    update public.appointment_items set duration_mins = v_duration
      where appointment_id = p_appointment_id;
  end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.position), '[]'::jsonb)
    into v_items from public.appointment_items i where i.appointment_id = p_appointment_id;
  return to_jsonb(v_saved) || jsonb_build_object(
    'appointment_items', v_items,
    'contacts', (select jsonb_build_object('name', name) from public.contacts where id = v_saved.contact_id),
    'services', (select jsonb_build_object('name', name) from public.services where id = v_saved.service_id));
end;
$$;
revoke all on function app_private.edit_booking_workflow(uuid,jsonb,boolean) from public,anon;
grant execute on function app_private.edit_booking_workflow(uuid,jsonb,boolean) to authenticated;

create function public.edit_booking_workflow(
  p_appointment_id uuid, p_values jsonb, p_replace_service_items boolean default false
) returns jsonb language sql security invoker set search_path = '' as $$
  select app_private.edit_booking_workflow(p_appointment_id, p_values, p_replace_service_items);
$$;
revoke all on function public.edit_booking_workflow(uuid,jsonb,boolean) from public,anon;
grant execute on function public.edit_booking_workflow(uuid,jsonb,boolean) to authenticated;
