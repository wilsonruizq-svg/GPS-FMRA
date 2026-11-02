-- GPS-FMRA — fix accept_invitation: pgcrypto / digest(bytea, unknown)
-- APPLY: pegar este archivo completo en Supabase SQL Editor → Run.
--
-- Causa: con `set search_path = public` la función `digest` de pgcrypto
-- (schema `extensions` en Supabase) no es visible, y el literal 'sha256'
-- queda como `unknown` → error `function digest(bytea, unknown) does not exist`.
--
-- Hashing alineado con Flutter (`InviteToken.hashToken`):
--   sha256.convert(utf8.encode(plain)).toString()  → hex minúsculas
-- Tras aplicar, los códigos ya emitidos siguen válidos (mismo algoritmo).
-- Si un código falló solo por este bug, reintenta; regenera solo si cambiaste
-- el algoritmo o el token en claro ya no está disponible.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.accept_invitation(p_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text;
  v_hash text;
  v_inv public.invitations%rowtype;
  v_group public.family_groups%rowtype;
  v_membership_id uuid;
  v_existing_role public.membership_role;
  v_existing_status public.membership_status;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED'
      using errcode = 'P0001',
            hint = 'Debes iniciar sesión para aceptar una invitación.';
  end if;

  v_raw := trim(both from coalesce(p_token, ''));
  if v_raw = '' then
    raise exception 'TOKEN_INVALID'
      using errcode = 'P0001',
            hint = 'El código de invitación está vacío.';
  end if;

  -- Stub de deep link: gpsfmra://invite/<token>
  if lower(v_raw) like 'gpsfmra://invite/%' then
    v_raw := substring(v_raw from length('gpsfmra://invite/') + 1);
  end if;
  v_raw := trim(both from v_raw);

  if length(v_raw) < 8 then
    raise exception 'TOKEN_INVALID'
      using errcode = 'P0001',
            hint = 'El código de invitación no es válido.';
  end if;

  -- Mismo algoritmo que Flutter: SHA-256 hex de UTF-8
  v_hash := encode(
    digest(convert_to(v_raw, 'UTF8'), 'sha256'::text),
    'hex'
  );

  select *
    into v_inv
  from public.invitations
  where token_hash = v_hash
  for update;

  if not found then
    raise exception 'INVITE_NOT_FOUND'
      using errcode = 'P0001',
            hint = 'No existe una invitación con ese código.';
  end if;

  if v_inv.status = 'revoked' then
    raise exception 'INVITE_REVOKED'
      using errcode = 'P0001',
            hint = 'Esta invitación fue revocada.';
  end if;

  if v_inv.expires_at <= now() then
    update public.invitations
       set status = 'expired'
     where id = v_inv.id
       and status = 'pending';
    raise exception 'INVITE_EXPIRED'
      using errcode = 'P0001',
            hint = 'Esta invitación ya venció.';
  end if;

  if v_inv.status <> 'pending' or v_inv.uses_count >= v_inv.max_uses then
    raise exception 'INVITE_USED'
      using errcode = 'P0001',
            hint = 'Esta invitación ya fue usada.';
  end if;

  -- Perfil por si el trigger de auth aún no corrió
  insert into public.profiles (id)
  values (v_uid)
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  select gm.role, gm.status
    into v_existing_role, v_existing_status
  from public.group_memberships gm
  where gm.group_id = v_inv.group_id
    and gm.user_id = v_uid;

  select *
    into v_group
  from public.family_groups
  where id = v_inv.group_id;

  if v_group.id is null then
    raise exception 'GROUP_MISSING'
      using errcode = 'P0001',
            hint = 'El grupo de la invitación ya no existe.';
  end if;

  -- Ya es miembro activo: no consumir el cupo de un solo uso
  if v_existing_status = 'active' then
    return json_build_object(
      'group_id', v_group.id,
      'group_name', v_group.name,
      'membership_id', null,
      'role', v_existing_role::text,
      'already_member', true
    );
  end if;

  insert into public.group_memberships (group_id, user_id, role, status)
  values (v_inv.group_id, v_uid, 'member', 'active')
  on conflict (group_id, user_id) do update
    set status = 'active',
        role = case
          when public.group_memberships.role in ('group_admin', 'org_admin')
            then public.group_memberships.role
          else 'member'::public.membership_role
        end,
        joined_at = now(),
        updated_at = now()
  returning id into v_membership_id;

  update public.invitations
     set uses_count = uses_count + 1,
         accepted_by = v_uid,
         accepted_at = now(),
         status = case
           when uses_count + 1 >= max_uses then 'accepted'::public.invitation_status
           else status
         end
   where id = v_inv.id;

  return json_build_object(
    'group_id', v_group.id,
    'group_name', v_group.name,
    'membership_id', v_membership_id,
    'role', 'member',
    'already_member', false
  );
end;
$$;

comment on function public.accept_invitation(text) is
  'Acepta invitación por token en claro; SHA-256 hex via pgcrypto. Rol: member.';

revoke all on function public.accept_invitation(text) from public;
revoke all on function public.accept_invitation(text) from anon;
grant execute on function public.accept_invitation(text) to authenticated;
