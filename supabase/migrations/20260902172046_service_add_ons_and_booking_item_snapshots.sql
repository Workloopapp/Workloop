-- Optional extras belong to one configured service. Packages/bundles remain
-- ordinary services with their own name, duration and price; this deliberately
-- avoids a generic product-composition engine.
create table public.service_add_ons (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  service_id uuid not null,
  name text not null,
  description text,
  duration_mins integer not null default 0,
  price numeric(12, 2) not null default 0,
  active boolean not null default true,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_add_ons_workspace_service_fk
    foreign key (workspace_id, service_id)
    references public.services(workspace_id, id)
    on delete cascade,
  constraint service_add_ons_name_check
    check (char_length(btrim(name)) between 1 and 80),
  constraint service_add_ons_description_check
    check (description is null or char_length(description) <= 500),
  constraint service_add_ons_duration_check
    check (duration_mins between 0 and 1440),
  constraint service_add_ons_price_check
    check (price between 0 and 1000000),
  constraint service_add_ons_position_check
    check (position between 0 and 1000)
);

create unique index service_add_ons_workspace_id_id_uidx
  on public.service_add_ons(workspace_id, id);
create index service_add_ons_service_position_idx
  on public.service_add_ons(workspace_id, service_id, active, position, id);

-- These rows are immutable business-history snapshots. Catalog edits and
-- deletes may clear source identifiers, but never rewrite what was requested
-- or confirmed.
create unique index if not exists booking_requests_workspace_id_id_uidx
  on public.booking_requests(workspace_id, id);

create table public.booking_request_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  booking_request_id uuid not null,
  item_kind text not null,
  source_service_id uuid,
  source_add_on_id uuid,
  name text not null,
  duration_mins integer not null,
  price numeric(12, 2) not null,
  position integer not null,
  created_at timestamptz not null default now(),
  constraint booking_request_items_workspace_request_fk
    foreign key (workspace_id, booking_request_id)
    references public.booking_requests(workspace_id, id)
    on delete cascade,
  constraint booking_request_items_workspace_service_fk
    foreign key (workspace_id, source_service_id)
    references public.services(workspace_id, id)
    on delete set null (source_service_id),
  constraint booking_request_items_workspace_add_on_fk
    foreign key (workspace_id, source_add_on_id)
    references public.service_add_ons(workspace_id, id)
    on delete set null (source_add_on_id),
  constraint booking_request_items_kind_check
    check (item_kind in ('base', 'add_on')),
  constraint booking_request_items_source_check
    check (
      (item_kind = 'base' and source_add_on_id is null)
      or item_kind = 'add_on'
    ),
  constraint booking_request_items_name_check
    check (char_length(btrim(name)) between 1 and 80),
  constraint booking_request_items_duration_check
    check (duration_mins between 0 and 1440),
  constraint booking_request_items_price_check
    check (price between 0 and 1000000),
  constraint booking_request_items_position_check
    check (position between 0 and 1000),
  unique (booking_request_id, position)
);

create unique index booking_request_items_one_base_uidx
  on public.booking_request_items(booking_request_id)
  where item_kind = 'base';
create unique index booking_request_items_source_add_on_uidx
  on public.booking_request_items(booking_request_id, source_add_on_id)
  where source_add_on_id is not null;
create index booking_request_items_workspace_request_idx
  on public.booking_request_items(workspace_id, booking_request_id, position);
create index booking_request_items_workspace_source_service_idx
  on public.booking_request_items(workspace_id, source_service_id);
create index booking_request_items_workspace_source_add_on_idx
  on public.booking_request_items(workspace_id, source_add_on_id);

create table public.appointment_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  appointment_id uuid not null,
  item_kind text not null,
  source_service_id uuid,
  source_add_on_id uuid,
  name text not null,
  duration_mins integer not null,
  price numeric(12, 2) not null,
  position integer not null,
  created_at timestamptz not null default now(),
  constraint appointment_items_workspace_appointment_fk
    foreign key (workspace_id, appointment_id)
    references public.appointments(workspace_id, id)
    on delete cascade,
  constraint appointment_items_workspace_service_fk
    foreign key (workspace_id, source_service_id)
    references public.services(workspace_id, id)
    on delete set null (source_service_id),
  constraint appointment_items_workspace_add_on_fk
    foreign key (workspace_id, source_add_on_id)
    references public.service_add_ons(workspace_id, id)
    on delete set null (source_add_on_id),
  constraint appointment_items_kind_check
    check (item_kind in ('base', 'add_on')),
  constraint appointment_items_source_check
    check (
      (item_kind = 'base' and source_add_on_id is null)
      or item_kind = 'add_on'
    ),
  constraint appointment_items_name_check
    check (char_length(btrim(name)) between 1 and 80),
  constraint appointment_items_duration_check
    check (duration_mins between 0 and 1440),
  constraint appointment_items_price_check
    check (price between 0 and 1000000),
  constraint appointment_items_position_check
    check (position between 0 and 1000),
  unique (appointment_id, position)
);

