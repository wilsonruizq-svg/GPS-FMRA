-- GPS-FMRA — Historial: admin de grupo ve puntos de cualquier integrante
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: location_history_admin_ok = true
--
-- Miembros: solo propio (RPC list_own / list_group_location_history).
-- Admin (group_admin/org_admin): list_member_location_history(p_user_id).
-- RLS SELECT directo sigue own-only; admin lee vía security definer.
-- Idempotente. No incluye secretos.

-- Mantener own-only en RLS (sin peers vía SELECT directo).
drop policy if exists location_history_select_visible on public.location_history;
drop policy if exists location_history_select_own on public.location_history;
create policy location_history_select_own
  on public.location_history for select to authenticated
  using (user_id = auth.uid());

create or replace function public.list_member_location_history(
  p_group_id uuid,
  p_user_id uuid,
  p_hours integer default 24,
  p_limit integer default 200
)
returns table (
  id uuid,
  user_id uuid,
  lat double precision,
  lon double precision,
  accuracy_m double precision,
  recorded_at timestamptz,
  display_name text
)
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_hours integer := greatest(1, least(coalesce(p_hours, 24), 72));
  v_limit integer := greatest(1, least(coalesce(p_limit, 200), 500));
  v_uid uuid := auth.uid();
  v_target uuid := p_user_id;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null or v_target is null then
    raise exception 'group and user required';
  end if;
  if not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not a group member';
  end if;

  -- Propio: siempre. Ajeno: solo admin del grupo.
  if v_target <> v_uid and not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'not allowed to view this member history';
  end if;

  -- El objetivo debe ser miembro activo del grupo.
  if not public.is_active_member(p_group_id, v_target) then
    raise exception 'target is not an active member';
  end if;

  return query
  select
    h.id,
    h.user_id,
    h.lat,
    h.lon,
    h.accuracy_m,
    h.recorded_at,
    p.display_name
  from public.location_history h
  left join public.profiles p on p.id = h.user_id
  where h.user_id = v_target
    and h.recorded_at >= (now() at time zone 'utc') - make_interval(hours => v_hours)
  order by h.recorded_at desc
  limit v_limit;
end;
$$;

revoke all on function public.list_member_location_history(uuid, uuid, integer, integer) from public;
revoke all on function public.list_member_location_history(uuid, uuid, integer, integer) from anon;
grant execute on function public.list_member_location_history(uuid, uuid, integer, integer) to authenticated;

comment on function public.list_member_location_history(uuid, uuid, integer, integer) is
  'Historial de un integrante del grupo. Admin ve cualquiera; miembro solo el suyo.';

notify pgrst, 'reload schema';

select
  has_function_privilege(
    'authenticated',
    'public.list_member_location_history(uuid, uuid, integer, integer)',
    'execute'
  ) as location_history_admin_ok;
