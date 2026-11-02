# GPS-FMRA

App Flutter (Android-first) de protección familiar y localización. UI en español. Fase 1: Auth + grupos + consentimiento + mapa placeholder.

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
| `GOOGLE_MAPS_API_KEY` | No (Fase 1) | Si falta, la app muestra marcador de posición + lista de miembros |

**No subas `.env`.**

### Cómo añadir Google Maps (Wilson)

1. Crea una clave en [Google Cloud Console](https://console.cloud.google.com/) con **Maps SDK for Android** (y iOS si aplica).
2. Restringe la clave por paquete `com.gpsfmra.gps_fmra` + SHA-1 de debug/release.
3. Ponla en `.env`:

```env
GOOGLE_MAPS_API_KEY=AIza...tu_clave
```

4. En un hito posterior se cableará el SDK (`google_maps_flutter`) y el meta-data en `AndroidManifest.xml`. **Hoy**, con o sin clave, el mapa es un placeholder explícito.

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

Ya aplicadas en el proyecto live (`Success. No rows returned`). Guía: [`supabase/APPLY_ES.md`](supabase/APPLY_ES.md).

Archivo: `supabase/migrations/20261102150000_fase1_mvp_schema.sql`

## Pantallas MVP (esta entrega)

| Pantalla | Qué hace |
|----------|----------|
| Auth | Registro/login email-password; perfil vía trigger + fallback |
| Consentimiento | Explica compartir; Aceptar / Pausar; pide permiso de ubicación en contexto |
| Mapa | Placeholder Maps + selector de grupo + lista stub de miembros |
| Grupos | Crear grupo, listar membresías, invitación stub (token + hash SHA-256) |
| Tarjeta miembro | Nombre, estado de compartir, última actualización (placeholder) |
| Ajustes | Perfil, privacidad, cerrar sesión |

**No incluido:** chat, SOS, WebRTC, mapas offline.

## Análisis

```bash
flutter analyze
flutter test
```
