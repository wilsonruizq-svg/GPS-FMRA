# Aplicar migraciones GPS-FMRA (Fase 1)

Las migraciones están en `supabase/migrations/`. **No incluyen secretos.**

## Opción A — SQL Editor (recomendada si no tienes la DB password a mano)

1. Abre el proyecto en [Supabase Dashboard](https://supabase.com/dashboard).
2. Ve a **SQL Editor** → **New query**.
3. Abre el archivo local:
   `supabase/migrations/20261102150000_fase1_mvp_schema.sql`
4. Copia **todo** el contenido y pégalo en el editor.
5. Pulsa **Run**.
6. Verifica en **Table Editor** que existan:
   `profiles`, `family_groups`, `group_memberships`, `invitations`,
   `location_consents`, `location_updates`, `user_settings`.
7. En **Authentication → Policies** (o Table → RLS) confirma que RLS está **ON**.

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
   Si Auth falla, prueba el JWT legacy **anon public** (`eyJ...`) de
   **Project Settings → API**.
4. `flutter pub get` y `flutter run`.

## Qué NO hace esta migración

- Tablas de chat / SOS (Fase 2+).
- Edge Functions de invitaciones (aceptación segura con rate-limit).
- Buckets de Storage para fotos.
