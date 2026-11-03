# SOS — Aceptar de todo el grupo

## Qué hace

1. Un integrante envía **SOS**.
2. Cada compañero ve el banner **SOS de {Nombre}** y pulsa **Aceptar**
   (se guarda un acuse en `sos_acks` y se oculta el banner en su teléfono).
3. En el teléfono del **emisor** el banner **sigue visible** y muestra
   quién falta (`Confirmaciones X/Y. Pendiente: …`).
4. Cuando **todos** los miembros activos del grupo (excepto el emisor)
   aceptaron, el SOS pasa a `resolved` y el banner del emisor se limpia.
5. El emisor puede **Cancelar alerta** en cualquier momento.

## APPLY (Wilson) — obligatorio para esta versión

1. Supabase → **SQL Editor** → **New query**.
2. Pega **todo** el archivo:
   `supabase/migrations/20261102273000_sos_acks.sql`
3. **Run**. Al final debe verse `sos_acks_ok = true`.
4. Reinicia la app (o reinstala los APK 01/02 nuevos).

Sin este SQL, **Aceptar** del compañero falla al registrar el ack
(el banner local puede ocultarse, pero el emisor no verá confirmaciones).

## Prueba rápida (2 teléfonos)

1. Instala `APK/gps-fmra-debug-01.apk` y `02`, mismo grupo.
2. A envía SOS → banner rojo con pendientes.
3. B pulsa **Aceptar** → banner de B desaparece; A ve `1/1` o deja de
   mostrar a B como pendiente.
4. Si solo hay 2 miembros: al aceptar B, el SOS se cierra en A.
5. Con 3+ miembros: A sigue hasta que el último acepte (o cancele).
