-- Travel plans for coordinating cars. Unlike votes, this is visible to every
-- guest on purpose, so people can group into cars. Run once in Supabase >
-- SQL Editor. Already included in schema.sql for new setups.

create table if not exists public.travel (
  guest_id        uuid primary key references public.guests(id) on delete cascade,
  arrival_at      timestamp,
  arrival_place   text not null default '',
  departure_at    timestamp,
  departure_place text not null default '',
  can_drive       boolean not null default false,
  notes           text not null default '',
  updated_at      timestamptz not null default now()
);

alter table public.travel enable row level security;
revoke all on public.travel from anon, authenticated;

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
  insert into travel (guest_id, arrival_at, arrival_place, departure_at, departure_place, can_drive, notes)
  values (
    p_guest,
    nullif(p->>'arrival_at', '')::timestamp,
    left(coalesce(p->>'arrival_place', ''), 200),
    nullif(p->>'departure_at', '')::timestamp,
    left(coalesce(p->>'departure_place', ''), 200),
    coalesce((p->>'can_drive')::boolean, false),
    left(coalesce(p->>'notes', ''), 500)
  )
  on conflict (guest_id) do update set
    arrival_at      = excluded.arrival_at,
    arrival_place   = excluded.arrival_place,
    departure_at    = excluded.departure_at,
    departure_place = excluded.departure_place,
    can_drive       = excluded.can_drive,
    notes           = excluded.notes,
    updated_at      = now();
end $$;

grant execute on function public.get_travel(), public.save_travel(uuid, jsonb) to anon, authenticated;
