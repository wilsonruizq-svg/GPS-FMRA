-- GPS-FMRA — Lugares con foto + categorías (carpetas) por grupo familiar
-- APPLY: SQL Editor → Run completo.
-- Éxito: named_places_photos_ok = true
--
-- Categorías (Restaurantes, Negocios…) ≠ del tracking familiar.
-- Visibles a todo el grupo; foto en Storage place-photos.

-- 1) Categorías / carpetas de ubicaciones (por family_group)
create table if not exists public.place_categories (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  name text not null
    check (char_length(trim(name)) > 0 and char_length(name) <= 60),
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index if not exists place_categories_group_name_uidx
  on public.place_categories (group_id, lower(trim(name)));

create index if not exists place_categories_group_idx
  on public.place_categories (group_id, created_at);

comment on table public.place_categories is
  'Carpetas para organizar ubicaciones (restaurantes, negocios…). '
  'Pertenecen a un family_group; visibles a miembros activos.';

alter table public.place_categories enable row level security;
alter table public.place_categories force row level security;

drop policy if exists place_categories_select on public.place_categories;
create policy place_categories_select
  on public.place_categories for select to authenticated
  using (public.is_active_member(group_id, auth.uid()));

drop policy if exists place_categories_insert on public.place_categories;
create policy place_categories_insert
  on public.place_categories for insert to authenticated
  with check (
    created_by = auth.uid()
    and public.is_active_member(group_id, auth.uid())
  );

drop policy if exists place_categories_update on public.place_categories;
create policy place_categories_update
  on public.place_categories for update to authenticated
  using (public.is_active_member(group_id, auth.uid()))
  with check (public.is_active_member(group_id, auth.uid()));

drop policy if exists place_categories_delete on public.place_categories;
create policy place_categories_delete
  on public.place_categories for delete to authenticated
  using (
    created_by = auth.uid()
    or public.is_active_member(group_id, auth.uid())
  );

grant select, insert, update, delete on table public.place_categories to authenticated;

-- 2) Columnas en named_places
alter table public.named_places
  add column if not exists description text
    check (
      description is null
      or char_length(description) <= 280
    );

alter table public.named_places
  add column if not exists photo_path text
    check (
      photo_path is null
      or char_length(trim(photo_path)) > 0
    );

alter table public.named_places
  add column if not exists category_id uuid
    references public.place_categories (id) on delete set null;

create index if not exists named_places_category_idx
  on public.named_places (category_id)
  where category_id is not null;

comment on column public.named_places.description is
  'Detalle del lugar (restaurante/negocio), máx. 280.';
comment on column public.named_places.photo_path is
  'Ruta en bucket place-photos: {owner_id}/{place_id}.jpg';
comment on column public.named_places.category_id is
  'Carpeta/categoría de organización (opcional).';

-- 3) RLS update/delete named_places
drop policy if exists named_places_update_own on public.named_places;
create policy named_places_update_own
  on public.named_places for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists named_places_delete_own on public.named_places;
create policy named_places_delete_own
  on public.named_places for delete to authenticated
  using (
    owner_id = auth.uid()
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

grant select, insert, update, delete on table public.named_places to authenticated;

-- 4) RPC save_named_place ampliado
drop function if exists public.save_named_place(text, double precision, double precision, uuid);
drop function if exists public.save_named_place(text, double precision, double precision, uuid, text, text);
drop function if exists public.save_named_place(text, double precision, double precision, uuid, text, text, uuid);

