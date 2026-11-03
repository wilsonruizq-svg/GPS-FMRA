-- GPS-FMRA — Fix: pins de pares (2 miembros, 1 grupo, consentimiento activo)
-- APPLY: pegar en SQL Editor → Run (ver supabase/APPLY_ES.md paso 3.6).
-- Idempotente. No incluye secretos.
--
-- Problema: con FORCE RLS, helpers security definer sin row_security=off pueden
-- fallar al evaluar membresía/consentimiento AJENO. can_view_location corta en
-- `sharer = viewer` → solo ves tu propio pin. Este script endurece los helpers
-- y añade RPC list_group_locations para lectura fiable de pines del grupo.

-- ---------------------------------------------------------------------------
-- Helpers: bypass RLS interno (siguen validando auth.uid / can_view_location)
-- ---------------------------------------------------------------------------
create or replace function public.is_active_member(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
      and gm.status = 'active'
  );
$$;

create or replace function public.is_group_admin(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
      and gm.status = 'active'
      and gm.role in ('group_admin', 'org_admin')
  );
$$;

create or replace function public.can_view_location(p_sharer_id uuid, p_viewer_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    (
      p_sharer_id is not null
      and p_viewer_id is not null
      and (
        p_sharer_id = p_viewer_id
        or exists (
          select 1
          from public.location_consents lc
          where lc.sharer_id = p_sharer_id
            and lc.status = 'active'
            and (lc.valid_until is null or lc.valid_until > now())
            and lc.valid_from <= now()
            and (
              (
                lc.scope = 'user'
                and lc.viewer_id = p_viewer_id
                and (
                  lc.group_id is null
                  or public.is_active_member(lc.group_id, p_viewer_id)
                )
              )
              or (
                lc.scope = 'group'
                and lc.group_id is not null
                and public.is_active_member(lc.group_id, p_viewer_id)
                and public.is_active_member(lc.group_id, p_sharer_id)
              )
            )
        )
      )
    )
    and not exists (
      select 1
      from public.user_settings us
      where us.user_id = p_sharer_id
        and us.share_location_globally_paused = true
        and p_sharer_id <> p_viewer_id
    );
$$;

revoke all on function public.is_active_member(uuid, uuid) from public;
revoke all on function public.is_group_admin(uuid, uuid) from public;
revoke all on function public.can_view_location(uuid, uuid) from public;
grant execute on function public.is_active_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;
grant execute on function public.can_view_location(uuid, uuid) to authenticated;

-- Reafirmar política SELECT (misma regla; idempotente)
drop policy if exists location_updates_select_consented on public.location_updates;
create policy location_updates_select_consented
  on public.location_updates for select to authenticated
  using (public.can_view_location(user_id));

-- ---------------------------------------------------------------------------
-- RPC: ubicaciones visibles de un grupo (evita filtros PostgREST frágiles)
-- ---------------------------------------------------------------------------
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
    and public.can_view_location(lu.user_id, auth.uid());
$$;

revoke all on function public.list_group_locations(uuid) from public;
grant execute on function public.list_group_locations(uuid) to authenticated;

comment on function public.list_group_locations(uuid) is
  'Últimas ubicaciones de miembros del grupo visibles vía can_view_location. Requiere membresía activa del caller.';

-- Realtime: asegurar publicación (por si APPLY 230000 no se corrió)
alter table public.location_updates replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.location_updates;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;
