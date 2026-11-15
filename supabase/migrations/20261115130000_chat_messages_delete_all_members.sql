-- GPS-FMRA — Borrar mensajes: cualquier integrante / participante DM
-- APPLY después de (o en lugar de) 20261115120000 si aún no aplicaste DELETE.
-- Éxito: group_messages_delete_members_ok y direct_messages_delete_participant_ok

grant delete on table public.group_messages to authenticated;
grant delete on table public.direct_messages to authenticated;

drop policy if exists group_messages_delete_own_or_admin on public.group_messages;
drop policy if exists group_messages_delete_members on public.group_messages;
drop policy if exists group_messages_delete_admin on public.group_messages;
create policy group_messages_delete_admin
  on public.group_messages for delete to authenticated
  using (
    public.is_active_member(group_id)
    and public.is_group_admin(group_id)
  );

drop policy if exists direct_messages_delete_sender on public.direct_messages;
drop policy if exists direct_messages_delete_participant on public.direct_messages;
create policy direct_messages_delete_participant
  on public.direct_messages for delete to authenticated
  using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
  );

notify pgrst, 'reload schema';

select
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'group_messages'
      and policyname = 'group_messages_delete_admin'
  ) as group_messages_delete_admin_ok,
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'direct_messages'
      and policyname = 'direct_messages_delete_participant'
  ) as direct_messages_delete_participant_ok;