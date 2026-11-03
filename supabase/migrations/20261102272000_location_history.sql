-- GPS-FMRA — Historial de ubicaciones (consent-first)
-- =====================================================================
-- Mantiene location_updates (última conocida) Y guarda filas de historial.
-- Solo se escribe con la app cuando hay consentimiento activo.
-- Lectura vía can_view_location (mismo criterio que el mapa en vivo).
--
-- APPLY: SQL Editor → pegar TODO → Run.
-- Éxito esperado: Success + verificación location_history_ok = true.
-- Idempotente. No incluye secretos.
--
create table if not exists public.location_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  accuracy_m double precision,
  recorded_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists location_history_user_recorded_idx
  on public.location_history (user_id, recorded_at desc);

create index if not exists location_history_recorded_idx
  on public.location_history (recorded_at desc);

comment on table public.location_history is
  'Historial GPS consent-first. SELECT vía can_view_location; INSERT solo propio.';

alter table public.location_history enable row level security;
alter table public.location_history force row level security;

drop policy if exists location_history_select_visible on public.location_history;
create policy location_history_select_visible
  on public.location_history for select to authenticated
  using (public.can_view_location(user_id));

drop policy if exists location_history_insert_own on public.location_history;
create policy location_history_insert_own
  on public.location_history for insert to authenticated
  with check (user_id = auth.uid());

-- Sin UPDATE/DELETE de clientes (retención vía job futuro / SQL).
grant select, insert on table public.location_history to authenticated;
grant all on table public.location_history to service_role;
grant all on table public.location_history to postgres;

-- RPC: historial reciente visible del grupo (default 24 h, máx 72 h).
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
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_active_member(p_group_id, auth.uid()) then
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
  where h.recorded_at >= (now() at time zone 'utc') - make_interval(hours => v_hours)
    and public.can_view_location(h.user_id, auth.uid())
  order by h.recorded_at desc
  limit v_limit;
end;
$$;

revoke all on function public.list_group_location_history(uuid, integer, integer) from public;
revoke all on function public.list_group_location_history(uuid, integer, integer) from anon;
grant execute on function public.list_group_location_history(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.location_history') is not null as location_history_ok,
  has_table_privilege('authenticated', 'public.location_history', 'INSERT') as history_insert_granted;
