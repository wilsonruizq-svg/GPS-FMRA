-- GPS-FMRA GF-70 — Categorías personales (Solo yo) + grupales
-- APPLY: SQL Editor → Run completo.
-- Éxito: personal_place_categories_ok = true
--
-- place_categories.group_id NULL = carpeta solo del created_by.
-- named_places con group_id NULL pueden usar esas categorías.

-- 1) group_id opcional
alter table public.place_categories
  alter column group_id drop not null;

comment on table public.place_categories is
  'Carpetas de ubicaciones: group_id = grupo familiar; '
  'group_id NULL = personal (Solo yo) del created_by.';

create unique index if not exists place_categories_personal_name_uidx
  on public.place_categories (created_by, lower(trim(name)))
  where group_id is null;

create index if not exists place_categories_personal_owner_idx
  on public.place_categories (created_by, created_at)
  where group_id is null;

-- 2) RLS: personal = dueño; grupal = miembro activo
drop policy if exists place_categories_select on public.place_categories;
create policy place_categories_select
  on public.place_categories for select to authenticated
  using (
    (
      group_id is null
      and created_by = auth.uid()
    )
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

drop policy if exists place_categories_insert on public.place_categories;
create policy place_categories_insert
  on public.place_categories for insert to authenticated
  with check (
    created_by = auth.uid()
    and (
      group_id is null
      or public.is_active_member(group_id, auth.uid())
    )
  );

drop policy if exists place_categories_update on public.place_categories;
create policy place_categories_update
  on public.place_categories for update to authenticated
  using (
    (
      group_id is null
      and created_by = auth.uid()
    )
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  )
  with check (
    (
      group_id is null
      and created_by = auth.uid()
    )
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

drop policy if exists place_categories_delete on public.place_categories;
create policy place_categories_delete
  on public.place_categories for delete to authenticated
  using (
    created_by = auth.uid()
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

-- 3) save_named_place: categoría personal si p_group_id es null
drop function if exists public.save_named_place(
  text, double precision, double precision, uuid, text, text, uuid
);

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
  v_cat_owner uuid;
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
    select c.group_id, c.created_by
      into v_cat_group, v_cat_owner
    from public.place_categories c
    where c.id = v_cat;
    if not found then
      raise exception 'invalid_category';
    end if;

    if p_group_id is null then
      -- Solo yo: categoría personal del mismo usuario
      if v_cat_group is not null or v_cat_owner is distinct from v_uid then
        raise exception 'category_group_mismatch';
      end if;
    else
      if v_cat_group is null or p_group_id <> v_cat_group then
        raise exception 'category_group_mismatch';
      end if;
      if not public.is_active_member(v_cat_group, v_uid) then
        raise exception 'not_group_member';
      end if;
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

-- 4) create_place_category: p_group_id null = personal
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
  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 60 then
    raise exception 'invalid_name';
  end if;

  if p_group_id is not null then
    if not public.is_active_member(p_group_id, v_uid) then
      raise exception 'not_group_member';
    end if;
  end if;

  insert into public.profiles (id, display_name)
  values (v_uid, 'Usuario')
  on conflict (id) do nothing;

  if p_group_id is null then
    select * into v_row
    from public.place_categories
    where group_id is null
      and created_by = v_uid
      and lower(trim(name)) = lower(v_name)
    limit 1;
  else
    select * into v_row
    from public.place_categories
    where group_id = p_group_id
      and lower(trim(name)) = lower(v_name)
    limit 1;
  end if;

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

-- 5) Verificación
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'place_categories'
      and column_name = 'group_id'
      and is_nullable = 'YES'
  ) then
    raise exception 'personal_place_categories_failed: group_id still NOT NULL';
  end if;
  raise notice 'personal_place_categories_ok = true';
end $$;
