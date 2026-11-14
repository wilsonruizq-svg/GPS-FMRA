-- GPS-FMRA — Storage para audio de SOS (GF-31)
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: sos_audio_ok = true
-- Idempotente. No incluye secretos.
--
-- App graba mic mientras SOS activo y sube a:
--   bucket sos-audio / {auth.uid}/{sos_id}.m4a
-- Sin este SQL: grabación solo local (best-effort).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'sos-audio',
  'sos-audio',
  false,
  10485760,
  array['audio/mp4', 'audio/mpeg', 'audio/aac', 'audio/m4a']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists sos_audio_select_own on storage.objects;
create policy sos_audio_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'sos-audio'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1
        from public.sos_events s
        where s.id::text = replace(split_part(name, '/', 2), '.m4a', '')
          and public.is_active_member(s.group_id, auth.uid())
      )
    )
  );

drop policy if exists sos_audio_insert_own on storage.objects;
create policy sos_audio_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'sos-audio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists sos_audio_update_own on storage.objects;
create policy sos_audio_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'sos-audio'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'sos-audio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

notify pgrst, 'reload schema';

select
  exists (select 1 from storage.buckets where id = 'sos-audio') as sos_audio_ok;
