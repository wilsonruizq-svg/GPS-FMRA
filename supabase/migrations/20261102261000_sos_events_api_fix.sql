-- GPS-FMRA — SOS: hacer visible la tabla al API (fix 404 PostgREST)
-- =====================================================================
-- Síntoma en app / REST: 404 sobre sos_events aunque “creíste” aplicar
-- 20261102260000_sos_events.sql. El API no ve la tabla (falta GRANT o
-- schema cache), o la tabla no llegó a crearse.
--
-- APPLY (Wilson) — SQL Editor → New query → pegar TODO → Run:
--   supabase/migrations/20261102261000_sos_events_api_fix.sql
-- Éxito esperado: Success + al final verás filas de verificación
--   (sos_events_ok / device_push_tokens_ok = true).
--
-- Idempotente. No toca Storage. No incluye secretos.

-- ---------------------------------------------------------------------------
-- 1) Tabla sos_events
-- ---------------------------------------------------------------------------
create table if not exists public.sos_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  lat double precision,
  lon double precision,
  note text,
  status text not null default 'active'
    check (status in ('active', 'resolved', 'cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null
);

create index if not exists sos_events_group_active_idx
  on public.sos_events (group_id, created_at desc)
  where status = 'active';

create index if not exists sos_events_user_idx
  on public.sos_events (user_id, created_at desc);

alter table public.sos_events enable row level security;
alter table public.sos_events force row level security;

drop policy if exists sos_events_select_members on public.sos_events;
create policy sos_events_select_members
  on public.sos_events for select to authenticated
  using (public.is_active_member(group_id));

drop policy if exists sos_events_insert_own on public.sos_events;
create policy sos_events_insert_own
  on public.sos_events for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_member(group_id)
  );

drop policy if exists sos_events_update_own_or_admin on public.sos_events;
create policy sos_events_update_own_or_admin
  on public.sos_events for update to authenticated
  using (
    user_id = auth.uid()
    or public.is_group_admin(group_id)
  )
  with check (
    user_id = auth.uid()
    or public.is_group_admin(group_id)
  );

-- Grants explícitos (sin esto el REST a veces responde 404).
grant select, insert, update, delete on table public.sos_events to authenticated;
grant select, insert, update, delete on table public.sos_events to service_role;
grant all on table public.sos_events to postgres;

alter table public.sos_events replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.sos_events;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) device_push_tokens (si faltó el APPLY anterior — FCM opcional)
-- ---------------------------------------------------------------------------
create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android'
    check (platform in ('android', 'ios', 'web', 'unknown')),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;
alter table public.device_push_tokens force row level security;

drop policy if exists device_push_tokens_select_own on public.device_push_tokens;
create policy device_push_tokens_select_own
  on public.device_push_tokens for select to authenticated
  using (user_id = auth.uid());

drop policy if exists device_push_tokens_insert_own on public.device_push_tokens;
create policy device_push_tokens_insert_own
  on public.device_push_tokens for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists device_push_tokens_update_own on public.device_push_tokens;
create policy device_push_tokens_update_own
  on public.device_push_tokens for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists device_push_tokens_delete_own on public.device_push_tokens;
create policy device_push_tokens_delete_own
  on public.device_push_tokens for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on table public.device_push_tokens to authenticated;
grant select, insert, update, delete on table public.device_push_tokens to service_role;
grant all on table public.device_push_tokens to postgres;

create or replace function public.list_group_push_tokens(
  p_group_id uuid,
  p_exclude_user uuid default auth.uid()
)
returns table (
  user_id uuid,
  token text,
  platform text
)
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_active_member(p_group_id, auth.uid()) then
    raise exception 'not a group member';
  end if;

  return query
  select d.user_id, d.token, d.platform
  from public.device_push_tokens d
  join public.group_memberships gm
    on gm.user_id = d.user_id
   and gm.group_id = p_group_id
   and gm.status = 'active'
  where d.user_id is distinct from p_exclude_user;
end;
$$;

revoke all on function public.list_group_push_tokens(uuid, uuid) from public;
revoke all on function public.list_group_push_tokens(uuid, uuid) from anon;
grant execute on function public.list_group_push_tokens(uuid, uuid) to authenticated;
grant execute on function public.list_group_push_tokens(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3) RPC raise_sos (insert fiable vía security definer)
-- ---------------------------------------------------------------------------
create or replace function public.raise_sos(
  p_group_id uuid,
  p_lat double precision default null,
  p_lon double precision default null,
  p_note text default null
)
returns public.sos_events
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.sos_events;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not a group member';
  end if;

  insert into public.sos_events (group_id, user_id, lat, lon, note, status)
  values (p_group_id, v_uid, p_lat, p_lon, p_note, 'active')
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.raise_sos(uuid, double precision, double precision, text) from public;
revoke all on function public.raise_sos(uuid, double precision, double precision, text) from anon;
grant execute on function public.raise_sos(uuid, double precision, double precision, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Recargar schema cache de PostgREST (quita el 404)
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 5) Verificación (debe devolver true / true)
-- ---------------------------------------------------------------------------
select
  to_regclass('public.sos_events') is not null as sos_events_ok,
  to_regclass('public.device_push_tokens') is not null as device_push_tokens_ok,
  has_table_privilege('authenticated', 'public.sos_events', 'INSERT') as sos_insert_granted;
