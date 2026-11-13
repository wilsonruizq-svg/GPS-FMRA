-- GPS-FMRA — Historial: solo filas del usuario autenticado (auth.uid())
-- =====================================================================
-- Problema: SELECT vía can_view_location + RPC list_group_location_history
-- devolvían historial de compañeros (p. ej. admin) a todos los teléfonos.
--
-- Fix:
--   1) RLS SELECT: user_id = auth.uid()
--   2) RPC list_group_location_history: filtra h.user_id = auth.uid()
--   3) RPC list_own_location_history: alias explícito (mismo resultado)
-- INSERT ya era user_id = auth.uid() (sin cambio).
--
-- APPLY: pegar TODO en SQL Editor → Run.
-- Éxito: history_own_only_ok = true
-- Idempotente. No incluye secretos.

-- ---------------------------------------------------------------------------
-- RLS: historial es privado del dueño (no peers)
-- ---------------------------------------------------------------------------
drop policy if exists location_history_select_visible on public.location_history;
drop policy if exists location_history_select_own on public.location_history;
create policy location_history_select_own
  on public.location_history for select to authenticated
  using (user_id = auth.uid());

-- Reafirmar INSERT propio
drop policy if exists location_history_insert_own on public.location_history;
create policy location_history_insert_own
  on public.location_history for insert to authenticated
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- RPC existente: solo historial del caller en el grupo
-- ---------------------------------------------------------------------------
create or replace function public.list_group_location_history(
  p_group_id uuid,
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
security definer
set search_path = public
set row_security = off
as $$
declare
  v_hours integer := greatest(1, least(coalesce(p_hours, 24), 72));
  v_limit integer := greatest(1, least(coalesce(p_limit, 200), 500));
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not a group member';
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
  join public.group_memberships gm
    on gm.user_id = h.user_id
   and gm.group_id = p_group_id
   and gm.status = 'active'
  left join public.profiles p on p.id = h.user_id
  where h.user_id = v_uid
    and h.recorded_at >= (now() at time zone 'utc') - make_interval(hours => v_hours)
  order by h.recorded_at desc
  limit v_limit;
end;
$$;

revoke all on function public.list_group_location_history(uuid, integer, integer) from public;
revoke all on function public.list_group_location_history(uuid, integer, integer) from anon;
grant execute on function public.list_group_location_history(uuid, integer, integer) to authenticated;

comment on function public.list_group_location_history(uuid, integer, integer) is
  'Historial GPS propio (auth.uid) del grupo. No expone puntos de otros miembros.';

-- ---------------------------------------------------------------------------
-- RPC explícito: list_own_location_history (misma semántica)
-- ---------------------------------------------------------------------------
create or replace function public.list_own_location_history(
  p_group_id uuid,
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
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select * from public.list_group_location_history(p_group_id, p_hours, p_limit);
$$;

revoke all on function public.list_own_location_history(uuid, integer, integer) from public;
revoke all on function public.list_own_location_history(uuid, integer, integer) from anon;
grant execute on function public.list_own_location_history(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.location_history') is not null as history_own_only_ok,
  (
    select pg_get_functiondef('public.list_group_location_history(uuid,integer,integer)'::regprocedure)
    like '%h.user_id = v_uid%'
  ) as rpc_filters_auth_uid;
