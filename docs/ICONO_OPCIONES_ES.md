# Icono launcher — opciones (pendiente de confirmación)

**No finalizar** el icono de la app hasta que Wilson confirme
(**A / B / B-rounded / C / D** o un tweak). El APK actual usa un icono
**provisional** (`logo-gps-fmra-v2.jpg`, branding GPS — no GPR).

## Dónde verlas

| Opción | Archivo (repo) | Store |
|--------|----------------|-------|
| **A** | `assets/branding/icon-opciones/icon-opcion-a.jpg` | `media/icon-opciones/icon-opcion-a.jpg` |
| **B** | `assets/branding/icon-opciones/icon-opcion-b.jpg` | `media/icon-opciones/icon-opcion-b.jpg` |
| **B-rounded** | `assets/branding/icon-opciones/icon-opcion-b-rounded.jpg` | `media/icon-opciones/icon-opcion-b-rounded.jpg` |
| **C** | `assets/branding/icon-opciones/icon-opcion-c.jpg` | `media/icon-opciones/icon-opcion-c.jpg` |
| **D** | `assets/branding/icon-opciones/icon-opcion-d.jpg` | `media/icon-opciones/icon-opcion-d.jpg` |

## Resumen visual

- **A** — Escudo + familia + pin rojo + texto «GPS / FMRA» (círculo azul, look clásico de marca).
- **B** — Pin grande blanco con siluetas de grupo + «GPS-FMRA» abajo (círculo).
- **B-rounded** — Misma idea que B, en **cuadrado con esquinas redondeadas** (squircle).
- **C** — Escudo + familia + badge rojo **SOS** (cruz) + pin; enfatiza emergencia.
- **D** — Escudo con recorte de pin + tipografía «GPS» (paleta distinta / más gráfica).

## Cómo aplicar cuando confirmes

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
dart run tool/generate_launcher_icons.dart --option b-rounded   # o a / b / c / d
flutter build apk --debug
# copiar a APK\gps-fmra-debug-01.apk y 02
```

Respuesta esperada de Wilson: **sí, B-rounded** (o A/B/C/D / tweak).
Hasta entonces el launcher **no se bloquea** con ninguna opción.

## Mientras tanto

Perfil, foto, SOS e FCM siguen en el PR; el launcher provisional solo evita
el icono Flutter default.
