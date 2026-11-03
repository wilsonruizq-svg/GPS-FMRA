-- GPS-FMRA — PIN de salida del grupo (modo quiosco suave)
-- APPLY: pegar este archivo completo en Supabase SQL Editor → Run
--   (o añadirlo al orden en APPLY_ES.md / supabase db push).
--
-- El admin del grupo define un PIN numérico. Los integrantes deben
-- introducirlo para cerrar sesión o salir con el botón Atrás del sistema.
-- Solo se guarda hash bcrypt (pgcrypto crypt/gen_salt); nunca el PIN en claro.

create extension if not exists pgcrypto with schema extensions;

alter table public.family_groups
  add column if not exists exit_pin_hash text,
  add column if not exists exit_pin_updated_at timestamptz;

comment on column public.family_groups.exit_pin_hash is
  'Hash bcrypt del PIN de salida (crypt/gen_salt bf). NULL = sin PIN.';
comment on column public.family_groups.exit_pin_updated_at is
  'Última vez que el admin estableció o cambió el PIN de salida.';

-- ---------------------------------------------------------------------------
-- set_group_exit_pin — solo admin; hashea en servidor
-- ---------------------------------------------------------------------------
create or replace function public.set_group_exit_pin(
  p_group_id uuid,
  p_pin text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pin text;
  v_hash text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes iniciar sesión.';
  end if;

  if p_group_id is null then
    raise exception 'GROUP_REQUIRED'
      using errcode = 'P0001',
            hint = 'Falta el grupo.';
  end if;

  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'ADMIN_REQUIRED'
      using errcode = 'P0001',
            hint = 'Solo un admin del grupo puede configurar el PIN de salida.';
  end if;

  v_pin := trim(both from coalesce(p_pin, ''));
  if v_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN_INVALID'
      using errcode = 'P0001',
            hint = 'El PIN debe tener entre 4 y 8 dígitos.';
  end if;

  v_hash := crypt(v_pin, gen_salt('bf'));

  update public.family_groups
     set exit_pin_hash = v_hash,
         exit_pin_updated_at = now(),
         updated_at = now()
   where id = p_group_id;

  if not found then
    raise exception 'GROUP_MISSING'
      using errcode = 'P0001',
            hint = 'El grupo no existe.';
  end if;

  return json_build_object(
    'group_id', p_group_id,
    'exit_pin_set', true,
    'updated_at', now()
  );
end;
$$;

comment on function public.set_group_exit_pin(uuid, text) is
  'Admin: guarda PIN de salida hasheado (bcrypt). Nunca devuelve el hash.';

revoke all on function public.set_group_exit_pin(uuid, text) from public;
revoke all on function public.set_group_exit_pin(uuid, text) from anon;
grant execute on function public.set_group_exit_pin(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- clear_group_exit_pin — solo admin
-- ---------------------------------------------------------------------------
create or replace function public.clear_group_exit_pin(p_group_id uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes iniciar sesión.';
  end if;

  if p_group_id is null then
    raise exception 'GROUP_REQUIRED'
      using errcode = 'P0001',
            hint = 'Falta el grupo.';
  end if;

  if not public.is_group_admin(p_group_id, v_uid) then
    raise exception 'ADMIN_REQUIRED'
      using errcode = 'P0001',
            hint = 'Solo un admin del grupo puede quitar el PIN de salida.';
  end if;

  update public.family_groups
     set exit_pin_hash = null,
         exit_pin_updated_at = null,
         updated_at = now()
   where id = p_group_id;

  if not found then
    raise exception 'GROUP_MISSING'
      using errcode = 'P0001',
            hint = 'El grupo no existe.';
  end if;

  return json_build_object(
    'group_id', p_group_id,
    'exit_pin_set', false
  );
end;
$$;

comment on function public.clear_group_exit_pin(uuid) is
  'Admin: elimina el PIN de salida del grupo.';

revoke all on function public.clear_group_exit_pin(uuid) from public;
revoke all on function public.clear_group_exit_pin(uuid) from anon;
grant execute on function public.clear_group_exit_pin(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- group_has_exit_pin — miembro activo; no expone el hash
-- ---------------------------------------------------------------------------
create or replace function public.group_has_exit_pin(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_set boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes iniciar sesión.';
  end if;

  if not public.is_active_member(p_group_id, v_uid) then
    raise exception 'MEMBER_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes ser integrante del grupo.';
  end if;

  select (fg.exit_pin_hash is not null)
    into v_set
  from public.family_groups fg
  where fg.id = p_group_id;

  return coalesce(v_set, false);
end;
$$;

comment on function public.group_has_exit_pin(uuid) is
  'True si el grupo tiene PIN de salida configurado (sin devolver el hash).';

revoke all on function public.group_has_exit_pin(uuid) from public;
revoke all on function public.group_has_exit_pin(uuid) from anon;
grant execute on function public.group_has_exit_pin(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- exit_pin_is_required — true si el usuario pertenece a algún grupo con PIN
-- ---------------------------------------------------------------------------
create or replace function public.exit_pin_is_required()
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;

  return exists (
    select 1
    from public.group_memberships gm
    join public.family_groups fg on fg.id = gm.group_id
    where gm.user_id = v_uid
      and gm.status = 'active'
      and fg.status = 'active'
      and fg.exit_pin_hash is not null
  );
end;
$$;

comment on function public.exit_pin_is_required() is
  'True si el usuario activo debe introducir PIN para salir / cerrar sesión.';

revoke all on function public.exit_pin_is_required() from public;
revoke all on function public.exit_pin_is_required() from anon;
grant execute on function public.exit_pin_is_required() to authenticated;

-- ---------------------------------------------------------------------------
-- verify_exit_pin — valida el PIN contra cualquier grupo del usuario
-- ---------------------------------------------------------------------------
create or replace function public.verify_exit_pin(p_pin text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pin text;
  v_row record;
  v_matched boolean := false;
  v_group_id uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes iniciar sesión.';
  end if;

  v_pin := trim(both from coalesce(p_pin, ''));
  if v_pin = '' then
    raise exception 'PIN_INVALID'
      using errcode = 'P0001',
            hint = 'Ingresa el PIN de salida.';
  end if;

  if not exists (
    select 1
    from public.group_memberships gm
    join public.family_groups fg on fg.id = gm.group_id
    where gm.user_id = v_uid
      and gm.status = 'active'
      and fg.status = 'active'
      and fg.exit_pin_hash is not null
  ) then
    return json_build_object(
      'ok', true,
      'required', false
    );
  end if;

  for v_row in
    select fg.id, fg.exit_pin_hash
    from public.group_memberships gm
    join public.family_groups fg on fg.id = gm.group_id
    where gm.user_id = v_uid
      and gm.status = 'active'
      and fg.status = 'active'
      and fg.exit_pin_hash is not null
  loop
    if crypt(v_pin, v_row.exit_pin_hash) = v_row.exit_pin_hash then
      v_matched := true;
      v_group_id := v_row.id;
      exit;
    end if;
  end loop;

  if not v_matched then
    raise exception 'PIN_WRONG'
      using errcode = 'P0001',
            hint = 'PIN incorrecto.';
  end if;

  return json_build_object(
    'ok', true,
    'required', true,
    'group_id', v_group_id
  );
end;
$$;

comment on function public.verify_exit_pin(text) is
  'Compara el PIN con los hashes bcrypt de los grupos del usuario. No expone hashes.';

revoke all on function public.verify_exit_pin(text) from public;
revoke all on function public.verify_exit_pin(text) from anon;
grant execute on function public.verify_exit_pin(text) to authenticated;
