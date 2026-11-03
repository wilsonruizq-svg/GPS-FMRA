-- GPS-FMRA — Acuses SOS (Aceptar por compañero)
-- =====================================================================
-- APPLY (Wilson) — SQL Editor → New query → pegar TODO → Run:
--   supabase/migrations/20261102273000_sos_acks.sql
-- Éxito esperado: Success + al final sos_acks_ok = true.
--
-- Comportamiento:
--   • Cada compañero registra un ack con RPC ack_sos.
--   • El emisor ve quién falta (list_sos_ack_progress).
--   • Cuando TODOS los miembros activos (excepto el emisor) aceptan,
--     el SOS pasa a status = resolved y el banner del emisor se limpia.
-- Idempotente. No incluye secretos.

-- ---------------------------------------------------------------------------
-- 1) Tabla sos_acks
-- ---------------------------------------------------------------------------
create table if not exists public.sos_acks (
  id uuid primary key default gen_random_uuid(),
  sos_id uuid not null references public.sos_events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  acked_at timestamptz not null default now(),
  unique (sos_id, user_id)
);

create index if not exists sos_acks_sos_idx on public.sos_acks (sos_id);
create index if not exists sos_acks_user_idx on public.sos_acks (user_id);

comment on table public.sos_acks is
  'Acuse Aceptar de un integrante ante un SOS. El emisor espera a todos.';

alter table public.sos_acks enable row level security;
alter table public.sos_acks force row level security;

drop policy if exists sos_acks_select_members on public.sos_acks;
create policy sos_acks_select_members
  on public.sos_acks for select to authenticated
  using (
    exists (
      select 1
      from public.sos_events s
      where s.id = sos_id
        and public.is_active_member(s.group_id)
    )
  );

drop policy if exists sos_acks_insert_own on public.sos_acks;
create policy sos_acks_insert_own
  on public.sos_acks for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.sos_events s
      where s.id = sos_id
        and s.status = 'active'
        and public.is_active_member(s.group_id)
    )
  );

grant select, insert on table public.sos_acks to authenticated;
grant select, insert, update, delete on table public.sos_acks to service_role;
grant all on table public.sos_acks to postgres;

alter table public.sos_acks replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.sos_acks;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Resolver SOS si todos los compañeros (≠ emisor) ya aceptaron
-- ---------------------------------------------------------------------------
create or replace function public.try_resolve_sos_if_all_acked(p_sos_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_group uuid;
  v_sender uuid;
  v_status text;
  v_expected int;
  v_acked int;
begin
  select group_id, user_id, status
    into v_group, v_sender, v_status
  from public.sos_events
  where id = p_sos_id;

  if v_group is null then
    return false;
  end if;
  if v_status is distinct from 'active' then
    return true;
  end if;

  select count(*)::int into v_expected
  from public.group_memberships gm
  where gm.group_id = v_group
    and gm.status = 'active'
    and gm.user_id is distinct from v_sender;

  select count(*)::int into v_acked
  from public.sos_acks a
  join public.group_memberships gm
    on gm.user_id = a.user_id
   and gm.group_id = v_group
   and gm.status = 'active'
  where a.sos_id = p_sos_id
    and a.user_id is distinct from v_sender;

  if v_acked >= v_expected then
    update public.sos_events
       set status = 'resolved',
           resolved_at = now(),
           resolved_by = coalesce(auth.uid(), v_sender)
     where id = p_sos_id
       and status = 'active';
    return true;
  end if;
  return false;
end;
$$;

revoke all on function public.try_resolve_sos_if_all_acked(uuid) from public;
revoke all on function public.try_resolve_sos_if_all_acked(uuid) from anon;
grant execute on function public.try_resolve_sos_if_all_acked(uuid) to authenticated;
grant execute on function public.try_resolve_sos_if_all_acked(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3) RPC ack_sos — compañero pulsa Aceptar
-- ---------------------------------------------------------------------------
create or replace function public.ack_sos(p_sos_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_group uuid;
  v_sender uuid;
  v_status text;
  v_resolved boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select group_id, user_id, status
    into v_group, v_sender, v_status
  from public.sos_events
  where id = p_sos_id;

  if v_group is null then
    raise exception 'sos not found';
  end if;
  if not public.is_active_member(v_group, v_uid) then
    raise exception 'not a group member';
  end if;
  if v_status is distinct from 'active' then
    return jsonb_build_object(
      'ok', true,
      'already_resolved', true,
      'all_acked', true
    );
  end if;

  -- El emisor no registra ack de receptor; puede cancelar con cancel propio.
  if v_uid = v_sender then
    return jsonb_build_object(
      'ok', true,
      'is_sender', true,
      'all_acked', public.try_resolve_sos_if_all_acked(p_sos_id)
    );
  end if;

  insert into public.sos_acks (sos_id, user_id)
  values (p_sos_id, v_uid)
  on conflict (sos_id, user_id) do nothing;

  v_resolved := public.try_resolve_sos_if_all_acked(p_sos_id);

  return jsonb_build_object(
    'ok', true,
    'is_sender', false,
    'all_acked', v_resolved
  );
end;
$$;

revoke all on function public.ack_sos(uuid) from public;
revoke all on function public.ack_sos(uuid) from anon;
grant execute on function public.ack_sos(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) RPC list_sos_ack_progress — emisor ve pendientes
-- ---------------------------------------------------------------------------
create or replace function public.list_sos_ack_progress(p_sos_id uuid)
returns table (
  user_id uuid,
  display_name text,
  is_sender boolean,
  acked boolean,
  acked_at timestamptz
)
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_group uuid;
  v_sender uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select s.group_id, s.user_id into v_group, v_sender
  from public.sos_events s
  where s.id = p_sos_id;

  if v_group is null then
    raise exception 'sos not found';
  end if;
  if not public.is_active_member(v_group, v_uid) then
    raise exception 'not a group member';
  end if;

  return query
  select
    gm.user_id,
    coalesce(nullif(trim(p.display_name), ''), 'Integrante') as display_name,
    (gm.user_id = v_sender) as is_sender,
    (a.id is not null) as acked,
    a.acked_at
  from public.group_memberships gm
  left join public.profiles p on p.id = gm.user_id
  left join public.sos_acks a
    on a.user_id = gm.user_id
   and a.sos_id = p_sos_id
  where gm.group_id = v_group
    and gm.status = 'active'
  order by (gm.user_id = v_sender) desc, p.display_name nulls last;
end;
$$;

revoke all on function public.list_sos_ack_progress(uuid) from public;
revoke all on function public.list_sos_ack_progress(uuid) from anon;
grant execute on function public.list_sos_ack_progress(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Schema cache + verificación
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

select
  to_regclass('public.sos_acks') is not null as sos_acks_ok,
  has_function_privilege('authenticated', 'public.ack_sos(uuid)', 'execute')
    as ack_sos_ok,
  has_function_privilege(
    'authenticated',
    'public.list_sos_ack_progress(uuid)',
    'execute'
  ) as progress_ok;