create or replace function public.save_named_place(
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_group_id uuid default null,
  p_description text default null,
  p_photo_path text default null,
  p_category_id uuid default null
)
returns public.named_places
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(p_name);
  v_desc text := nullif(trim(coalesce(p_description, '')), '');
  v_photo text := nullif(trim(coalesce(p_photo_path, '')), '');
  v_cat uuid := p_category_id;
  v_cat_group uuid;
  v_row public.named_places;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 80 then
    raise exception 'invalid_name';
  end if;

  if v_desc is not null and char_length(v_desc) > 280 then
    raise exception 'invalid_description';
  end if;

  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90
     or p_lon < -180 or p_lon > 180 then
    raise exception 'invalid_coordinates';
  end if;

  if p_group_id is not null and not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not_group_member';
  end if;

  if v_cat is not null then
    select c.group_id into v_cat_group
    from public.place_categories c
    where c.id = v_cat;
    if v_cat_group is null then
      raise exception 'invalid_category';
    end if;
    if p_group_id is null or p_group_id <> v_cat_group then
      raise exception 'category_group_mismatch';
    end if;
    if not public.is_active_member(v_cat_group, v_uid) then
      raise exception 'not_group_member';
    end if;
  end if;

  insert into public.profiles (id, display_name)
  values (v_uid, 'Usuario')
  on conflict (id) do nothing;

  insert into public.named_places (
    owner_id, group_id, name, lat, lon, description, photo_path, category_id
  )
  values (
    v_uid, p_group_id, v_name, p_lat, p_lon, v_desc, v_photo, v_cat
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.save_named_place(
  text, double precision, double precision, uuid, text, text, uuid
) from public;
grant execute on function public.save_named_place(
  text, double precision, double precision, uuid, text, text, uuid
) to authenticated;

-- 5) RPC crear categoría
create or replace function public.create_place_category(
  p_group_id uuid,
  p_name text
)
returns public.place_categories
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(p_name);
  v_row public.place_categories;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_group_id is null or not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not_group_member';
  end if;
  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 60 then
    raise exception 'invalid_name';
  end if;

  insert into public.profiles (id, display_name)
  values (v_uid, 'Usuario')
  on conflict (id) do nothing;

  insert into public.place_categories (group_id, name, created_by)
  values (p_group_id, v_name, v_uid)
  on conflict (group_id, lower(trim(name))) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row
    from public.place_categories
    where group_id = p_group_id
      and lower(trim(name)) = lower(v_name)
    limit 1;
  end if;

  return v_row;
end;
$$;

-- unique index uses expression — ON CONFLICT needs matching constraint.
-- Recreate as unique constraint on (group_id, name_norm) via generated col if needed.
-- Fallback: handle duplicate in app; for ON CONFLICT use unique index name:
-- Postgres ON CONFLICT requires constraint/unique index columns, not expressions easily.
-- Simpler: drop expression unique and use plain unique on (group_id, name) case-sensitive,
-- or catch unique_violation. Rewrite create without ON CONFLICT expression:

drop function if exists public.create_place_category(uuid, text);

create or replace function public.create_place_category(
  p_group_id uuid,
  p_name text
)
returns public.place_categories
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(p_name);
  v_row public.place_categories;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_group_id is null or not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not_group_member';
  end if;
  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 60 then
    raise exception 'invalid_name';
  end if;

  insert into public.profiles (id, display_name)
  values (v_uid, 'Usuario')
  on conflict (id) do nothing;

  select * into v_row
  from public.place_categories
  where group_id = p_group_id
    and lower(trim(name)) = lower(v_name)
  limit 1;

  if v_row.id is not null then
    return v_row;
  end if;

  insert into public.place_categories (group_id, name, created_by)
  values (p_group_id, v_name, v_uid)
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.create_place_category(uuid, text) from public;
grant execute on function public.create_place_category(uuid, text) to authenticated;

-- 6) Storage bucket place-photos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'place-photos',
  'place-photos',
  true,
  3145728,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists place_photos_public_read on storage.objects;
create policy place_photos_public_read
  on storage.objects for select
  to public
  using (bucket_id = 'place-photos');

drop policy if exists place_photos_insert_own on storage.objects;
create policy place_photos_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'place-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists place_photos_update_own on storage.objects;
create policy place_photos_update_own
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'place-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'place-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists place_photos_delete_own on storage.objects;
create policy place_photos_delete_own
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'place-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

notify pgrst, 'reload schema';

select
  to_regclass('public.named_places') is not null
  and to_regclass('public.place_categories') is not null
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'named_places'
      and column_name = 'category_id'
  )
  and exists (
    select 1 from storage.buckets where id = 'place-photos'
  ) as named_places_photos_ok;
