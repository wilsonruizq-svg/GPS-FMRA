-- GPS-FMRA — Mensajes 1:1 (DM) entre integrantes
-- APPLY: pegar en SQL Editor → Run (ver docs/DM_ES.md).
-- Éxito: direct_messages_ok = true AND direct_messages_realtime_ok = true

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  body text not null
    check (char_length(trim(body)) > 0 and char_length(body) <= 2000),
  created_at timestamptz not null default now(),
  constraint direct_messages_distinct_users check (sender_id <> recipient_id)
);

create index if not exists direct_messages_pair_created_idx
  on public.direct_messages (
    least(sender_id, recipient_id),
    greatest(sender_id, recipient_id),
    created_at desc
  );

create index if not exists direct_messages_recipient_created_idx
  on public.direct_messages (recipient_id, created_at desc);

comment on table public.direct_messages is
  'Chat 1:1. Solo sender y recipient leen/escriben (RLS).';

alter table public.direct_messages enable row level security;
alter table public.direct_messages force row level security;

drop policy if exists direct_messages_select_participants on public.direct_messages;
create policy direct_messages_select_participants
  on public.direct_messages for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists direct_messages_insert_own on public.direct_messages;
create policy direct_messages_insert_own
  on public.direct_messages for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_id <> recipient_id
  );

grant select, insert on table public.direct_messages to authenticated;

alter table public.direct_messages replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.direct_messages;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.direct_messages') is not null as direct_messages_ok,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_messages'
  ) as direct_messages_realtime_ok;
