-- Lodging vote: Supabase schema.
-- Paste this whole file into Supabase > SQL Editor and run it once.
-- BEFORE RUNNING: change the admin key at the bottom of this file.
--
-- Privacy model: the tables are locked (RLS on, no policies, no grants), so the
-- browser can only call the functions below. Guests see vote tallies and who has
-- voted, never who voted for what. Admin functions require the admin key.

create extension if not exists pgcrypto with schema extensions;

-- Tables ---------------------------------------------------------------------

create table if not exists public.settings (
  id             int primary key default 1 check (id = 1),
  title          text not null default 'Pick our house',
  subtitle       text not null default '',
  price_note     text not null default 'per person, whole stay',
  voting_open    boolean not null default true,
  admin_key_hash text not null
);

create table if not exists public.houses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  location    text not null default '',
  description text not null default '',
  link        text not null default '',
  capacity    int,
  highlights  text[] not null default '{}',
  images      text[] not null default '{}',
  total_price numeric(10,2) not null default 0 check (total_price >= 0),
  host_mode   text not null default 'pct' check (host_mode in ('pct', 'abs')),
  host_value  numeric(10,2) not null default 0 check (host_value >= 0),
  created_at  timestamptz not null default now()
);

create table if not exists public.guests (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

-- One row per guest. device_token lets a guest see their own vote without
-- exposing it to anyone who merely knows their guest id.
create table if not exists public.votes (
  guest_id     uuid primary key references public.guests(id) on delete cascade,
  house_id     uuid not null references public.houses(id) on delete cascade,
  device_token uuid not null,
  updated_at   timestamptz not null default now()
);

alter table public.settings enable row level security;
alter table public.houses   enable row level security;
alter table public.guests   enable row level security;
alter table public.votes    enable row level security;

revoke all on public.settings, public.houses, public.guests, public.votes from anon, authenticated;

-- Helpers --------------------------------------------------------------------

-- What the host pays for a house: a percentage of the total or a fixed amount,
-- never more than the total.
create or replace function public.host_share(h public.houses)
returns numeric language sql immutable as $$
  select least(
    h.total_price,
    case when h.host_mode = 'pct'
      then h.total_price * least(h.host_value, 100) / 100
      else h.host_value
    end
  )
$$;

create or replace function public.assert_admin(p_key text)
returns void language plpgsql stable security definer
set search_path = public, extensions as $$
begin
  if not exists (select 1 from settings where admin_key_hash = crypt(p_key, admin_key_hash)) then
    raise exception 'Invalid admin key' using errcode = '28000';
  end if;
end $$;

-- Guest functions ------------------------------------------------------------

create or replace function public.get_state()
returns jsonb language sql stable security definer
set search_path = public as $$
  with g as (select count(*)::int as n from guests)
  select jsonb_build_object(
    'title',       s.title,
    'subtitle',    s.subtitle,
    'price_note',  s.price_note,
    'voting_open', s.voting_open,
    'guest_count', (select n from g),
    'guests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', gu.id,
        'name', gu.name,
        'voted', exists (select 1 from votes v where v.guest_id = gu.id)
      ) order by gu.name)
      from guests gu), '[]'::jsonb),
    'houses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          h.id,
        'name',        h.name,
        'location',    h.location,
        'description', h.description,
        'capacity',    h.capacity,
        'highlights',  to_jsonb(h.highlights),
        'images',      to_jsonb(h.images),
        'price_pp',    round((h.total_price - host_share(h)) / nullif((select n from g), 0), 2),
        'votes',       (select count(*) from votes v where v.house_id = h.id)
      ) order by h.created_at)
      from houses h), '[]'::jsonb)
  )
  from settings s
$$;

