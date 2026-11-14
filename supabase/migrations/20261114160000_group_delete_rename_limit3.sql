-- GPS-FMRA — GF-32: eliminar grupo, renombrar, máx. 3 grupos creados
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → pegar TODO → Run.
-- Éxito: group_admin_ops_ok = true
-- Idempotente. No incluye secretos.
--
-- • delete_family_group: solo group_admin/org_admin; DELETE (cascade hijos).
-- • rename_family_group: solo admin; nombre 1–80 chars.
-- • Trigger: máx. 3 family_groups activos con created_by = usuario.

-- ---------------------------------------------------------------------------
-- Límite 3 grupos creados (status active)
-- ---------------------------------------------------------------------------
create or replace function public.count_created_active_groups(
  p_user_id uuid default auth.uid()
)
returns integer
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select count(*)::integer
  from public.family_groups fg
  where fg.created_by = p_user_id
    and fg.status = 'active';
$$;

revoke all on function public.count_created_active_groups(uuid) from public;
revoke all on function public.count_created_active_groups(uuid) from anon;
grant execute on function public.count_created_active_groups(uuid) to authenticated;

create or replace function public.enforce_max_created_groups()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_count integer;
begin
  if new.status is distinct from 'active' then
    return new;
  end if;
  select count(*)::integer into v_count
  from public.family_groups fg
  where fg.created_by = new.created_by
    and fg.status = 'active';
  -- BEFORE INSERT: v_count es los existentes; el nuevo aún no está.
  if v_count >= 3 then
    raise exception 'MAX_CREATED_GROUPS: Ya creaste 3 grupos. Elimina uno para crear otro.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_max_created_groups on public.family_groups;
create trigger trg_enforce_max_created_groups
  before insert on public.family_groups
  for each row
  execute function public.enforce_max_created_groups();

-- ---------------------------------------------------------------------------
-- Renombrar (admin)
-- ---------------------------------------------------------------------------
create or replace function public.rename_family_group(
  p_group_id uuid,
  p_name text
)
returns public.family_groups
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_row public.family_groups;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null then
    raise exception 'group required';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 80 then
    raise exception 'INVALID_GROUP_NAME: El nombre debe tener entre 1 y 80 caracteres.';
  end if;
  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'not a group admin';
  end if;

  update public.family_groups
     set name = v_name,
         updated_at = now()
   where id = p_group_id
     and status = 'active'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'group not found';
  end if;
  return v_row;
end;
$$;

revoke all on function public.rename_family_group(uuid, text) from public;
revoke all on function public.rename_family_group(uuid, text) from anon;
grant execute on function public.rename_family_group(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Eliminar (admin) — DELETE cascade a membresías, invites, mensajes, etc.
-- ---------------------------------------------------------------------------
create or replace function public.delete_family_group(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_group_id is null then
    raise exception 'group required';
  end if;
  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'not a group admin';
  end if;

  select name into v_name
  from public.family_groups
  where id = p_group_id;

  if v_name is null then
    raise exception 'group not found';
  end if;

  delete from public.family_groups where id = p_group_id;

  return jsonb_build_object(
    'ok', true,
    'group_id', p_group_id,
    'name', v_name
  );
end;
$$;

revoke all on function public.delete_family_group(uuid) from public;
revoke all on function public.delete_family_group(uuid) from anon;
grant execute on function public.delete_family_group(uuid) to authenticated;

-- UPDATE name también vía RLS existente (admin); sin cambio de policy.

notify pgrst, 'reload schema';

select
  has_function_privilege('authenticated', 'public.delete_family_group(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.rename_family_group(uuid, text)', 'execute')
    and has_function_privilege('authenticated', 'public.count_created_active_groups(uuid)', 'execute')
    as group_admin_ops_ok;
