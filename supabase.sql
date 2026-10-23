-- Dawam cloud copy. Run once in Supabase → SQL Editor.
-- The table itself is closed; the app reaches it only through the two
-- functions below, and only with the sync code saved in the app's settings.

create table if not exists public.dawam_state (
  code       text primary key check (length(code) >= 12),
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.dawam_state enable row level security;
revoke all on public.dawam_state from anon, authenticated;

create or replace function public.dawam_get(p_code text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select data from public.dawam_state where code = p_code;
$$;

-- keeps the newer copy: an older phone cannot overwrite newer data
create or replace function public.dawam_put(p_code text, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if length(p_code) < 12 then
    raise exception 'sync code too short';
  end if;
  insert into public.dawam_state (code, data, updated_at)
  values (p_code, p_data, now())
  on conflict (code) do update
    set data = excluded.data, updated_at = now()
    where coalesce((public.dawam_state.data->>'updatedAt')::bigint, 0)
       <= coalesce((excluded.data->>'updatedAt')::bigint, 0);
end;
$$;

revoke all on function public.dawam_get(text) from public;
revoke all on function public.dawam_put(text, jsonb) from public;
grant execute on function public.dawam_get(text) to anon;
grant execute on function public.dawam_put(text, jsonb) to anon;
