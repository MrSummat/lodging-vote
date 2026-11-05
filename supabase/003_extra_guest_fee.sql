-- Per-house surcharge for people beyond what the base price includes
-- (e.g. camp beds at €40 per person per night). Run once in Supabase > SQL Editor.
-- Already included in schema.sql for new setups.

alter table public.houses
  add column if not exists included_guests int check (included_guests >= 0),
  add column if not exists extra_guest_fee numeric(10,2) not null default 0 check (extra_guest_fee >= 0);

-- House total for everyone staying: the guest list plus the host.
create or replace function public.effective_total(h public.houses)
returns numeric language sql stable as $$
  select h.total_price + case
    when h.included_guests is null then 0
    else greatest(0, (select count(*) from public.guests) + 1 - h.included_guests) * h.extra_guest_fee
  end
$$;

create or replace function public.host_share(h public.houses)
returns numeric language sql stable as $$
  select least(
    public.effective_total(h),
    case when h.host_mode = 'pct'
      then public.effective_total(h) * least(h.host_value, 100) / 100
      else h.host_value
    end
  )
$$;

revoke execute on function public.effective_total(public.houses) from public, anon, authenticated;

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
        'price_pp',    round((effective_total(h) - host_share(h)) / nullif((select n from g), 0), 2),
        'votes',       (select count(*) from votes v where v.house_id = h.id)
      ) order by h.created_at)
      from houses h), '[]'::jsonb)
  )
  from settings s
$$;

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
        'id',              h.id,
        'name',            h.name,
        'location',        h.location,
        'description',     h.description,
        'link',            h.link,
        'capacity',        h.capacity,
        'highlights',      to_jsonb(h.highlights),
        'images',          to_jsonb(h.images),
        'total_price',     h.total_price,
        'included_guests', h.included_guests,
        'extra_guest_fee', h.extra_guest_fee,
        'effective_total', effective_total(h),
        'host_mode',       h.host_mode,
        'host_value',      h.host_value,
        'votes',           (select count(*) from votes v where v.house_id = h.id)
      ) order by h.created_at)
      from houses h), '[]'::jsonb)
  ) into v_result
  from settings s;
  return v_result;
end $$;

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
    name            = coalesce(nullif(trim(p->>'name'), ''), 'New house'),
    location        = coalesce(p->>'location', ''),
    description     = coalesce(p->>'description', ''),
    link            = coalesce(p->>'link', ''),
    capacity        = nullif(p->>'capacity', '')::int,
    highlights      = array(select jsonb_array_elements_text(coalesce(p->'highlights', '[]'::jsonb))),
    images          = array(select jsonb_array_elements_text(coalesce(p->'images', '[]'::jsonb))),
    total_price     = coalesce(nullif(p->>'total_price', '')::numeric, 0),
    included_guests = nullif(p->>'included_guests', '')::int,
    extra_guest_fee = coalesce(nullif(p->>'extra_guest_fee', '')::numeric, 0),
    host_mode       = coalesce(p->>'host_mode', 'pct'),
    host_value      = coalesce(nullif(p->>'host_value', '')::numeric, 0)
  where id = v_id;
  return v_id;
end $$;
