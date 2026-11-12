# Chat del grupo (MVP)

Mensajes de texto entre integrantes del **grupo seleccionado**.
Funciona en primer plano con **Realtime** (sin push FCM en v1).

## APPLY (Wilson) — obligatorio

1. Supabase Dashboard → **SQL Editor** → **New query**.
2. Abre el archivo local:
   `supabase/migrations/20261102280000_group_messages.sql`
3. Copia **todo** el contenido → pégalo → **Run**.
4. Al final debe verse `group_messages_ok = true`.
5. Confirma en **Table Editor** la tabla `group_messages`.
6. En **Database → Replication** (o Publication `supabase_realtime`)
   confirma que `group_messages` está incluida.
7. Reinicia la app (o hot restart) y prueba el chat.

Sin este SQL, abrir chat o enviar falla (tabla/API no visible).

## Cómo abrir el chat en la app

1. Elige un grupo en **Mapa** (selector arriba) → icono de **chat** (burbuja).
2. O entra a **Grupos** → toca el grupo → icono de **chat** en la barra.

## Prueba rápida (2 teléfonos)

1. Mismo grupo, ambos con la app abierta.
2. A escribe y envía → B debe ver el mensaje en segundos (Realtime).
3. B responde → A lo ve sin refrescar manualmente.

## Fuera de v1

- Push FCM al recibir mensaje con app en segundo plano.
- Adjuntos / fotos / reacciones.
- Chats 1:1 aparte del grupo (este MVP es **chat de grupo**).
