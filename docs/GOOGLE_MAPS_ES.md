# Google Maps en GPS-FMRA (Android) — PAUSADO

> **Estado:** Google Maps está **pausado** (billing Cloud ~$30). El mapa del MVP usa **MapLibre** sin clave de pago.  
> Guía activa: [`MAPLIBRE_ES.md`](MAPLIBRE_ES.md).

Esta guía queda por si más adelante se reactiva Google. El cableado Manifest/`local.properties` sigue, pero la UI ya no monta `GoogleMap`.

Paquete Android: `com.gpsfmra.gps_fmra`

## Pasos exactos (Google Cloud Console)

1. Abre [Google Cloud Console](https://console.cloud.google.com/).
2. Arriba: elige o crea un proyecto (ej. `GPS-FMRA`).
3. Menú ☰ → **APIs y servicios** → **Biblioteca**.
4. Busca **Maps SDK for Android** → **Administrar** / **Habilitar**.
5. Menú ☰ → **APIs y servicios** → **Credenciales**.
6. **+ Crear credenciales** → **Clave de API**.
7. Copia la clave (`AIza…`).
8. Pulsa **Restringir clave** (o edita la clave recién creada):
   - **Restricciones de aplicación** → **Aplicaciones de Android**.
   - **Agregar un elemento**:
     - Nombre del paquete: `com.gpsfmra.gps_fmra`
     - Huella SHA-1: la de debug (abajo).
   - **Restricciones de API** → **Restringir clave** → marca solo **Maps SDK for Android**.
9. **Guardar**.

## Obtener SHA-1 de debug

En PowerShell, desde la raíz del repo:

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA\android"
.\gradlew signingReport
```

En la salida busca `Variant: debug` → `SHA1: XX:XX:…`. Usa ese valor en la restricción de la clave.

(Alternativa: `keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android`)

## Dónde pegar la clave (dos sitios)

La misma clave va en **ambos** archivos (locales, no se suben a Git):

### 1. `.env` (Flutter decide si mostrar `GoogleMap`)

```env
GOOGLE_MAPS_API_KEY=AIza...tu_clave
```

### 2. `android/local.properties` (SDK nativo / AndroidManifest)

Añade una línea (no borres `sdk.dir` ni `flutter.sdk`):

```properties
GOOGLE_MAPS_API_KEY=AIza...tu_clave
```

Luego:

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA"
flutter pub get
flutter run
```

Si el mapa queda en blanco tras poner la clave: confirma que está en `local.properties`, que Maps SDK for Android está habilitado, y vuelve a instalar la app (`flutter run`).

## Qué hace el código (referencia)

| Archivo | Rol |
|---------|-----|
| `.env` → `Env.hasMapsConfig` | Si hay clave real, la UI monta `GoogleMap` |
| `android/local.properties` → `build.gradle.kts` → `manifestPlaceholders` | Inyecta la clave en el meta-data |
| `AndroidManifest.xml` | `com.google.android.geo.API_KEY` |
| `google_maps_flutter` | Widget del mapa |

**No subas la clave a Git.** `.env` y `local.properties` están ignorados.
