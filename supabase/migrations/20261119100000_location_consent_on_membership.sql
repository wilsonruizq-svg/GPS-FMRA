-- GPS-FMRA — GF-74: consent de ubicación al activar membresía
-- APPLY: pegar en SQL Editor → Run (idempotente).
--
-- Problema: location_updates es 1 fila / user_id, pero can_view_location exige
-- location_consents activo **por grupo**. Si el cliente solo escribe consent
-- del grupo creado (o falla al unirse), los peers del grupo unido no ven el pin.
--
-- Solución:
-- 1) Backfill: crear consent 'active' faltante para membresías activas.
-- 2) Trigger: al pasar membership a active, insertar consent si no existe
--    (no reactiva filas 'paused'/'revoked' — eso lo hace el cliente al publicar).

-- ---------------------------------------------------------------------------
-- Backfill (solo inserta si no hay fila group-scope para ese sharer+grupo)
-- ---------------------------------------------------------------------------
insert into public.location_consents (sharer_id, scope, group_id, status)
select
  gm.user_id,
  'group'::public.consent_scope,
  gm.group_id,
  'active'::public.consent_status
from public.group_memberships gm
inner join public.family_groups fg
  on fg.id = gm.group_id
 and fg.status = 'active'
where gm.status = 'active'
  and not exists (
    select 1
    from public.location_consents lc
    where lc.sharer_id = gm.user_id
      and lc.group_id = gm.group_id
      and lc.scope = 'group'
  );

-- ---------------------------------------------------------------------------
-- Trigger: membership → consent (insert-if-missing)
-- ---------------------------------------------------------------------------
create or replace function public.ensure_location_consent_for_membership()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if new.status = 'active' and new.group_id is not null and new.user_id is not null then
    insert into public.location_consents (sharer_id, scope, group_id, status)
    select
      new.user_id,
      'group'::public.consent_scope,
      new.group_id,
      'active'::public.consent_status
    where not exists (
      select 1
      from public.location_consents lc
      where lc.sharer_id = new.user_id
        and lc.group_id = new.group_id
        and lc.scope = 'group'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_membership_ensure_location_consent on public.group_memberships;
create trigger trg_membership_ensure_location_consent
  after insert or update of status, group_id, user_id
  on public.group_memberships
  for each row
  execute function public.ensure_location_consent_for_membership();

comment on function public.ensure_location_consent_for_membership() is
  'GF-74: al activar membresía, crea location_consents group-scope si falta (no pisa paused).';

-- Verificación
select
  (select count(*) from public.group_memberships where status = 'active') as active_memberships,
  (select count(*) from public.location_consents where scope = 'group' and status = 'active') as active_group_consents,
  exists (
    select 1 from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'ensure_location_consent_for_membership'
  ) as gf74_consent_trigger_ok;
