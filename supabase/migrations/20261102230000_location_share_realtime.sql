-- GPS-FMRA — Fase 1 ubicación compartida (Realtime)
-- APPLY: pegar en SQL Editor → Run (ver supabase/APPLY_ES.md).
-- Idempotente. No incluye secretos.
--
-- Asegura que location_updates esté en la publicación Realtime y que los
-- DELETE/UPDATE envíen la fila completa (REPLICA IDENTITY FULL) para que
-- RLS + clientes puedan filtrar por user_id. La lectura sigue pasando por
-- can_view_location() — sin consentimiento activo nadie ve coords ajenas.

alter table public.location_updates replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.location_updates;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

comment on table public.location_updates is
  'Última ubicación conocida (no historial). SELECT vía can_view_location; Realtime con RLS.';
