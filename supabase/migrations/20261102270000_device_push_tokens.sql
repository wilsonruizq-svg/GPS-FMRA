-- GPS-FMRA — Tokens FCM por dispositivo (SOS push)
-- APPLY: pegar en SQL Editor → Run (ver supabase/APPLY_ES.md).
-- Idempotente. No incluye secretos.
--
-- Mensaje de éxito esperado (Supabase SQL Editor):
--   Success. No rows returned

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

comment on table public.device_push_tokens is
  'Tokens FCM por usuario/dispositivo. Usados por Edge Function notify-sos.';

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

-- RPC: tokens de compañeros del grupo (excepto el emisor). Security definer
-- para que notify-sos / cliente autenticado pueda listar sin abrir la tabla.
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

comment on function public.list_group_push_tokens(uuid, uuid) is
  'Tokens FCM de miembros activos del grupo (excluye emisor). Para SOS push.';
