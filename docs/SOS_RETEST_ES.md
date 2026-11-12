# Retest SOS (español)

## Diagnóstico 404

Si el SOS no guardaba / el API respondía **404**:

**`supabase/migrations/20261102261000_sos_events_api_fix.sql`**

1. SQL Editor → pegar **todo** → **Run**.
2. Al final `sos_events_ok = true`.
3. Reinicia la app.

## Acuses Aceptar (obligatorio en builds nuevos)

**`supabase/migrations/20261102273000_sos_acks.sql`** → `sos_acks_ok = true`.  
Detalle: `docs/SOS_ACKS_ES.md`.

## Prueba con 2 teléfonos

1. Instala `APK/gps-fmra-debug.apk` en ambos teléfonos (mismo grupo).
2. Ambos en pestaña **Mapa**, grupo seleccionado.
3. Teléfono A: botón rojo **SOS** → confirmar.
4. A: banner rojo **SOS de {nombre}** + texto de pendientes + **Cancelar alerta**.
5. B: banner **SOS de {nombre}** + **Aceptar** (≤5 s; Realtime o poll).
6. B pulsa **Aceptar** → banner de B se oculta; A ve confirmación / se cierra
   si B era el único compañero.
7. Push FCM: `docs/FCM_SOS_ES.md` (opcional; el flujo de acuses es independiente).

## Foto de perfil (recorte)

Ajustes → Perfil → Añadir foto → galería/cámara → **recorta en cuadrado**
→ se comprime ≤768px y sube.
