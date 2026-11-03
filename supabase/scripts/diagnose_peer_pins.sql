-- Diagnóstico: ¿por qué solo se ve 1 pin? (Wilson / SQL Editor)
-- No modifica datos. Ejecutar como postgres en el Dashboard.

-- 1) Resumen por grupo
select
  g.id as group_id,
  g.name,
  (select count(*) from public.group_memberships gm
    where gm.group_id = g.id and gm.status = 'active') as members,
  (select count(*) from public.location_consents lc
    where lc.group_id = g.id and lc.scope = 'group' and lc.status = 'active') as active_consents,
  (select count(*) from public.location_updates lu
    join public.group_memberships gm on gm.user_id = lu.user_id
     and gm.group_id = g.id and gm.status = 'active') as location_rows
from public.family_groups g
where g.status = 'active'
order by g.created_at desc
limit 10;

-- 2) Detalle: miembros + consentimiento + última fix
select
  g.name as grupo,
  p.display_name,
  u.email,
  gm.role,
  gm.status as membership,
  lc.status as consent,
  lc.updated_at as consent_updated,
  us.share_location_globally_paused as global_pause,
  lu.lat,
  lu.lon,
  lu.recorded_at as last_fix
from public.family_groups g
join public.group_memberships gm on gm.group_id = g.id and gm.status = 'active'
join auth.users u on u.id = gm.user_id
left join public.profiles p on p.id = gm.user_id
left join public.location_consents lc
  on lc.sharer_id = gm.user_id
 and lc.group_id = g.id
 and lc.scope = 'group'
left join public.user_settings us on us.user_id = gm.user_id
left join public.location_updates lu on lu.user_id = gm.user_id
where g.status = 'active'
order by g.created_at desc, gm.joined_at;

-- 3) ¿Existe la RPC del fix?
select proname, prosecdef as security_definer
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'can_view_location',
    'list_group_locations',
    'is_active_member'
  )
order by proname;
