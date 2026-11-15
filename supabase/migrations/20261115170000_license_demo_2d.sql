-- GPS-FMRA GF-72 — Licencia demo 2 días por cuenta Supabase
-- APPLY: SQL Editor → pegar completo → Run.
-- Éxito: license_demo_2d_ok = true
--
-- Reglas:
-- 1) Email confirmado (auth.users.email_confirmed_at).
-- 2) Demo 2 días desde primer acceso (alta de entitlement).
-- 3) Tras demo: valid_until >= now() o admin (wilsonruizq@gmail.com).
-- Cliente solo lee / llama RPC; no escribe valid_until.

-- ---------------------------------------------------------------------------
-- 1) Tabla license_entitlements
-- ---------------------------------------------------------------------------
create table if not exists public.license_entitlements (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  demo_started_at timestamptz not null default now(),
  valid_until timestamptz,
  status text not null default 'demo'
    check (status in ('demo', 'active', 'expired')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.license_entitlements is
  'Licencia por cuenta: demo 2d, luego valid_until o is_admin. GF-72.';

comment on column public.license_entitlements.demo_started_at is
  'Primer acceso / alta de entitlement; demo = +2 días.';

comment on column public.license_entitlements.valid_until is
  'Fin de licencia pagada/activa. Solo service role / SQL admin escribe.';

comment on column public.license_entitlements.is_admin is
  'true = acceso permanente (dueño). Wilson: wilsonruizq@gmail.com.';

create index if not exists license_entitlements_status_idx
  on public.license_entitlements (status);

create index if not exists license_entitlements_valid_until_idx
  on public.license_entitlements (valid_until)
  where valid_until is not null;

drop trigger if exists license_entitlements_set_updated_at
  on public.license_entitlements;
create trigger license_entitlements_set_updated_at
  before update on public.license_entitlements
  for each row
  execute function public.set_updated_at();

alter table public.license_entitlements enable row level security;
alter table public.license_entitlements force row level security;

-- Cliente: solo SELECT propia fila. Sin INSERT/UPDATE/DELETE (RPC / service role).
drop policy if exists license_entitlements_select_own
  on public.license_entitlements;
create policy license_entitlements_select_own
  on public.license_entitlements for select to authenticated
  using (user_id = auth.uid());

grant select on table public.license_entitlements to authenticated;
grant select, insert, update, delete on table public.license_entitlements
  to service_role;
grant all on table public.license_entitlements to postgres;

-- ---------------------------------------------------------------------------
-- 2) Admin permanente Wilson
-- ---------------------------------------------------------------------------
-- Marca is_admin si el perfil ya existe; idempotente.
-- Si aún no hay profiles, el RPC lo crea en el primer login de Wilson.
insert into public.license_entitlements (
  user_id, demo_started_at, status, is_admin, valid_until
)
select
  p.id,
  now(),
  'active',
  true,
  null
from auth.users u
join public.profiles p on p.id = u.id
where lower(trim(u.email)) = 'wilsonruizq@gmail.com'
on conflict (user_id) do update
  set is_admin = true,
      status = 'active',
      updated_at = now();

-- ---------------------------------------------------------------------------
-- 3) RPC: ensure + evaluar acceso (security definer)
-- ---------------------------------------------------------------------------
create or replace function public.ensure_my_license_access()
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_confirmed_at timestamptz;
  v_row public.license_entitlements%rowtype;
  v_demo_end timestamptz;
  v_allowed boolean := false;
  v_reason text := 'expired';
  v_admin_email constant text := 'wilsonruizq@gmail.com';
begin
  if v_uid is null then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'no_session',
      'status', null,
      'demo_started_at', null,
      'demo_ends_at', null,
      'valid_until', null,
      'is_admin', false
    );
  end if;

  select
    lower(trim(u.email)),
    u.email_confirmed_at
  into v_email, v_confirmed_at
  from auth.users u
  where u.id = v_uid;

  -- Admin Wilson: siempre OK (aunque falte confirmación).
  if v_email = v_admin_email then
    insert into public.license_entitlements (
      user_id, demo_started_at, status, is_admin
    ) values (
      v_uid, now(), 'active', true
    )
    on conflict (user_id) do update
      set is_admin = true,
          status = 'active',
          updated_at = now()
    returning * into v_row;

    return jsonb_build_object(
      'allowed', true,
      'reason', 'admin',
      'status', v_row.status,
      'demo_started_at', v_row.demo_started_at,
      'demo_ends_at', v_row.demo_started_at + interval '2 days',
      'valid_until', v_row.valid_until,
      'is_admin', true
    );
  end if;

  -- Email validado obligatorio.
  if v_confirmed_at is null then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'email_unconfirmed',
      'status', null,
      'demo_started_at', null,
      'demo_ends_at', null,
      'valid_until', null,
      'is_admin', false
    );
  end if;

  -- Alta entitlement en primer acceso (demo 2 días).
  insert into public.license_entitlements (
    user_id, demo_started_at, status, is_admin
  ) values (
    v_uid, now(), 'demo', false
  )
  on conflict (user_id) do nothing;

  select * into v_row
  from public.license_entitlements
  where user_id = v_uid;

  if v_row.is_admin then
    v_allowed := true;
    v_reason := 'admin';
  elsif v_row.valid_until is not null and v_row.valid_until >= now() then
    v_allowed := true;
    v_reason := 'valid_until';
    if v_row.status is distinct from 'active' then
      update public.license_entitlements
      set status = 'active', updated_at = now()
      where user_id = v_uid
      returning * into v_row;
    end if;
  else
    v_demo_end := v_row.demo_started_at + interval '2 days';
    if now() < v_demo_end then
      v_allowed := true;
      v_reason := 'demo';
      if v_row.status is distinct from 'demo' then
        update public.license_entitlements
        set status = 'demo', updated_at = now()
        where user_id = v_uid
        returning * into v_row;
      end if;
    else
      v_allowed := false;
      v_reason := 'expired';
      if v_row.status is distinct from 'expired' then
        update public.license_entitlements
        set status = 'expired', updated_at = now()
        where user_id = v_uid
        returning * into v_row;
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'allowed', v_allowed,
    'reason', v_reason,
    'status', v_row.status,
    'demo_started_at', v_row.demo_started_at,
    'demo_ends_at', v_row.demo_started_at + interval '2 days',
    'valid_until', v_row.valid_until,
    'is_admin', v_row.is_admin
  );
end;
$$;

comment on function public.ensure_my_license_access() is
  'GF-72: crea entitlement demo si falta y evalúa acceso (email, demo 2d, valid_until, admin).';

revoke all on function public.ensure_my_license_access() from public;
grant execute on function public.ensure_my_license_access() to authenticated;
grant execute on function public.ensure_my_license_access() to service_role;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 4) Verificación
-- ---------------------------------------------------------------------------
select
  (
    exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = 'license_entitlements'
    )
    and exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'ensure_my_license_access'
    )
  ) as license_demo_2d_ok;
