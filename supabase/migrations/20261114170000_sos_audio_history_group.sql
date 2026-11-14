-- GPS-FMRA — Audio de emergencia SOS (por evento, no feed grupal)
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: sos_audio_emergency_ok = true
-- Requiere bucket sos-audio (20261114150000 / docs/sos-audio-storage.sql).
--
-- Política: miembros del grupo del sos_event pueden LEER el objeto
--   {user_id}/{sos_id}.m4a  (rescate). No es historial social de audios.
-- Idempotente. No incluye secretos.

drop policy if exists sos_audio_select_own on storage.objects;
drop policy if exists sos_audio_select_group on storage.objects;
create policy sos_audio_select_group
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

-- Helper opcional: ¿hay audio para este SOS? (miembro del grupo).
create or replace function public.sos_audio_available(p_sos_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_group uuid;
  v_sender uuid;
  v_path text;
begin
  if v_uid is null then
    return false;
  end if;
  select group_id, user_id into v_group, v_sender
  from public.sos_events
  where id = p_sos_id;
  if v_group is null then
    return false;
  end if;
  if not public.is_active_member(v_group, v_uid) then
    return false;
  end if;
  v_path := v_sender::text || '/' || p_sos_id::text || '.m4a';
  return exists (
    select 1 from storage.objects o
    where o.bucket_id = 'sos-audio' and o.name = v_path
  );
end;
$$;

revoke all on function public.sos_audio_available(uuid) from public;
revoke all on function public.sos_audio_available(uuid) from anon;
grant execute on function public.sos_audio_available(uuid) to authenticated;

-- Quitar RPC de listado social si existió en un APPLY intermedio.
drop function if exists public.list_group_sos_audio(uuid, integer);

notify pgrst, 'reload schema';

select
  has_function_privilege(
    'authenticated',
    'public.sos_audio_available(uuid)',
    'execute'
  ) as sos_audio_emergency_ok;
