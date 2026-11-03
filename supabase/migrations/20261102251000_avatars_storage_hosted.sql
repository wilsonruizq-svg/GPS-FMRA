-- GPS-FMRA — Bucket `avatars` para Supabase HOSTED (SQL Editor)
-- =====================================================================
-- USA ESTE ARCHIVO si viste:
--   ERROR: 42501: must be owner of table objects
-- al correr 20261102250000_avatars_storage.sql
--
-- Causa: ese script antiguo hacía COMMENT ON storage.objects (requiere
-- dueño de la tabla). Este archivo NO toca ownership ni ALTER/COMMENT
-- sobre storage.objects — solo bucket + policies.
--
-- APPLY (Wilson):
--   1. Supabase Dashboard → SQL Editor → New query
--   2. Pega TODO este archivo
--   3. Run
-- Éxito esperado: Success. No rows returned
--   (o Success con 1 fila del upsert del bucket)
-- Luego: Storage → Buckets → debe existir "avatars" (Public).
--
-- Idempotente. No incluye secretos.
-- sos_events / device_push_tokens NO van aquí (si ya los aplicaste, OK).

-- 1) Bucket público (lectura vía URL pública de la app).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152, -- 2 MiB
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 2) Policies en storage.objects (sin COMMENT / ALTER TABLE).
-- Lectura pública del bucket avatars.
drop policy if exists avatars_public_read on storage.objects;
create policy avatars_public_read
  on storage.objects for select
  to public
  using (bucket_id = 'avatars');

-- Subir solo a carpeta propia: {auth.uid()}/...
drop policy if exists avatars_insert_own on storage.objects;
create policy avatars_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Fin. No hay COMMENT ON / ALTER TABLE storage.objects.
