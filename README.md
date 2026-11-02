# GPS-FMRA

App Flutter (Android-first) de protección familiar y localización. UI en español. Fase 1: Auth + grupos + consentimiento + mapa (Google Maps si hay clave).

## Requisitos

- Flutter **3.47+** / Dart **3.13+**
- Android SDK (minSdk **23**)
- Proyecto Supabase (URL + clave anon/publishable)
- Emulador Android o dispositivo USB con depuración

```bash
flutter doctor
```

## Configurar secretos (local)

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
copy .env.example .env
```

Edita `.env`:

| Variable | Obligatorio | Notas |
|----------|-------------|--------|
| `SUPABASE_URL` | Sí | `https://….supabase.co` |
| `SUPABASE_ANON_KEY` | Sí | `sb_publishable_…` o JWT anon `eyJ…` |
| `GOOGLE_MAPS_API_KEY` | Para mapa real | Misma clave en `.env` **y** `android/local.properties` |

**No subas `.env` ni pongas la clave en Git.**

### Cómo añadir Google Maps (Wilson)

Guía con clics exactos: [`docs/GOOGLE_MAPS_ES.md`](docs/GOOGLE_MAPS_ES.md).

Resumen:

1. Google Cloud → habilitar **Maps SDK for Android** → crear clave API.
2. Restringir a paquete `com.gpsfmra.gps_fmra` + SHA-1 debug (`cd android; .\gradlew signingReport`).
3. Pegar la clave en `.env` y en `android/local.properties` como `GOOGLE_MAPS_API_KEY=…`.
4. `flutter run` — con clave válida se muestra `GoogleMap`; sin clave, el placeholder.

## Ejecutar en emulador / dispositivo

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
flutter pub get
flutter devices
flutter run
```

Flujo: **splash → login/registro Supabase → consentimiento → mapa / grupos / ajustes**.

- Si Auth pide confirmar correo: revisa la bandeja o desactiva **Confirm email** en Supabase → Authentication → Providers → Email.
- El trigger `on_auth_user_created` crea `profiles` + `user_settings`; la app también hace `ensureOwnProfile` por si hiciera falta.

## Migraciones SQL

Guía: [`supabase/APPLY_ES.md`](supabase/APPLY_ES.md).

| Archivo | Contenido |
|---------|-----------|
| `20261102150000_fase1_mvp_schema.sql` | Tablas + RLS |
| `20261102200000_accept_invitation_rpc.sql` | RPC `accept_invitation` (aceptar código) |
| `20261102210000_fix_accept_invitation_pgcrypto.sql` | Fix `digest` / pgcrypto (**APPLY** si falla aceptar) |

**Importante:** sin la RPC, “Unirme con código” falla. Si el error es
`digest(bytea, unknown)`, pega el archivo `…pgcrypto.sql` en SQL Editor.

Prueba con dos cuentas: [`docs/INVITACIONES_PRUEBA_ES.md`](docs/INVITACIONES_PRUEBA_ES.md).

## Pantallas MVP (esta entrega)

| Pantalla | Qué hace |
|----------|----------|
| Auth | Registro/login email-password; perfil vía trigger + fallback |
| Consentimiento | Explica compartir; Aceptar / Pausar; pide permiso de ubicación en contexto |
| Mapa | Placeholder si no hay billing/clave Maps; `GoogleMap` si hay clave |
| Grupos | Crear/seleccionar grupo, invitar (hash/un uso/caducidad), unirse con código |
| Tarjeta miembro | Nombre, rol, estado de compartir |
| Ajustes | Perfil, privacidad, cerrar sesión |

**No incluido:** chat, SOS, WebRTC, mapas offline. Maps pausado por billing.

## Análisis

```bash
flutter analyze
flutter test
```
