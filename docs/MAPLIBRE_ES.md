# MapLibre en GPS-FMRA (Android)

El mapa del MVP usa **`maplibre_gl`** (MapLibre Native). **No necesitas clave de pago** para ver el mapa: por defecto se carga **OpenFreeMap Liberty** (OSM, $0).

Google Maps queda **pausado** (billing Cloud). Guía antigua: [`GOOGLE_MAPS_ES.md`](GOOGLE_MAPS_ES.md).

## Qué verás sin configurar nada

1. Copia `.env.example` → `.env` y rellena solo Supabase.
2. `flutter pub get` → `flutter run` (o instala el APK debug).
3. Tras login, la pestaña **Mapa** pide permiso de ubicación al abrir y arranca centrada en tu GPS (`initialCameraPosition`). Solo usa Bogotá si no hay GPS/permiso.
4. FAB **Mi ubicación**: vuelve a centrar (pide permiso OS si hace falta) y anima la cámara.
5. Etiqueta inferior: «MapLibre · estilo libre (sin clave)».
6. Pines de familiares: **stub** (lista de integrantes debajo; coords en vivo más adelante).

## Estilos (elige uno)

| Estilo | Clave | Cómo |
|--------|-------|------|
| **OpenFreeMap Liberty** (default) | No | No pongas `MAP_STYLE_URL` ni `MAPTILER_API_KEY` |
| **Demotiles MapLibre** (smoke mínimo) | No | `MAP_STYLE_URL=https://demotiles.maplibre.org/style.json` |
| **MapTiler Streets v2** (Free) | Sí (gratis) | Cuenta en [cloud.maptiler.com](https://cloud.maptiler.com/) → API key → `MAPTILER_API_KEY=…` en `.env` |
| URL custom | Depende | `MAP_STYLE_URL=https://…/style.json` |

Orden de resolución en código (`Env.mapStyleUrl`):

1. `MAP_STYLE_URL` si tiene valor real  
2. Si no, y hay `MAPTILER_API_KEY` → Streets v2 de MapTiler  
3. Si no → OpenFreeMap Liberty  

## MapTiler Free (opcional)

- Plan Free: **$0**, sin tarjeta; cuota mensual limitada (aprox. 5 000 sesiones / 100 k requests).
- Uso no comercial / PoC; antes de Play Store comercial revisar ToS o pasar a Flex / self-host.
- Solo hace falta pegar la key en **`.env`** (no en `local.properties`; eso era de Google).

```env
MAPTILER_API_KEY=tu_clave_maptiler
```

Luego reinicia la app (`flutter run` o reinstala el APK).

## Requisitos de build

- Flutter **3.29+** (proyecto en 3.47+)
- **JDK 21** para Android (el plugin MapLibre lo exige)
- Internet en el dispositivo (tiles online; offline = fase posterior)

## Archivos relevantes

| Archivo | Rol |
|---------|-----|
| `maplibre_gl` en `pubspec.yaml` | SDK del mapa |
| `Env.mapStyleUrl` | Resuelve el estilo |
| `map_shell_screen.dart` | `MapLibreMap` + centrado GPS + FAB + lista |
| `geolocator` en `pubspec.yaml` | Posición actual del dispositivo |
| `.env` / `.env.example` | `MAP_STYLE_URL`, `MAPTILER_API_KEY` |

**No subas claves a Git.**