create unique index appointment_items_one_base_uidx
  on public.appointment_items(appointment_id)
  where item_kind = 'base';
create unique index appointment_items_source_add_on_uidx
  on public.appointment_items(appointment_id, source_add_on_id)
  where source_add_on_id is not null;
create index appointment_items_workspace_appointment_idx
  on public.appointment_items(workspace_id, appointment_id, position);
create index appointment_items_workspace_source_service_idx
  on public.appointment_items(workspace_id, source_service_id);
create index appointment_items_workspace_source_add_on_idx
  on public.appointment_items(workspace_id, source_add_on_id);

alter table public.service_add_ons enable row level security;
alter table public.booking_request_items enable row level security;
alter table public.appointment_items enable row level security;

revoke all on table public.service_add_ons from public, anon, authenticated;
revoke all on table public.booking_request_items from public, anon, authenticated;
revoke all on table public.appointment_items from public, anon, authenticated;

grant select, insert, update, delete on table public.service_add_ons
  to authenticated;
grant select on table public.booking_request_items, public.appointment_items
  to authenticated;

create policy "Members can manage service add-ons"
on public.service_add_ons for all
to authenticated
using (app_private.is_workspace_member(workspace_id))
with check (app_private.is_workspace_member(workspace_id));

create policy "Members can read booking request items"
on public.booking_request_items for select
to authenticated
using (app_private.is_workspace_member(workspace_id));

create policy "Members can read appointment items"
on public.appointment_items for select
to authenticated
using (app_private.is_workspace_member(workspace_id));

create policy "Verified MFA users require AAL2"
on public.service_add_ons as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

create policy "Verified MFA users require AAL2"
on public.booking_request_items as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

create policy "Verified MFA users require AAL2"
on public.appointment_items as restrictive for all
to authenticated
using (app_private.current_user_meets_mfa_policy())
with check (app_private.current_user_meets_mfa_policy());

-- Snapshot the base service at the booking-request write boundary so every
-- intake overload receives the same immutable history. This intentionally
-- covers older TestFlight clients that continue to call v2 while v3 adds the
-- selected extras after the trusted request insert succeeds.
create function app_private.snapshot_booking_request_base_service()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.service_id is null then
    return new;
  end if;

  insert into public.booking_request_items(
    workspace_id,
    booking_request_id,
    item_kind,
    source_service_id,
    source_add_on_id,
    name,
    duration_mins,
    price,
    position,
    created_at
  )
  select new.workspace_id,
         new.id,
         'base',
         service.id,
         null,
         service.name,
         service.duration_mins,
         service.price,
         0,
         coalesce(new.created_at, now())
    from public.services service
   where service.workspace_id = new.workspace_id
     and service.id = new.service_id
  on conflict on constraint booking_request_items_booking_request_id_position_key
    do nothing;

  return new;
end;
$$;

revoke all on function app_private.snapshot_booking_request_base_service()
  from public, anon, authenticated;

create trigger snapshot_booking_request_base_service
after insert on public.booking_requests
for each row execute function app_private.snapshot_booking_request_base_service();

comment on function app_private.snapshot_booking_request_base_service() is
  'Snapshots a trusted base service for every new booking request, including requests created by legacy intake overloads.';

-- Best-available snapshot for pre-migration rows. Appointment snapshots use
-- the actual confirmed title, duration and price rather than today's catalog
-- values, preserving historical meaning from this point forward.
insert into public.booking_request_items(
  workspace_id,
  booking_request_id,
  item_kind,
  source_service_id,
  name,
  duration_mins,
  price,
  position,
  created_at
)
select request.workspace_id,
       request.id,
       'base',
       service.id,
       service.name,
       service.duration_mins,
       service.price,
       0,
       coalesce(request.created_at, now())
  from public.booking_requests request
  join public.services service
    on service.id = request.service_id
   and service.workspace_id = request.workspace_id
