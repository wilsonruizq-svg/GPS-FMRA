-- GPS-FMRA — Dos administradores de grupo (padre/madre)
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: group_dual_admins_ok = true
--
-- Schema: group_memberships ya permite varios group_admin (unique solo
--   group_id+user_id). Este script añade RPC promote/demote con tope 2.
-- Ambos admins: invitar, PIN, historial miembros, rename/delete (is_group_admin).
-- Idempotente. No incluye secretos.

create or replace function public.count_group_admins(p_group_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select count(*)::integer
  from public.group_memberships gm
  where gm.group_id = p_group_id
    and gm.status = 'active'
    and gm.role = 'group_admin';
$$;

revoke all on function public.count_group_admins(uuid) from public;
revoke all on function public.count_group_admins(uuid) from anon;
grant execute on function public.count_group_admins(uuid) to authenticated;

-- Promover miembro → group_admin (máx. 2 group_admin activos).
create or replace function public.promote_group_admin(
  p_group_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_admins integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null or p_user_id is null then
    raise exception 'group and user required';
  end if;
  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'only group admin can promote';
  end if;

  select gm.role::text, gm.status::text
    into v_role, v_status
  from public.group_memberships gm
  where gm.group_id = p_group_id and gm.user_id = p_user_id;

  if v_role is null then
    raise exception 'user is not a member';
  end if;
  if v_status <> 'active' then
    raise exception 'user is not an active member';
  end if;
  if v_role in ('group_admin', 'org_admin') then
    return jsonb_build_object(
      'ok', true,
      'role', v_role,
      'already', true
    );
  end if;

  v_admins := public.count_group_admins(p_group_id);
  if v_admins >= 2 then
    raise exception 'max 2 group admins';
  end if;

  update public.group_memberships
  set role = 'group_admin',
      updated_at = now()
  where group_id = p_group_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'role', 'group_admin',
    'already', false
  );
end;
$$;

revoke all on function public.promote_group_admin(uuid, uuid) from public;
revoke all on function public.promote_group_admin(uuid, uuid) from anon;
grant execute on function public.promote_group_admin(uuid, uuid) to authenticated;

-- Quitar group_admin → member (no dejar el grupo sin admins).
create or replace function public.demote_group_admin(
  p_group_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_admins integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null or p_user_id is null then
    raise exception 'group and user required';
  end if;
  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'only group admin can demote';
  end if;

  select gm.role::text into v_role
  from public.group_memberships gm
  where gm.group_id = p_group_id
    and gm.user_id = p_user_id
    and gm.status = 'active';

  if v_role is null then
    raise exception 'user is not an active member';
  end if;
  if v_role = 'org_admin' then
    raise exception 'cannot demote org admin here';
  end if;
  if v_role <> 'group_admin' then
    return jsonb_build_object(
      'ok', true,
      'role', 'member',
      'already', true
    );
  end if;

  v_admins := public.count_group_admins(p_group_id);
  if v_admins <= 1 then
    raise exception 'cannot remove the last group admin';
  end if;

  update public.group_memberships
  set role = 'member',
      updated_at = now()
  where group_id = p_group_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'role', 'member',
    'already', false
  );
end;
$$;

revoke all on function public.demote_group_admin(uuid, uuid) from public;
revoke all on function public.demote_group_admin(uuid, uuid) from anon;
grant execute on function public.demote_group_admin(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

select
  has_function_privilege(
    'authenticated',
    'public.promote_group_admin(uuid, uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.demote_group_admin(uuid, uuid)',
    'execute'
  ) as group_dual_admins_ok;
