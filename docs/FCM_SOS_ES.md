# Push FCM para SOS (GPS-FMRA)

Objetivo: cuando alguien pulsa **SOS**, los demás integrantes reciben una
**notificación en el teléfono** (aunque la app esté en segundo plano), además
del banner rojo in-app si la tienen abierta.

Sin Firebase configurado la app **sigue funcionando**: SOS se guarda en
`sos_events` y los compañeros lo ven en el mapa (Realtime / polling).

## 1. Proyecto Firebase (consola)

1. Abre [Firebase Console](https://console.firebase.google.com/) → **Add project**
   (o usa uno existente). Nombre sugerido: `GPS-FMRA`.
2. En el proyecto → **Add app** → **Android**.
3. **Android package name** (debe coincidir exacto):
   `com.gpsfmra.gps_fmra`
4. Descarga **`google-services.json`**.
5. Cópialo a:
   `D:\APPS PROYECTOS\GPS-FMRA\android\app\google-services.json`
   (está en `.gitignore`; no lo subas a Git).
6. En Firebase → **Project settings** → **Cloud Messaging**: confirma que
   la API FCM esté habilitada (por defecto lo está en proyectos nuevos).

Plantilla de referencia (no sirve sola):  
`android/app/google-services.json.example`

## 2. Cuenta de servicio (para la Edge Function)

1. Firebase / Google Cloud → **IAM & Admin** → **Service accounts**.
2. Crea o usa una cuenta con rol **Firebase Cloud Messaging API Admin**
   (o “Firebase Admin SDK Administrator Service Agent”).
3. **Keys** → **Add key** → JSON → descarga el archivo.
4. En Supabase Dashboard → **Edge Functions** → **Secrets** (o CLI):

```bash
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(Get-Content -Raw .\ruta\al-servicio.json)"
```

También asegúrate de tener `SUPABASE_SERVICE_ROLE_KEY` disponible para
funciones (Supabase lo inyecta en el runtime de Edge Functions).

## 3. SQL (SQL Editor)

Ejecuta en orden (si aún no lo hiciste), ver `supabase/APPLY_ES.md`:

1. `20261102260000_sos_events.sql`
2. `20261102270000_device_push_tokens.sql`

Éxito esperado: **Success. No rows returned**.

## 4. Desplegar Edge Function `notify-sos`

Desde la carpeta del repo (con proyecto linkeado):

```bash
cd "D:\APPS PROYECTOS\GPS-FMRA"
npx supabase functions deploy notify-sos
```

La app, tras crear un SOS, llama a `functions.invoke('notify-sos')`.
Si la función no está desplegada o falta el secret, el SOS **igual se guarda**
y el banner in-app funciona; solo falla el push.

## 5. Rebuild APK

Tras colocar `google-services.json`:

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

Copia a `APK\gps-fmra-debug-01.apk` / `02` (ver `docs/APK_ES.md`).

## 6. Probar push

1. Dos teléfonos, mismo grupo, ambos con sesión y permiso de notificaciones.
2. En el teléfono A (en segundo plano o pantalla bloqueada): espera.
3. En B: Mapa → botón rojo **SOS** → confirmar.
4. A debe recibir notificación: **«SOS — GPS-FMRA»** /
   **«¡SOS! {nombre} necesita ayuda.»**
5. Con la app abierta: banner rojo + (si FCM foreground) notificación local.

## Notas

- No es un chat: solo alerta corta SOS.
- Canal Android: `sos_alerts`.
- Tokens en tabla `device_push_tokens` (RLS: solo el dueño escribe/lee su fila;
  el envío usa RPC `list_group_push_tokens` vía service role en la función).
