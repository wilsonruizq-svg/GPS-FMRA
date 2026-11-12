# Icono launcher — GPS-FMRA

## Icono elegido (Wilson)

Fuente confirmada:

`assets/branding/gps-fmra-launcher-icon.png`

Mipmaps Android generados con:

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
dart run tool/generate_launcher_icons.dart --source assets/branding/gps-fmra-launcher-icon.png
```

Se aplicará en la **próxima** compilación / APK (`flutter build` / `flutter run`).
No hace falta regenerar a mano salvo que cambie la PNG fuente.

## Opciones históricas (archivo)

| Opción | Archivo |
|--------|---------|
| **E** pin | `assets/branding/icon-opciones/icon-e-pin.jpg` |
| **F** radar | `assets/branding/icon-opciones/icon-f-radar.jpg` |
| **G** monogram | `assets/branding/icon-opciones/icon-g-monogram.jpg` |
| A–D | `icon-opcion-a.jpg` … `d.jpg` / `b-rounded` |
| Provisional viejo | `assets/branding/logo-gps-fmra-v2.jpg` |

```bash
dart run tool/generate_launcher_icons.dart --option e   # solo si se vuelve a una opción
```
