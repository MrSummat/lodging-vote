-- Stop sending listing links to guests (admin_get_state still returns them).
-- Run once in Supabase > SQL Editor. Already included in schema.sql for new setups.

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
