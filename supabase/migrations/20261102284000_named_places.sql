-- GPS-FMRA — Lugares con nombre (guardar / compartir pin)
-- APPLY: SQL Editor → Run. Éxito: named_places_ok = true

create table if not exists public.named_places (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  group_id uuid references public.family_groups (id) on delete cascade,
  name text not null
    check (char_length(trim(name)) > 0 and char_length(name) <= 80),
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  created_at timestamptz not null default now()
);

create index if not exists named_places_owner_idx
  on public.named_places (owner_id, created_at desc);

create index if not exists named_places_group_idx
  on public.named_places (group_id, created_at desc)
  where group_id is not null;

comment on table public.named_places is
  'Pin con nombre: group_id null = solo dueño; con group_id = visible al grupo.';

alter table public.named_places enable row level security;
alter table public.named_places force row level security;

drop policy if exists named_places_select on public.named_places;
create policy named_places_select
  on public.named_places for select to authenticated
  using (
    owner_id = auth.uid()
    or (
      group_id is not null
      and public.is_active_member(group_id)
    )
  );

drop policy if exists named_places_insert_own on public.named_places;
create policy named_places_insert_own
  on public.named_places for insert to authenticated
  with check (
    owner_id = auth.uid()
    and (
      group_id is null
      or public.is_active_member(group_id)
    )
  );

drop policy if exists named_places_delete_own on public.named_places;
create policy named_places_delete_own
  on public.named_places for delete to authenticated
  using (owner_id = auth.uid());

grant select, insert, delete on table public.named_places to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.named_places') is not null as named_places_ok;
