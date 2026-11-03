# Icono launcher — opciones A–D (pendiente de Wilson)

**No finalizar** el icono de la app hasta que Wilson elija **A / B / C / D**
(o pida un ajuste). El APK actual usa un icono **provisional**
(`logo-gps-fmra-v2.jpg`, branding GPS — no GPR).

## Dónde verlas

| Opción | Archivo (repo) | Store |
|--------|----------------|-------|
| **A** | `assets/branding/icon-opciones/icon-opcion-a.jpg` | `media/icon-opciones/icon-opcion-a.jpg` |
| **B** | `assets/branding/icon-opciones/icon-opcion-b.jpg` | `media/icon-opciones/icon-opcion-b.jpg` |
| **C** | `assets/branding/icon-opciones/icon-opcion-c.jpg` | `media/icon-opciones/icon-opcion-c.jpg` |
| **D** | `assets/branding/icon-opciones/icon-opcion-d.jpg` | `media/icon-opciones/icon-opcion-d.jpg` |

## Resumen visual

- **A** — Escudo + familia + pin rojo + texto «GPS / FMRA» (círculo azul, look clásico de marca).
- **B** — Pin grande blanco con siluetas de grupo + «GPS-FMRA» abajo (más simple, legible en chico).
- **C** — Escudo + familia + badge rojo **SOS** (cruz) + pin; enfatiza emergencia.
- **D** — Escudo con recorte de pin + tipografía «GPS» (paleta distinta / más gráfica).

## Cómo aplicar cuando elijas

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
dart run tool/generate_launcher_icons.dart --option a   # o b / c / d
flutter build apk --debug
# copiar a APK\gps-fmra-debug-01.apk y 02
```

Respuesta esperada de Wilson: **A**, **B**, **C**, **D**, o un tweak concreto
(p. ej. «C sin badge SOS», «B sin texto»).

## Mientras tanto

Siguen avanzando perfil, foto, SOS e FCM en el mismo PR — el launcher
provisional solo evita el icono Flutter default.
