# Historial de ubicaciones (consent-first)

## SQL (Wilson)

Archivo:

`supabase/migrations/20261102272000_location_history.sql`

1. SQL Editor → New query → pegar **todo** → **Run**.
2. Éxito: ver `location_history_ok = true`.
3. La app sigue publicando la ubicación **en vivo** (`location_updates`) y,
   con este SQL, también guarda puntos en historial.

## App

- Ajustes → **Historial de ubicaciones** (lista de puntos recientes del grupo).
- Solo se ven miembros con consentimiento activo (misma regla que el mapa).
- Retención en consulta: últimas 24 h (RPC hasta 72 h).

## Nota

Sin este SQL el mapa en vivo sigue funcionando; el historial queda vacío.