create or replace function public.my_vote(p_guest uuid, p_token uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select house_id from votes where guest_id = p_guest and device_token = p_token
$$;

-- p_house = null removes the guest's vote.
create or replace function public.cast_vote(p_guest uuid, p_house uuid, p_token uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if not (select voting_open from settings) then
    raise exception 'Voting is closed';
  end if;
  if not exists (select 1 from guests where id = p_guest) then
    raise exception 'Unknown guest';
  end if;
  if p_house is null then
    delete from votes where guest_id = p_guest;
    return;
  end if;
  if not exists (select 1 from houses where id = p_house) then
    raise exception 'Unknown house';
  end if;
  insert into votes (guest_id, house_id, device_token)
  values (p_guest, p_house, p_token)
  on conflict (guest_id) do update
    set house_id = excluded.house_id,
        device_token = excluded.device_token,
        updated_at = now();
end $$;

-- Admin functions ------------------------------------------------------------

create or replace function public.admin_get_state(p_key text)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_n int := (select count(*) from guests);
  v_result jsonb;
begin
  perform assert_admin(p_key);
  select jsonb_build_object(
    'title',       s.title,
    'subtitle',    s.subtitle,
    'price_note',  s.price_note,
    'voting_open', s.voting_open,
    'guest_count', v_n,
    'guests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', gu.id,
        'name', gu.name,
        'voted', exists (select 1 from votes v where v.guest_id = gu.id)
      ) order by gu.name)
      from guests gu), '[]'::jsonb),
    'houses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          h.id,
        'name',        h.name,
        'location',    h.location,
        'description', h.description,
        'link',        h.link,
        'capacity',    h.capacity,
        'highlights',  to_jsonb(h.highlights),
        'images',      to_jsonb(h.images),
        'total_price', h.total_price,
        'host_mode',   h.host_mode,
        'host_value',  h.host_value,
        'votes',       (select count(*) from votes v where v.house_id = h.id)
      ) order by h.created_at)
      from houses h), '[]'::jsonb)
  ) into v_result
  from settings s;
  return v_result;
end $$;

create or replace function public.admin_save_settings(p_key text, p jsonb)
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  update settings set
    title       = coalesce(p->>'title', title),
    subtitle    = coalesce(p->>'subtitle', subtitle),
    price_note  = coalesce(p->>'price_note', price_note),
    voting_open = coalesce((p->>'voting_open')::boolean, voting_open)
  where id = 1;
end $$;

-- Creates the house when p has no id, otherwise updates it. Returns the id.
create or replace function public.admin_save_house(p_key text, p jsonb)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  v_id uuid := nullif(p->>'id', '')::uuid;
begin
  perform assert_admin(p_key);
  if v_id is null then
    insert into houses (name) values ('New house') returning id into v_id;
  end if;
  update houses set
    name        = coalesce(nullif(trim(p->>'name'), ''), 'New house'),
    location    = coalesce(p->>'location', ''),
    description = coalesce(p->>'description', ''),
    link        = coalesce(p->>'link', ''),
    capacity    = nullif(p->>'capacity', '')::int,
    highlights  = array(select jsonb_array_elements_text(coalesce(p->'highlights', '[]'::jsonb))),
    images      = array(select jsonb_array_elements_text(coalesce(p->'images', '[]'::jsonb))),
    total_price = coalesce(nullif(p->>'total_price', '')::numeric, 0),
    host_mode   = coalesce(p->>'host_mode', 'pct'),
    host_value  = coalesce(nullif(p->>'host_value', '')::numeric, 0)
  where id = v_id;
  return v_id;
end $$;

create or replace function public.admin_delete_house(p_key text, p_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  delete from houses where id = p_id;
end $$;

create or replace function public.admin_add_guests(p_key text, p_names text[])
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  insert into guests (name)
  select distinct trim(n) from unnest(p_names) as n where trim(n) <> ''
  on conflict (name) do nothing;
end $$;

create or replace function public.admin_delete_guest(p_key text, p_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  delete from guests where id = p_id;
end $$;

create or replace function public.admin_set_key(p_key text, p_new_key text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform assert_admin(p_key);
  if length(coalesce(p_new_key, '')) < 6 then
    raise exception 'New key must be at least 6 characters';
  end if;
  update settings set admin_key_hash = crypt(p_new_key, gen_salt('bf')) where id = 1;
end $$;

-- Permissions ----------------------------------------------------------------

revoke execute on function public.host_share(public.houses) from public, anon, authenticated;
revoke execute on function public.assert_admin(text) from public, anon, authenticated;

grant execute on function
  public.get_state(),
  public.my_vote(uuid, uuid),
  public.cast_vote(uuid, uuid, uuid),
  public.admin_get_state(text),
  public.admin_save_settings(text, jsonb),
  public.admin_save_house(text, jsonb),
  public.admin_delete_house(text, uuid),
  public.admin_add_guests(text, text[]),
  public.admin_delete_guest(text, uuid),
  public.admin_set_key(text, text)
to anon, authenticated;

-- Initial settings: CHANGE THE ADMIN KEY BELOW --------------------------------

insert into public.settings (id, admin_key_hash)
values (1, extensions.crypt('change-me-please', extensions.gen_salt('bf')))
on conflict (id) do nothing;
