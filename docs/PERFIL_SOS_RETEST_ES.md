# Retest rápido — Perfil, foto y SOS

Tras APPLY de migraciones (ver `supabase/APPLY_ES.md` ítems 7–9) e instalar
`APK\gps-fmra-debug-01.apk` / `02`.

## SQL (Dashboard → SQL Editor)

Ejecutar si aún no:

1. `supabase/migrations/20261102250000_avatars_storage.sql`  
   Éxito: **Success. No rows returned** (o Success con filas del bucket).
2. `supabase/migrations/20261102260000_sos_events.sql`  
   Éxito: **Success. No rows returned**.
3. `supabase/migrations/20261102270000_device_push_tokens.sql`  
   Éxito: **Success. No rows returned**.

Confirmar: Storage → bucket **avatars**; Table Editor → **sos_events**,
**device_push_tokens**.

## Perfil

1. Iniciar sesión → **Ajustes** → **Perfil**.
2. Cambiar nombre (obligatorio) y teléfono opcional → **Guardar cambios**.
3. Debe verse snackbar «Perfil actualizado.»
4. Con bucket aplicado: **Añadir foto** / cámara o galería → foto en círculo.
5. **Quitar foto** + guardar limpia el avatar.

## SOS (in-app, sin Firebase)

1. Dos teléfonos, mismo grupo, app abierta en el mapa.
2. Teléfono B: botón rojo **SOS** → diálogo → **Enviar SOS**.
3. B: snackbar «Alerta SOS enviada al grupo.» + banner «Tu alerta SOS…».
4. A: banner rojo «¡SOS! {nombre} necesita ayuda.»
5. B: **Cancelar alerta** quita el banner en ambos (tras refresh/Realtime).

## Push FCM (opcional)

Solo si Wilson completó `docs/FCM_SOS_ES.md` (`google-services.json` +
Edge Function + secret):

1. Teléfono A en segundo plano.
2. B envía SOS → A recibe notificación del sistema.
