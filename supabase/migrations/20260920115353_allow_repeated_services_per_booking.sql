-- Repeated catalogue service IDs represent quantity within one booking. Keep
-- the existing eight-item cap, catalogue validation, immutable snapshots and
-- service-role-only execution boundary.
create or replace function app_private.booking_service_selection(
  p_workspace_id uuid, p_service_ids uuid[], p_add_on_ids uuid[], p_public boolean
) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  v_service_count integer := coalesce(cardinality(p_service_ids), 0);
  v_distinct_service_count integer := coalesce(
    (select count(distinct id) from unnest(p_service_ids) id),
    0
  );
  v_add_on_count integer := coalesce(cardinality(p_add_on_ids), 0);
  v_items jsonb;
  v_duration integer;
  v_price numeric;
begin
  if v_service_count not between 1 and 8
     or exists (select 1 from unnest(p_service_ids) id where id is null) then
    raise exception 'invalid_service' using errcode = '22023';
  end if;
  -- Lock each selected catalogue row until every occurrence is snapshotted.
  perform 1 from public.services s
    where s.workspace_id = p_workspace_id and s.id = any(p_service_ids)
    order by s.id for share;
  if v_distinct_service_count <> (select count(*) from public.services s
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
grant execute on function app_private.booking_service_selection(uuid, uuid[], uuid[], boolean)
  to service_role;
