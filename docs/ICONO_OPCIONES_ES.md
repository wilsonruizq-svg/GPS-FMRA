# Icono launcher — opciones (pendiente de confirmación)

**No finalizar** el icono hasta que Wilson confirme (**E / F / G**
recomendados, o A–D / tweak). El APK actual usa un icono **provisional**
(`logo-gps-fmra-v2.jpg`) — Wilson nota que se ve “tipo foundation”; las
nuevas **E/F/G** son **cuadrado con esquinas redondeadas (squircle)**.

## Nuevas (elegir una)

| Opción | Archivo (repo) | Store |
|--------|----------------|-------|
| **E** pin | `assets/branding/icon-opciones/icon-e-pin.jpg` | `media/icon-opciones/icon-e-pin.jpg` |
| **F** radar | `assets/branding/icon-opciones/icon-f-radar.jpg` | `media/icon-opciones/icon-f-radar.jpg` |
| **G** monogram | `assets/branding/icon-opciones/icon-g-monogram.jpg` | `media/icon-opciones/icon-g-monogram.jpg` |

### Resumen visual

- **E — Pin:** Squircle azul oscuro, pin cian con borde blanco + texto **GPS**.
- **F — Radar:** Squircle azul con retícula/radar, pin rojo al centro + **FMRA**.
- **G — Monograma:** Squircle oscuro, letra **G** formando pin (punta roja) + **GPS-FMRA**.

## Anteriores (A–D)

| Opción | Archivo |
|--------|---------|
| **A** | `icon-opcion-a.jpg` — escudo + familia + pin (círculo) |
| **B** | `icon-opcion-b.jpg` — pin grande + grupo (círculo) |
| **B-rounded** | `icon-opcion-b-rounded.jpg` — B en squircle |
| **C** | `icon-opcion-c.jpg` — escudo + badge SOS |
| **D** | `icon-opcion-d.jpg` — escudo tipográfico |

## Cómo aplicar **cuando Wilson confirme** (aún no)

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
dart run tool/generate_launcher_icons.dart --option e   # o f / g
flutter build apk --debug
# copiar a APK\gps-fmra-debug-01.apk y 02
```

Respuesta esperada: **E**, **F**, **G**, o “refinar …”.  
Hasta entonces el launcher **no se bloquea** con ninguna opción.
