-- Anonymous messages to the host. Stores no guest id, device token or exact
-- time. Only the admin can read them. Run once in Supabase > SQL Editor.
-- Already included in schema.sql for new setups.

create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  body       text not null check (length(body) between 1 and 2000),
  -- Day only, so a message can't be matched to when someone voted.
  created_on date not null default current_date
);

alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

create or replace function public.send_feedback(p_body text)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if coalesce(trim(p_body), '') = '' then
    raise exception 'Write something first';
  end if;
  insert into feedback (body) values (left(trim(p_body), 2000));
end $$;

-- Random ids, so order within a day reveals nothing either.
create or replace function public.admin_get_feedback(p_key text)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'body', body, 'created_on', created_on)
                     order by created_on desc, id)
    from feedback), '[]'::jsonb);
end $$;

create or replace function public.admin_delete_feedback(p_key text, p_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform assert_admin(p_key);
  delete from feedback where id = p_id;
end $$;

grant execute on function
  public.send_feedback(text),
  public.admin_get_feedback(text),
  public.admin_delete_feedback(text, uuid)
to anon, authenticated;
