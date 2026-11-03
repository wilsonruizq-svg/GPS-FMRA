# Retest rápido — Perfil, foto y SOS

Tras APPLY de migraciones (ver `supabase/APPLY_ES.md` ítems 7–9) e instalar
`APK\gps-fmra-debug-01.apk` / `02`.

## SQL exacto para Wilson (Dashboard → SQL Editor)

Pegar **todo el contenido** de cada archivo → **Run**, en este orden:

1. `supabase/migrations/20261102251000_avatars_storage_hosted.sql`  
   → foto de perfil (bucket `avatars`) — **usar este**, no el `…250000…`  
   (el viejo daba ERROR 42501 por COMMENT ON storage.objects).  
   Guía corta: `docs/AVATARS_SQL_WILSON_ES.md`  
   Éxito: **Success. No rows returned**.
2. `supabase/migrations/20261102260000_sos_events.sql`  
   → botón SOS  
   Éxito: **Success. No rows returned**.
3. `supabase/migrations/20261102270000_device_push_tokens.sql`  
   → tokens FCM (opcional para push)  
   Éxito: **Success. No rows returned**.

Si (2) y (3) ya corrieron OK, solo falta (1) hosted.  
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
