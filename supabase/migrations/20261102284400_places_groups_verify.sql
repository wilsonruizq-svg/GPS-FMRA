-- GPS-FMRA — Verificación Grupos + ubicaciones/fotos
-- APPLY en SQL Editor si la pestaña Grupos no lista carpetas/lugares.
-- Éxito: places_groups_verify_ok = true
--
-- Recarga schema API + grants + bucket.

grant select, insert, update, delete on table public.place_categories to authenticated;
grant select, insert, update, delete on table public.named_places to authenticated;

-- Asegura policies select (miembros del grupo ven categorías y lugares)
drop policy if exists place_categories_select on public.place_categories;
create policy place_categories_select
  on public.place_categories for select to authenticated
  using (public.is_active_member(group_id, auth.uid()));

drop policy if exists named_places_select on public.named_places;
create policy named_places_select
  on public.named_places for select to authenticated
  using (
    owner_id = auth.uid()
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

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

notify pgrst, 'reload schema';

select
  to_regclass('public.place_categories') is not null
  and to_regclass('public.named_places') is not null
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'named_places'
      and column_name = 'category_id'
  )
  and exists (select 1 from storage.buckets where id = 'place-photos')
  as places_groups_verify_ok;
