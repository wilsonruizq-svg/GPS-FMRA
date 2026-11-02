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
4. Verifica en **Table Editor** que existan:
   `profiles`, `family_groups`, `group_memberships`, `invitations`,
   `location_consents`, `location_updates`, `user_settings`.
5. En **Database → Functions** confirma `accept_invitation(text)`.
6. En **Authentication → Policies** (o Table → RLS) confirma que RLS está **ON**.

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

- Tablas de chat / SOS (Fase 2+).
- Edge Functions con rate-limit anti-fuerza bruta (la aceptación Fase 1
  usa RPC `accept_invitation` security definer; rate-limit queda para endurecer).
- Buckets de Storage para fotos.
