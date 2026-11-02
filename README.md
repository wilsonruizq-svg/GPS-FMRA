# GPS-FMRA

App Flutter (Android-first) de protección familiar y localización. UI en español. Fase 1: Auth + esquema Supabase/RLS.

## Requisitos

- Flutter **3.47+** / Dart **3.13+**
- Android SDK (minSdk **23**)
- Proyecto Supabase (URL + clave anon)

```bash
flutter doctor
```

## Configurar secretos (local)

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
copy .env.example .env
```

Edita `.env` con `SUPABASE_URL` y `SUPABASE_ANON_KEY`. **No subas `.env`.**

La app usa `publishableKey` (válido con `sb_publishable_...`). Si Auth falla, prueba el JWT **anon public** (`eyJ...`) de Project Settings → API.

## Ejecutar

```bash
flutter pub get
flutter run
```

Flujo: **splash → login Supabase → consentimiento → mapa placeholder**.

## Migraciones SQL

Ver guía en español: [`supabase/APPLY_ES.md`](supabase/APPLY_ES.md).

Archivo principal:

`supabase/migrations/20261102150000_fase1_mvp_schema.sql`

Tablas MVP: `profiles`, `family_groups`, `group_memberships`, `invitations`, `location_consents`, `location_updates`, `user_settings`. RLS default-deny; los admins **no** eluden el consentimiento de ubicación.

## Módulos (`lib/modules`)

- `auth` — splash, login/registro Supabase
- `location` — consentimiento (placeholder)
- `map` — shell del mapa (sin SDK aún)
- `groups` — lista de grupos (vacía)
- `settings` — ajustes básicos

## Próximos pasos

1. Aplicar la migración en el proyecto Supabase (SQL Editor o `npx supabase db push`).
2. Confirmar JWT anon en `.env` si Auth falla con publishable key.
3. Integrar Google Maps y flujos de grupos/consentimiento reales.
