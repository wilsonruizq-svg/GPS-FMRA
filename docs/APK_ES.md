# Carpeta de APKs (entrega local)

Todos los APK generados para prueba o entrega van en:

```text
D:\APPS PROYECTOS\GPS-FMRA\APK\
```

| Archivo | Uso |
|---------|-----|
| `APK\gps-fmra-debug.apk` | Último debug (nombre fijo) |
| `APK\gps-fmra-debug-AAAA-MM-DD.apk` | Copia fechada (opcional) |

No uses `dist\` ni dejes APKs sueltos en la raíz del repo.

## Generar y copiar

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
flutter build apk --debug
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" "APK\gps-fmra-debug.apk"
```

`APK\`, `dist\` y `*.apk` están en `.gitignore`. **No commits de binarios.**
