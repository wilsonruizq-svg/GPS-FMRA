# Mensajes personales (1:1)

Chat directo entre dos integrantes. El chat de **grupo** sigue igual
(icono burbuja del grupo).

## APPLY (Wilson) — obligatorio

1. Supabase → proyecto `dgmzewsxbnwxjpnrtgyb` → **SQL Editor** → New query.
2. Abre y copia **todo**:
   `D:\APPS PROYECTOS\GPS-FMRA\supabase\migrations\20261102282000_direct_messages.sql`
3. Pegar → **Run**.
4. Debe verse:
   - `direct_messages_ok = true`
   - `direct_messages_realtime_ok = true`
5. Table Editor → tabla `direct_messages`.

Sin este SQL, al abrir un DM la app muestra el aviso de SQL faltante.

## Cómo abrir un DM

1. En **Mapa**, lista de integrantes debajo del mapa: toca el icono de
   **mensaje** (burbuja) a la derecha de un compañero (no en “tú”).
2. O en **Grupos** → detalle del grupo → mismo icono en la fila del integrante.
3. Escribe y envía. El otro, con la app abierta (Mapa u otra pantalla),
   recibe notificación local + snackbar (mismo patrón que el chat de grupo).

## Notas

- Solo las dos personas del hilo ven los mensajes (RLS).
- Alertas en primer plano: Realtime + polling. Background FCM de DM queda
  para después (igual que grupo: secret + Edge Function).
