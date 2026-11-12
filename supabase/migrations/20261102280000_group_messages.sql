-- GPS-FMRA — Mensajes de texto del grupo (chat MVP v1)
-- APPLY: pegar en SQL Editor → Run (ver docs/CHAT_ES.md y supabase/APPLY_ES.md).
-- Idempotente. No incluye secretos.
--
-- Éxito esperado al final: group_messages_ok = true

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null
    check (char_length(trim(body)) > 0 and char_length(body) <= 2000),
  created_at timestamptz not null default now()
);

create index if not exists group_messages_group_created_idx
  on public.group_messages (group_id, created_at desc);

comment on table public.group_messages is
  'Chat de texto del grupo familiar (MVP). Solo miembros activos leen/escriben.';

alter table public.group_messages enable row level security;
alter table public.group_messages force row level security;

drop policy if exists group_messages_select_members on public.group_messages;
create policy group_messages_select_members
  on public.group_messages for select to authenticated
  using (public.is_active_member(group_id));

drop policy if exists group_messages_insert_own on public.group_messages;
create policy group_messages_insert_own
  on public.group_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_active_member(group_id)
  );

-- Sin UPDATE/DELETE en v1 (historial append-only).

grant select, insert on table public.group_messages to authenticated;

alter table public.group_messages replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.group_messages;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.group_messages') is not null as group_messages_ok;
