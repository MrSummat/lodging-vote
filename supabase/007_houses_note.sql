-- A short info note shown just above the house cards.
-- Run once in Supabase > SQL Editor. Already included in schema.sql for new setups.

alter table public.settings
  add column if not exists houses_note text not null default '';

-- Move the Girona pre-booking out of the header, only if not done yet.
update public.settings set
  houses_note = $n$📌 Girona is pre-booked just in case: it's the only one with free cancellation (until 11 Nov), real beds for all and late check-out. But it's your call!$n$,
  subtitle = $s$📅 Fri 11 → Sun 13 December

🗳️ Vote by Sun 8 Nov 🙏$s$
where id = 1 and houses_note = '';

create or replace function public.get_state()
returns jsonb language sql stable security definer
set search_path = public as $$
  with g as (select count(*)::int as n from guests)
  select jsonb_build_object(
    'title',         s.title,
    'subtitle',      s.subtitle,
    'message_title', s.message_title,
    'message',       s.message,
    'houses_note',   s.houses_note,
    'price_note',    s.price_note,
    'voting_open',   s.voting_open,
    'guest_count',   (select n from g),
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
    'title',         s.title,
    'subtitle',      s.subtitle,
    'message_title', s.message_title,
    'message',       s.message,
    'houses_note',   s.houses_note,
    'price_note',    s.price_note,
    'voting_open',   s.voting_open,
    'guest_count',   v_n,
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
        'included_guests', h.included_guests,
        'extra_guest_fee', h.extra_guest_fee,
        'effective_total', effective_total(h),
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
    title         = coalesce(p->>'title', title),
    subtitle      = coalesce(p->>'subtitle', subtitle),
    message_title = coalesce(p->>'message_title', message_title),
    message       = coalesce(p->>'message', message),
    houses_note   = coalesce(p->>'houses_note', houses_note),
    price_note    = coalesce(p->>'price_note', price_note),
    voting_open   = coalesce((p->>'voting_open')::boolean, voting_open)
  where id = 1;
end $$;
