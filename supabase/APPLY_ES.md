# Aplicar migraciones GPS-FMRA (Fase 1)

Las migraciones están en `supabase/migrations/`. **No incluyen secretos.**

## Opción A — SQL Editor (recomendada si no tienes la DB password a mano)

1. Abre el proyecto en [Supabase Dashboard](https://supabase.com/dashboard).
2. Ve a **SQL Editor** → **New query**.
3. Abre y ejecuta **en orden** estos archivos locales (todo el contenido
   de cada uno → **Run**):
   1. `supabase/migrations/20261102150000_fase1_mvp_schema.sql`
   2. `supabase/migrations/20261102200000_accept_invitation_rpc.sql`
   3. `supabase/migrations/20261102210000_fix_accept_invitation_pgcrypto.sql`
      (**APPLY** si ves `function digest(bytea, unknown) does not exist` —
      este archivo solo basta para el fix; pégalo completo → Run.)
   4. `supabase/migrations/20261102220000_group_exit_pin.sql`
      (PIN de salida del grupo: columnas + RPCs bcrypt. Obligatorio para
      que “Cerrar sesión” / Atrás pidan PIN.)
   5. `supabase/migrations/20261102230000_location_share_realtime.sql`
      (**APPLY** para pines en vivo: `REPLICA IDENTITY FULL` + publicación
      Realtime de `location_updates`. Sin esto el mapa puede seguir
      refrescando por polling, pero Realtime no entrega DELETE/UPDATE bien.)
   6. `supabase/migrations/20261102240000_fix_peer_location_visibility.sql`
      (**APPLY obligatorio si solo ves 1 pin** con 2 miembros + consentimiento:
      endurece `can_view_location` / helpers con `row_security=off` y añade
      RPC `list_group_locations` para que ambos pines sean visibles.)
   7. `supabase/migrations/20261102251000_avatars_storage_hosted.sql`
      (**APPLY para foto de perfil en Supabase hosted.** Crea bucket
      público `avatars` + policies. **No** hace COMMENT/ALTER sobre
      `storage.objects` (evita ERROR 42501 must be owner of table objects).
      Éxito esperado: **Success. No rows returned**.
      Si ya corriste el archivo viejo `20261102250000_…` y falló al final,
      corre **este** `…251000…_hosted.sql` — es seguro e idempotente.)
   8. `supabase/migrations/20261102260000_sos_events.sql`
      (**APPLY para botón SOS:** tabla `sos_events` + RLS + Realtime.
      Éxito esperado: **Success. No rows returned**.)
   9. `supabase/migrations/20261102270000_device_push_tokens.sql`
      (**APPLY para push FCM:** tabla `device_push_tokens` + RPC
      `list_group_push_tokens`. Éxito esperado: **Success. No rows returned**.
      Guía Firebase: `docs/FCM_SOS_ES.md`.)
   10. `supabase/migrations/20261102261000_sos_events_api_fix.sql`
      (**APPLY si SOS da 404 / “tabla no visible”:** GRANT + RPC `raise_sos`
      + `NOTIFY pgrst, 'reload schema'`. Al final debe verse
      `sos_events_ok = true`. Guía: `docs/SOS_RETEST_ES.md`.)
   11. `supabase/migrations/20261102272000_location_history.sql`
      (**APPLY para historial GPS:** tabla `location_history` + RPC
      `list_group_location_history`. Éxito: `location_history_ok = true`.
      Guía: `docs/HISTORIAL_ES.md`.)
   12. `supabase/migrations/20261102273000_sos_acks.sql`
      (**APPLY para Aceptar grupal:** tabla `sos_acks` + RPC `ack_sos` /
      `list_sos_ack_progress`. El emisor ve pendientes; el SOS se resuelve
      cuando todos los compañeros aceptan. Éxito: `sos_acks_ok = true`.
      Guía: `docs/SOS_ACKS_ES.md`.)
   13. `supabase/migrations/20261102280000_group_messages.sql`
      (**APPLY para chat del grupo:** tabla `group_messages` + RLS +
      Realtime. Éxito: `group_messages_ok = true`. Guía: `docs/CHAT_ES.md`.)
   14. `supabase/migrations/20261102281000_group_messages_realtime.sql`
      (**APPLY si chat OK pero sin alertas:** asegura publication Realtime.
      Éxito: `group_messages_realtime_ok = true`.)
4. Verifica en **Table Editor** que existan:
   `profiles`, `family_groups`, `group_memberships`, `invitations`,
   `location_consents`, `location_updates`, `user_settings`, `sos_events`,
   `device_push_tokens`, `sos_acks`, `group_messages`.
5. En **Storage → Buckets** confirma el bucket **`avatars`** (público).
6. En **Database → Functions** confirma `accept_invitation(text)`,
   `set_group_exit_pin`, `clear_group_exit_pin`, `group_has_exit_pin`,
   `exit_pin_is_required`, `verify_exit_pin`, `list_group_locations`,
   `can_view_location`, `list_group_push_tokens`.
7. En **Authentication → Policies** (o Table → RLS) confirma que RLS está **ON**.
8. En **Database → Replication** (o Publication) confirma que
   `location_updates`, `sos_events` y `group_messages` están en
   `supabase_realtime`.

## Diagnóstico rápido — solo 1 pin (2 miembros, 1 grupo)

Con sesión de servicio / SQL Editor (como postgres), pega:

```sql
-- Cuenta membresías, consentimientos y fixes por grupo
select
  g.id as group_id,
  g.name,
  (select count(*) from group_memberships gm
    where gm.group_id = g.id and gm.status = 'active') as members,
  (select count(*) from location_consents lc
    where lc.group_id = g.id and lc.scope = 'group' and lc.status = 'active') as active_consents,
  (select count(*) from location_updates lu
    join group_memberships gm on gm.user_id = lu.user_id
     and gm.group_id = g.id and gm.status = 'active') as location_rows
from family_groups g
where g.status = 'active'
order by g.created_at desc
limit 10;
```

Esperado con 2 teléfonos compartiendo: `members >= 2`, `active_consents >= 2`,
`location_rows >= 2`. Si `location_rows = 1`, el segundo teléfono aún no
publicó GPS (abrir Mapa + permiso OS + consentimiento activo).
Si `active_consents = 1`, el segundo debe ir a Consentimiento → Aceptar.

## Opción B — Supabase CLI

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
npx supabase login
npx supabase link --project-ref dgmzewsxbnwxjpnrtgyb
npx supabase db push
```

`link` / `db push` pedirán la **database password** del proyecto
(Settings → Database). Sin esa contraseña no se puede aplicar desde CLI.

## Clave anon / publishable para Flutter

1. Copia `.env.example` → `.env` (ya gitignored).
2. Pon `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
3. La app inicializa Supabase con `publishableKey` (acepta `sb_publishable_...`).
   Si Auth responde **401 / invalid API key**, prueba el JWT legacy **anon public**
   (`eyJ...`) de **Project Settings → API**.
   Un error `Connection reset by peer` / `SocketException` **no** se arregla
   cambiando la clave: es red del dispositivo/operador.
4. `flutter pub get` y `flutter run`.

## Confirm email (recomendado OFF para pruebas Android)

Con **Confirm email** activo, cada signup intenta mandar correo. En free tier
eso dispara rápido `email rate limit exceeded` / `over_email_send_rate_limit`.

Para pruebas en el dispositivo:

1. Abre [Authentication → Sign In / Providers](https://supabase.com/dashboard/project/dgmzewsxbnwxjpnrtgyb/auth/providers).
2. Expande **Email**.
3. Desactiva el toggle **Confirm email**.
4. **Save**.

Tras eso, `signUp` no envía email y la sesión inicia al instante.
Si dejas Confirm email ON y ves rate limit: espera unos minutos o apaga el toggle.

## Red / Connection reset en el teléfono

Desde un PC de desarrollo, `https://dgmzewsxbnwxjpnrtgyb.supabase.co/auth/v1/health`
y `POST /auth/v1/signup` deben responder (TLS OK vía Cloudflare).

Si en el **móvil** (p. ej. Realme) ves
`ClientException … SocketException: Connection reset by peer` hacia
`/auth/v1/signup`:

1. Prueba otra red (Wi‑Fi vs datos, hotspot del PC).
2. Desactiva VPN / ahorro de datos / firewall del teléfono.
3. Abre en el navegador del teléfono:
   `https://dgmzewsxbnwxjpnrtgyb.supabase.co/auth/v1/health`
4. Si el navegador también falla y el PC no: causa probable = red/operador
   hacia `*.supabase.co` (Cloudflare), no la clave ni el código Android HTTPS.

Android ya declara `INTERNET`; HTTPS no necesita cleartext.

## Qué NO hace esta migración

- Chat / mensajería (sigue fuera de v1; SOS es alerta corta + push, sin chat).
- Edge Functions con rate-limit anti-fuerza bruta (la aceptación Fase 1
  usa RPC `accept_invitation` security definer; rate-limit queda para endurecer).
- Push FCM queda **preparado** (`notify-sos` + tokens); requiere que Wilson
  complete Firebase + secret (ver `docs/FCM_SOS_ES.md`). Sin eso, SOS in-app
  (banner/Realtime) sigue operativo.
