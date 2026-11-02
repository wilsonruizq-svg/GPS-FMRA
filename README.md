# GPS-FMRA

App Flutter (Android-first) de protección familiar y localización. UI en español. Fase 1: scaffold MVP.

## Requisitos

- Flutter **3.47+** / Dart **3.13+**
- Android SDK (minSdk **23**)
- Android Studio o VS Code con extensión Flutter

Comprobar entorno:

```bash
flutter doctor
```

## Abrir el proyecto

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
flutter pub get
flutter run
```

Flujo actual del scaffold: **splash → login (shell) → consentimiento → mapa placeholder** (pestañas Grupos / Ajustes).

## Variables de entorno

Copia `.env.example` y completa en local (o usa `--dart-define`). **No subas secretos.**

| Variable | Uso |
|----------|-----|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_ANON_KEY` | Clave anónima (pública) de Supabase |
| `GOOGLE_MAPS_API_KEY` | API key de Google Maps |

Ejemplo:

```bash
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ... --dart-define=GOOGLE_MAPS_API_KEY=AIza...
```

## Módulos (`lib/modules`)

- `auth` — splash y shell de login
- `location` — consentimiento de ubicación (placeholder)
- `map` — shell del mapa (sin SDK aún)
- `groups` — lista de grupos (vacía)
- `settings` — ajustes básicos

## Próximo paso: Supabase

1. Crear el proyecto Supabase (cuenta de Wilson).
2. Configurar Auth + tablas/RLS según la arquitectura.
3. Conectar el cliente Flutter con `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
4. Integrar Google Maps en el shell del mapa.

## Git

Repositorio local listo. **No hay remoto** hasta que Wilson proporcione la URL de GitHub.
