-- GPS-FMRA — Audio de emergencia SOS (por evento + historial del grupo)
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: sos_audio_emergency_ok = true
-- Requiere bucket sos-audio (docs/sos-audio-storage.sql).
--
-- Lectura Storage: miembros del grupo del sos_event.
-- Historial: solo eventos SOS con archivo subido (emergencia, no chat).
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

-- Historial de emergencias con audio (grupo). Solo SOS con archivo.
drop function if exists public.list_group_sos_audio(uuid, integer);
drop function if exists public.list_group_sos_emergency_audio(uuid, integer);

create or replace function public.list_group_sos_emergency_audio(
  p_group_id uuid,
  p_limit integer default 50
)
returns table (
  sos_id uuid,
  user_id uuid,
  display_name text,
  status text,
  created_at timestamptz,
  storage_path text
)
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null then
    raise exception 'group required';
  end if;
  if not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not a member of this group';
  end if;

  return query
  select
    s.id as sos_id,
    s.user_id,
    coalesce(nullif(trim(p.display_name), ''), 'Integrante') as display_name,
    s.status,
    s.created_at,
    (s.user_id::text || '/' || s.id::text || '.m4a') as storage_path
  from public.sos_events s
  left join public.profiles p on p.id = s.user_id
  where s.group_id = p_group_id
    and exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'sos-audio'
        and o.name = (s.user_id::text || '/' || s.id::text || '.m4a')
    )
  order by s.created_at desc
  limit v_lim;
end;
$$;

revoke all on function public.list_group_sos_emergency_audio(uuid, integer) from public;
revoke all on function public.list_group_sos_emergency_audio(uuid, integer) from anon;
grant execute on function public.list_group_sos_emergency_audio(uuid, integer) to authenticated;

notify pgrst, 'reload schema';

select
  has_function_privilege(
    'authenticated',
    'public.sos_audio_available(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_group_sos_emergency_audio(uuid, integer)',
    'execute'
  ) as sos_audio_emergency_ok;
