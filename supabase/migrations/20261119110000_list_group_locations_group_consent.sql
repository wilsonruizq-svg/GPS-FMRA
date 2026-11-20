-- GPS-FMRA — GF-74b: list_group_locations exige consent del grupo pedido
-- APPLY: pegar en SQL Editor → Run (idempotente).
--
-- Repro Wilson: miembro crea Grupo M y sigue en Grupo W. Su pin “vive” en M
-- (selfFix local / consent de M). En W, peers solo veían update al cambiar el
-- dropdown (fetch puntual). can_view_location acepta consent de CUALQUIER
-- grupo compartido; para el mapa por grupo hace falta consent de ESE grupo.
--
-- Esta RPC exige location_consents activo con group_id = p_group_id.
-- El cliente GF-74 + trigger 20261119100000 mantienen consent en todas las
-- membresías aunque el dropdown del sharer se quede en M.

create or replace function public.list_group_locations(p_group_id uuid)
returns table (
  user_id uuid,
  lat double precision,
  lon double precision,
  accuracy_m double precision,
  recorded_at timestamptz
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    lu.user_id,
    lu.lat,
    lu.lon,
    lu.accuracy_m,
    lu.recorded_at
  from public.location_updates lu
  inner join public.group_memberships gm
    on gm.user_id = lu.user_id
   and gm.group_id = p_group_id
   and gm.status = 'active'
  where public.is_active_member(p_group_id, auth.uid())
    and (
      lu.user_id = auth.uid()
      or (
        exists (
          select 1
          from public.location_consents lc
          where lc.sharer_id = lu.user_id
            and lc.scope = 'group'
            and lc.group_id = p_group_id
            and lc.status = 'active'
            and (lc.valid_until is null or lc.valid_until > now())
            and lc.valid_from <= now()
        )
        and not exists (
          select 1
          from public.user_settings us
          where us.user_id = lu.user_id
            and us.share_location_globally_paused = true
        )
      )
    );
$$;

revoke all on function public.list_group_locations(uuid) from public;
grant execute on function public.list_group_locations(uuid) to authenticated;

comment on function public.list_group_locations(uuid) is
  'GF-74b: ubicaciones del grupo visibles solo con location_consents activo para ESE group_id (o propio).';

select
  exists (
    select 1 from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'list_group_locations'
  ) as gf74b_list_group_locations_ok;
