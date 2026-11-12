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
- Toca una fila → mapa centrado en ese punto.
- Solo se ven miembros con consentimiento activo (misma regla que el mapa).
- Retención en consulta: últimas 24 h (RPC hasta 72 h).

## Muestreo (cliente)

Tabla: `public.location_history` (sin cambio de esquema).

- Máximo **1 punto cada 5 minutos** por usuario.
- Si la coordenada es casi la misma que la anterior (< 5 m), **no se guarda**
  duplicado (estático).
- El mapa en vivo (`location_updates`) sigue con heartbeat corto.

## Nota

Sin este SQL el mapa en vivo sigue funcionando; el historial queda vacío.
