-- GPS-FMRA — asegurar perfil y (opcional) org_admin para wruizq@gmail.com
-- Pegar en SQL Editor. Sin contraseñas. Idempotente en inserts de perfil/settings.
-- Requisito: el usuario ya existe en Authentication → Users (auto-confirmado).

-- 1) Diagnóstico
select
  u.id,
  u.email,
  u.email_confirmed_at,
  p.id as profile_id,
  p.display_name,
  s.user_id as settings_user_id
from auth.users u
left join public.profiles p on p.id = u.id
left join public.user_settings s on s.user_id = u.id
where lower(u.email) = lower('wruizq@gmail.com');

-- 2) Perfil + settings si faltan
insert into public.profiles (id, display_name)
select u.id,
       coalesce(u.raw_user_meta_data->>'display_name', split_part(u.email, '@', 1))
from auth.users u
where lower(u.email) = lower('wruizq@gmail.com')
on conflict (id) do nothing;

insert into public.user_settings (user_id)
select u.id
from auth.users u
where lower(u.email) = lower('wruizq@gmail.com')
on conflict (user_id) do nothing;

-- 3a) Si YA hay membresías activas: promover a org_admin (admin general)
update public.group_memberships gm
set role = 'org_admin',
    status = 'active',
    updated_at = now()
from auth.users u
where gm.user_id = u.id
  and lower(u.email) = lower('wruizq@gmail.com')
  and gm.status = 'active';

-- 3b) Si NO hay grupo todavía: crear uno y asignar org_admin
-- (Descomenta el bloque completo si 3a no actualizó ninguna fila.)
/*
do $$
declare
  v_uid uuid;
  v_gid uuid;
begin
  select id into v_uid
  from auth.users
  where lower(email) = lower('wruizq@gmail.com');

  if v_uid is null then
    raise exception 'Crea primero el usuario en Authentication → Users.';
  end if;

  insert into public.profiles (id, display_name)
  values (v_uid, 'Wilson')
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  insert into public.family_groups (name, created_by, status)
  values ('Familia Wilson', v_uid, 'active')
  returning id into v_gid;

  update public.group_memberships
  set role = 'org_admin',
      status = 'active',
      updated_at = now()
  where group_id = v_gid
    and user_id = v_uid;
end $$;
*/

-- 4) Verificación
select fg.name, gm.role, gm.status, gm.joined_at
from public.group_memberships gm
join public.family_groups fg on fg.id = gm.group_id
join auth.users u on u.id = gm.user_id
where lower(u.email) = lower('wruizq@gmail.com');