on conflict on constraint booking_request_items_booking_request_id_position_key
  do nothing;

insert into public.appointment_items(
  workspace_id,
  appointment_id,
  item_kind,
  source_service_id,
  name,
  duration_mins,
  price,
  position,
  created_at
)
select appointment.workspace_id,
       appointment.id,
       'base',
       service.id,
       coalesce(nullif(btrim(appointment.title), ''), service.name),
       greatest(
         0,
         least(
           1440,
           coalesce(
             round(extract(epoch from (appointment.end_time - appointment.start_time)) / 60)::integer,
             service.duration_mins
           )
         )
       ),
       greatest(0, least(1000000, coalesce(appointment.price, service.price))),
       0,
       coalesce(appointment.created_at, now())
  from public.appointments appointment
  join public.services service
    on service.id = appointment.service_id
   and service.workspace_id = appointment.workspace_id
on conflict on constraint appointment_items_appointment_id_position_key
  do nothing;

-- New public clients call v3 with IDs only. The trusted database validates the
-- parent relationship and snapshots catalog values. Existing v2 overloads are
-- intentionally retained for older TestFlight builds.
create function public.create_public_booking_request_v3(
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
  p_request_token uuid,
  p_add_on_ids uuid[] default '{}'::uuid[]
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
  v_existing_id uuid;
  v_result record;
  v_add_on_count integer := coalesce(array_length(p_add_on_ids, 1), 0);
begin
  -- The EXECUTE ACL below is the authorization boundary. Avoid a second check
  -- against the legacy JWT-claim GUC: branch service keys are mapped to the
  -- service_role database role without necessarily populating that setting.
  select request.id
    into v_existing_id
    from public.booking_requests request
   where request.workspace_id = p_workspace_id
     and request.request_token = p_request_token;
  if v_existing_id is not null then
    return query select v_existing_id, 'duplicate'::text;
    return;
  end if;

  if v_add_on_count > 8
     or v_add_on_count <> (
       select count(distinct add_on_id)::integer
         from unnest(coalesce(p_add_on_ids, '{}'::uuid[])) add_on_id
     )
     or (
       v_add_on_count > 0
       and (
         p_service_id is null
         or v_add_on_count <> (
           select count(*)::integer
             from public.service_add_ons add_on
            where add_on.workspace_id = p_workspace_id
              and add_on.service_id = p_service_id
              and add_on.id = any(p_add_on_ids)
              and add_on.active = true
         )
       )
     ) then
    return query select null::uuid, 'invalid_add_on'::text;
    return;
  end if;

  select request.booking_request_id, request.outcome
    into v_result
    from public.create_public_booking_request_v2(
      p_workspace_id,
      p_name,
      p_phone,
      p_email,
      p_service_id,
      p_preferred_time_text,
      p_requested_for,
      p_requested_timezone,
      p_message,
      p_source_hash,
      p_request_token
    ) request;

  if v_result.outcome = 'created' and p_service_id is not null then
    insert into public.booking_request_items(
      workspace_id,
      booking_request_id,
      item_kind,
      source_service_id,
      source_add_on_id,
      name,
      duration_mins,
      price,
      position
    )
    select p_workspace_id,
           v_result.booking_request_id,
           'base',
           service.id,
           null,
           service.name,
           service.duration_mins,
           service.price,
           0
      from public.services service
     where service.workspace_id = p_workspace_id
       and service.id = p_service_id
    on conflict on constraint booking_request_items_booking_request_id_position_key
      do nothing;

    insert into public.booking_request_items(
      workspace_id,
      booking_request_id,
      item_kind,
      source_service_id,
      source_add_on_id,
      name,
      duration_mins,
      price,
      position
    )
    select p_workspace_id,
           v_result.booking_request_id,
           'add_on',
           p_service_id,
           add_on.id,
           add_on.name,
           add_on.duration_mins,
           add_on.price,
           selected.ordinality::integer
      from unnest(coalesce(p_add_on_ids, '{}'::uuid[]))
           with ordinality selected(id, ordinality)
      join public.service_add_ons add_on
        on add_on.id = selected.id
       and add_on.workspace_id = p_workspace_id
       and add_on.service_id = p_service_id;
  end if;

  return query
    select v_result.booking_request_id::uuid, v_result.outcome::text;
end;
$$;

revoke all on function public.create_public_booking_request_v3(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid, uuid[]
) from public, anon, authenticated;
grant execute on function public.create_public_booking_request_v3(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid, uuid[]
) to service_role;

comment on function public.create_public_booking_request_v3(
  uuid, text, text, text, uuid, text, timestamptz, text, text, text, uuid, uuid[]
) is
  'Service-role-only public request intake that validates add-on IDs and snapshots trusted catalog values.';

-- Suggested times use the same trusted catalog validation as intake. The
-- caller sends IDs only; duration is summed here before the private schedule
-- query runs, so client-computed totals can never shorten a slot.
create function public.get_public_booking_slot_suggestions_v2(
  p_handle text,
  p_service_id uuid,
  p_source_hash text,
  p_add_on_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_workspace_id uuid;
  v_add_on_count integer := coalesce(array_length(p_add_on_ids, 1), 0);
  v_extra_duration integer := 0;
begin
  select profile.workspace_id
    into v_workspace_id
    from public.business_profiles profile
   where profile.handle = lower(btrim(p_handle))
     and profile.booking_mode = 'manual'
     and exists (
       select 1 from public.workspace_members member
        where member.workspace_id = profile.workspace_id
     )
   limit 1;

  if v_workspace_id is null then
    return jsonb_build_object('outcome', 'profile_unavailable');
  end if;
  if v_add_on_count > 8
     or v_add_on_count <> (
       select count(distinct add_on_id)::integer
         from unnest(coalesce(p_add_on_ids, '{}'::uuid[])) add_on_id
     )
     or v_add_on_count <> (
       select count(*)::integer
         from public.service_add_ons add_on
        where add_on.workspace_id = v_workspace_id
          and add_on.service_id = p_service_id
          and add_on.id = any(coalesce(p_add_on_ids, '{}'::uuid[]))
          and add_on.active = true
     ) then
    return jsonb_build_object('outcome', 'invalid_add_on');
  end if;

  select coalesce(sum(add_on.duration_mins), 0)::integer
    into v_extra_duration
    from public.service_add_ons add_on
   where add_on.workspace_id = v_workspace_id
     and add_on.service_id = p_service_id
     and add_on.id = any(coalesce(p_add_on_ids, '{}'::uuid[]))
     and add_on.active = true;

  return public.get_public_booking_slot_suggestions(
    p_handle,
    p_service_id,
    p_source_hash,
    v_extra_duration
  );
end;
$$;

revoke all on function public.get_public_booking_slot_suggestions_v2(
  text, uuid, text, uuid[]
) from public, anon, authenticated;
grant execute on function public.get_public_booking_slot_suggestions_v2(
  text, uuid, text, uuid[]
) to service_role;

-- Wrap the current workflow rather than changing its public JSON signature.
-- Old clients omit add_on_ids; new clients may provide a bounded UUID array.
alter function app_private.create_booking_workflow(jsonb)
  rename to create_booking_workflow_without_item_snapshots;

create function app_private.create_booking_workflow(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_caller_id uuid := auth.uid();
  v_workspace_id uuid;
  v_request_id uuid;
  v_service_id uuid;
  v_idempotency_key text;
  v_appointment_ids uuid[];
  v_add_on_ids uuid[] := '{}'::uuid[];
  v_add_on_count integer := 0;
begin
  begin
    v_workspace_id := nullif(p_payload ->> 'workspace_id', '')::uuid;
    v_request_id := nullif(p_payload ->> 'booking_request_id', '')::uuid;
    v_service_id := nullif(p_payload ->> 'service_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Booking item identifiers are invalid' using errcode = '22023';
  end;

  v_idempotency_key := btrim(coalesce(p_payload ->> 'idempotency_key', ''));
  if v_caller_id is not null
     and v_workspace_id is not null
     and char_length(v_idempotency_key) between 16 and 128
     and exists (
       select 1
         from app_private.workflow_idempotency request
        where request.workspace_id = v_workspace_id
          and request.user_id = v_caller_id
          and request.operation = 'create_booking'
          and request.idempotency_key = v_idempotency_key
          and request.result is not null
     ) then
    -- The inner workflow owns the authoritative replay result. Delegate before
    -- consulting mutable catalogue state so deactivating or deleting an add-on
    -- cannot turn a previously successful retry into a validation failure.
    return app_private.create_booking_workflow_without_item_snapshots(p_payload);
  end if;

  if p_payload ? 'add_on_ids' then
    if jsonb_typeof(p_payload -> 'add_on_ids') <> 'array' then
      raise exception 'Booking add-on IDs must be an array' using errcode = '22023';
    end if;
    begin
      select coalesce(array_agg(value::uuid), '{}'::uuid[])
        into v_add_on_ids
        from jsonb_array_elements_text(p_payload -> 'add_on_ids');
    exception when invalid_text_representation then
      raise exception 'Booking item identifiers are invalid' using errcode = '22023';
    end;
  end if;

  v_add_on_count := coalesce(array_length(v_add_on_ids, 1), 0);
  if v_request_id is null and (
    v_add_on_count > 8
    or v_add_on_count <> (
      select count(distinct add_on_id)::integer
        from unnest(v_add_on_ids) add_on_id
    )
    or (
      v_add_on_count > 0 and (
        v_service_id is null
        or v_add_on_count <> (
          select count(*)::integer
            from public.service_add_ons add_on
           where add_on.workspace_id = v_workspace_id
             and add_on.service_id = v_service_id
             and add_on.id = any(v_add_on_ids)
             and add_on.active = true
        )
      )
    )
  ) then
    raise exception 'Booking add-ons are invalid' using errcode = '22023';
  end if;

  v_result := app_private.create_booking_workflow_without_item_snapshots(p_payload);

  select coalesce(array_agg(value::uuid), '{}'::uuid[])
    into v_appointment_ids
    from jsonb_array_elements_text(v_result -> 'appointment_ids');

  if v_request_id is not null then
    insert into public.appointment_items(
      workspace_id,
      appointment_id,
      item_kind,
      source_service_id,
      source_add_on_id,
      name,
      duration_mins,
      price,
      position
    )
    select request_item.workspace_id,
           appointment_id,
           request_item.item_kind,
           request_item.source_service_id,
           request_item.source_add_on_id,
           request_item.name,
           request_item.duration_mins,
           request_item.price,
           request_item.position
      from public.booking_request_items request_item
      cross join unnest(v_appointment_ids) appointment_id
     where request_item.workspace_id = v_workspace_id
       and request_item.booking_request_id = v_request_id
    on conflict on constraint appointment_items_appointment_id_position_key
      do nothing;
  elsif v_service_id is not null then
    insert into public.appointment_items(
      workspace_id,
      appointment_id,
      item_kind,
      source_service_id,
      source_add_on_id,
      name,
      duration_mins,
      price,
      position
    )
    select v_workspace_id,
           appointment_id,
           'base',
           service.id,
           null,
           service.name,
           service.duration_mins,
           service.price,
           0
      from public.services service
      cross join unnest(v_appointment_ids) appointment_id
     where service.workspace_id = v_workspace_id
       and service.id = v_service_id
    on conflict on constraint appointment_items_appointment_id_position_key
      do nothing;

    insert into public.appointment_items(
      workspace_id,
      appointment_id,
      item_kind,
      source_service_id,
      source_add_on_id,
      name,
      duration_mins,
      price,
      position
    )
    select v_workspace_id,
           appointment_id,
           'add_on',
           v_service_id,
           add_on.id,
           add_on.name,
           add_on.duration_mins,
           add_on.price,
           selected.ordinality::integer
      from unnest(v_add_on_ids) with ordinality selected(id, ordinality)
      join public.service_add_ons add_on
        on add_on.id = selected.id
       and add_on.workspace_id = v_workspace_id
       and add_on.service_id = v_service_id
      cross join unnest(v_appointment_ids) appointment_id
    on conflict on constraint appointment_items_appointment_id_position_key
      do nothing;
  end if;

  return v_result;
end;
$$;

revoke all on function app_private.create_booking_workflow(jsonb)
  from public, anon, authenticated;
grant execute on function app_private.create_booking_workflow(jsonb)
  to service_role;

comment on function app_private.create_booking_workflow(jsonb) is
  'Atomic booking wrapper that preserves immutable requested/confirmed item snapshots; legacy payloads remain valid.';

comment on table public.service_add_ons is
  'Optional extras configured beneath one service; bundles remain ordinary services.';
comment on table public.booking_request_items is
  'Immutable catalog snapshots selected on a public booking request.';
comment on table public.appointment_items is
  'Immutable catalog snapshots associated with a confirmed appointment.';
