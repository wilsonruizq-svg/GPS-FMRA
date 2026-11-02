# Crear cuenta admin (Dashboard + SQL)

Email de ejemplo de dueño: `wruizq@gmail.com`.  
**La contraseña la define el dueño** en el Dashboard; no se guarda en el repo.

## Roles reales en el esquema

No hay columna `admin_general` en `profiles`.

| Producto | Columna / valor | Cómo |
|----------|-----------------|------|
| Admin de grupo | `group_memberships.role = 'group_admin'` | Trigger al crear `family_groups` |
| Admin general | `group_memberships.role = 'org_admin'` | SQL (o UI futura) |
| Integrante | `member` | Membresía / invitación |

`is_group_admin()` acepta `group_admin` **y** `org_admin`. Los admins **no** eluden consentimiento de ubicación.

## Clics en Supabase

1. [Authentication → Providers](https://supabase.com/dashboard/project/dgmzewsxbnwxjpnrtgyb/auth/providers) → **Email** → **Confirm email** OFF → Save.
2. [Authentication → Users](https://supabase.com/dashboard/project/dgmzewsxbnwxjpnrtgyb/auth/users) → **Add user** → **Create new user**.
3. Email + password (la tuya) → **Auto Confirm User** → **Create user**.
4. Si el esquema MVP no está aplicado: SQL Editor → pegar `migrations/20261102150000_fase1_mvp_schema.sql` → Run.
5. SQL Editor → scripts de `scripts/ensure_profile_and_org_admin.sql` (diagnóstico / perfil / promover).
6. En la app: iniciar sesión → **Grupos** → crear grupo (queda `group_admin`); o promover a `org_admin` con el SQL.

Detalle paso a paso ampliado: guía del Project store `docs/cuenta-admin-wilson.md`.

## App tras pull

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA"
git pull origin main
flutter pub get
flutter run
```

Hot reload `r` / hot restart `R` solo si ya corrías esa revisión; tras pull de Auth preferible `flutter run` limpio.
