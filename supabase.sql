-- Dawam cloud copy. Run once in Supabase → SQL Editor.
-- Everyone with the link shares one copy, stored under the code 'dawam-shared-main'.
-- The state table is reached only through the two functions below.

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
revoke execute on function public.dawam_get(text) from authenticated;
revoke execute on function public.dawam_put(text, jsonb) from authenticated;

-- one shared copy: start it from the fullest existing copy
insert into public.dawam_state (code, data, updated_at)
select 'dawam-shared-main', data, now()
from public.dawam_state
where code <> 'dawam-shared-main'
order by (select count(*) from jsonb_object_keys(coalesce(data->'days','{}'::jsonb))) desc, updated_at desc
limit 1
on conflict (code) do nothing;

-- love notes written from admin.html, shown as tasks in the app until she taps the heart
create table if not exists public.dawam_messages (
  id         bigint generated always as identity primary key,
  body       text not null check (length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  hearted_at timestamptz
);

alter table public.dawam_messages enable row level security;
-- open on purpose: anyone with the link may read, write and heart
create policy "dawam messages open read"   on public.dawam_messages for select to anon using (true);
create policy "dawam messages open insert" on public.dawam_messages for insert to anon with check (hearted_at is null);
create policy "dawam messages open update" on public.dawam_messages for update to anon using (true) with check (true);
create policy "dawam messages open delete" on public.dawam_messages for delete to anon using (true);
grant select, insert, update, delete on public.dawam_messages to anon;
