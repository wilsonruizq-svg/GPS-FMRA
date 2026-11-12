-- GPS-FMRA — Asegurar Realtime + grants para chat alerts
-- APPLY si el chat funciona pero NO llegan alertas con la app abierta.
-- Éxito: group_messages_realtime_ok = true

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
  to_regclass('public.group_messages') is not null as group_messages_ok,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'group_messages'
  ) as group_messages_realtime_ok;
