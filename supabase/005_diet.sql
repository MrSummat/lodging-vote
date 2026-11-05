-- Dietary needs and allergies, stored with each guest's travel plans.
-- Run once in Supabase > SQL Editor. Already included in schema.sql for new setups.

alter table public.travel add column if not exists diet text not null default '';

create or replace function public.get_travel()
returns jsonb language sql stable security definer
set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'guest_id',        t.guest_id,
    'name',            g.name,
    'arrival_at',      t.arrival_at,
    'arrival_place',   t.arrival_place,
    'departure_at',    t.departure_at,
    'departure_place', t.departure_place,
    'can_drive',       t.can_drive,
    'diet',            t.diet,
    'notes',           t.notes
  ) order by t.arrival_at nulls last, g.name), '[]'::jsonb)
  from travel t join guests g on g.id = t.guest_id
$$;

create or replace function public.save_travel(p_guest uuid, p jsonb)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if not exists (select 1 from guests where id = p_guest) then
    raise exception 'Unknown guest';
  end if;
  insert into travel (guest_id, arrival_at, arrival_place, departure_at, departure_place, can_drive, diet, notes)
  values (
    p_guest,
    nullif(p->>'arrival_at', '')::timestamp,
    left(coalesce(p->>'arrival_place', ''), 200),
    nullif(p->>'departure_at', '')::timestamp,
    left(coalesce(p->>'departure_place', ''), 200),
    coalesce((p->>'can_drive')::boolean, false),
    left(coalesce(p->>'diet', ''), 300),
    left(coalesce(p->>'notes', ''), 500)
  )
  on conflict (guest_id) do update set
    arrival_at      = excluded.arrival_at,
    arrival_place   = excluded.arrival_place,
    departure_at    = excluded.departure_at,
    departure_place = excluded.departure_place,
    can_drive       = excluded.can_drive,
    diet            = excluded.diet,
    notes           = excluded.notes,
    updated_at      = now();
end $$;
