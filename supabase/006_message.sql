-- A personal note from the host, shown to guests in its own section.
-- Run once in Supabase > SQL Editor. Already included in schema.sql for new setups.

alter table public.settings
  add column if not exists message_title text not null default '',
  add column if not exists message       text not null default '';

-- First draft, only if no note has been written yet. Edit it in the admin page.
update public.settings set
  message_title = '💌 Before you vote',
  message = $draft$Honestly, booking a house or building a website is the easy part. The hard part is making this weekend feel like a celebration, not a bill or an obligation.

So here's the plan:
🏡 I'm covering a third of the house. The rest is split between the 19 of you.
🛒 I'll take care of the food and drinks, and we'll split that too. Veggie, vegan or allergic? Tell me below and there'll be plenty for you.
🗳️ You choose the house, so you also choose how much we spend.

Please don't get me a gift. You making the trip is the gift, and I'd much rather your money goes on getting here.

And if it's still too much right now, I completely understand. No explanations needed. We'll celebrate another time, and I love you just the same ❤️$draft$
where id = 1 and message = '';

create or replace function public.get_state()
returns jsonb language sql stable security definer
set search_path = public as $$
  with g as (select count(*)::int as n from guests)
  select jsonb_build_object(
    'title',         s.title,
    'subtitle',      s.subtitle,
    'message_title', s.message_title,
    'message',       s.message,
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
    price_note    = coalesce(p->>'price_note', price_note),
    voting_open   = coalesce((p->>'voting_open')::boolean, voting_open)
  where id = 1;
end $$;
