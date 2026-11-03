# Retest SOS (español)

## Diagnóstico

Si el SOS no guardaba / el API respondía **404**, la tabla no estaba
visible a PostgREST. Arreglo:

**`supabase/migrations/20261102261000_sos_events_api_fix.sql`**

1. SQL Editor → New query → pegar **todo** el archivo → **Run**.
2. Al final debe verse `sos_events_ok = true` (y grants).
3. Reinicia la app (o cierra sesión y entra).

## Prueba con 2 teléfonos

1. Instala `APK/gps-fmra-debug-01.apk` y `02` (mismo grupo).
2. Ambos en pestaña **Mapa**, grupo seleccionado.
3. Teléfono A: botón rojo **SOS** → confirmar **Enviar SOS**.
4. A: snackbar de enviado + banner rojo «Tu alerta SOS está activa».
5. B (app abierta): en ≤5 s banner «¡SOS! {nombre} necesita ayuda.»
   (Realtime o poll). Tocar **Entendido** centra el mapa si hay coords.
6. A: **Cancelar alerta** → el banner desaparece en ambos.
7. Push FCM: solo si Firebase + Edge Function están configurados
   (`docs/FCM_SOS_ES.md`); sin eso el banner in-app basta.

## Foto de perfil (recorte)

Ajustes → Perfil → Añadir foto → galería/cámara → **recorta en cuadrado**
→ se comprime ≤768px y sube.
