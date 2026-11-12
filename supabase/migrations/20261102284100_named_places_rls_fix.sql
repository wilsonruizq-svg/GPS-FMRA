-- GPS-FMRA — Refuerzo RLS named_places (insert Solo yo / grupo)
-- APPLY si Guardar falla con RLS aunque named_places_ok = true.
-- Éxito: named_places_rls_ok = true

drop policy if exists named_places_select on public.named_places;
create policy named_places_select
  on public.named_places for select to authenticated
  using (
    owner_id = auth.uid()
    or (
      group_id is not null
      and public.is_active_member(group_id, auth.uid())
    )
  );

drop policy if exists named_places_insert_own on public.named_places;
create policy named_places_insert_own
  on public.named_places for insert to authenticated
  with check (
    owner_id = auth.uid()
    and (
      group_id is null
      or public.is_active_member(group_id, auth.uid())
    )
  );

drop policy if exists named_places_delete_own on public.named_places;
create policy named_places_delete_own
  on public.named_places for delete to authenticated
  using (owner_id = auth.uid());

grant select, insert, delete on table public.named_places to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.named_places') is not null as named_places_rls_ok;
