-- GPS-FMRA — Alertas SOS (v1, sin FCM/chat)
-- APPLY: pegar en SQL Editor → Run (ver supabase/APPLY_ES.md).
-- Idempotente. No incluye secretos.
--
-- Mensaje de éxito esperado (Supabase SQL Editor):
--   Success. No rows returned
-- Tras APPLY: Table Editor debe listar `sos_events`; Replication debe incluirla.

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

comment on table public.sos_events is
  'Alerta de emergencia SOS v1. Visible a miembros activos del grupo; sin chat.';

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

-- Quien creó la alerta o un admin del grupo puede resolver/cancelar.
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
