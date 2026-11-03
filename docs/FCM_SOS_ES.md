# Push FCM para SOS (GPS-FMRA)

Objetivo: cuando alguien pulsa **SOS**, los demás integrantes reciben una
**notificación en el teléfono** (aunque la app esté en segundo plano), además
del banner rojo in-app si la tienen abierta.

Sin Firebase configurado la app **sigue funcionando**: SOS se guarda en
`sos_events` y los compañeros lo ven en el mapa (Realtime / polling) con
banner **SOS de {Nombre}** + botón **Aceptar**.

Guía completa abajo. Checklist corto para Wilson:

## Checklist Wilson (orden)

| # | Qué hacer | Dónde / resultado |
|---|-----------|-------------------|
| 1 | Crear proyecto Firebase (o usar uno) | [console.firebase.google.com](https://console.firebase.google.com/) → nombre sugerido `GPS-FMRA` |
| 2 | Añadir app **Android** | Package exacto: `com.gpsfmra.gps_fmra` |
| 3 | Descargar `google-services.json` | Copiar a `android/app/google-services.json` (no subir a Git) |
| 4 | Confirmar FCM activo | Project settings → Cloud Messaging → API FCM habilitada |
| 5 | Cuenta de servicio JSON | IAM → Service account con rol FCM Admin → Keys → JSON |
| 6 | Secret en Supabase | `FIREBASE_SERVICE_ACCOUNT_JSON` = contenido del JSON |
| 7 | SQL tokens (si falta) | `supabase/migrations/20261102270000_device_push_tokens.sql` → Success |
| 8 | Deploy Edge Function | `npx supabase functions deploy notify-sos` |
| 9 | Rebuild APKs | Tras el JSON: `flutter build apk --debug` → `APK\gps-fmra-debug-01.apk` / `02` |
| 10 | Probar 2 teléfonos | Mismo grupo; B lanza SOS; A recibe push (app en segundo plano) |

**Estado actual del repo:** el código ya está cableado (`PushService` →
`device_push_tokens` → `notify-sos`). Falta en tu PC el archivo
`google-services.json` (aún no está) y los secrets/deploy de Firebase+Supabase.

---

## 1. Proyecto Firebase (consola)

1. Abre [Firebase Console](https://console.firebase.google.com/) → **Add project**
   (o usa uno existente). Nombre sugerido: `GPS-FMRA`.
2. Si pregunta Google Analytics: puedes desactivarlo; no es obligatorio para FCM.
3. En el proyecto → **Add app** → **Android**.
4. **Android package name** (debe coincidir exacto):
   `com.gpsfmra.gps_fmra`
5. Nickname opcional: `GPS-FMRA Android`. **SHA-1 no es obligatorio** solo para FCM SOS.
6. Descarga **`google-services.json`**.
7. Cópialo a:
   `D:\APPS PROYECTOS\GPS-FMRA\android\app\google-services.json`
   (está en `.gitignore`; no lo subas a Git).
8. En Firebase → **Project settings** → **Cloud Messaging**:
   - Confirma que la API FCM esté habilitada (por defecto en proyectos nuevos).
   - Si ves aviso de habilitar **Firebase Cloud Messaging API (V1)** en Google Cloud,
     ábrelo y pulsa **Enable**.

Plantilla de referencia (no sirve sola):  
`android/app/google-services.json.example`

El `build.gradle` de la app **aplica el plugin Google Services solo si**
existe ese archivo; sin él el APK arranca igual (SOS in-app) pero sin push.

## 2. Cuenta de servicio (para la Edge Function)

La función `notify-sos` envía el push con la API HTTP v1 de FCM. Necesita
una cuenta de servicio:

1. En Firebase Console → ⚙ **Project settings** → **Service accounts**
   → **Generate new private key** (o Google Cloud → IAM → Service accounts).
2. Rol recomendado: **Firebase Cloud Messaging API Admin**
   (o “Firebase Admin SDK Administrator Service Agent”).
3. Descarga el JSON (contiene `project_id`, `client_email`, `private_key`).
4. En Supabase Dashboard → **Edge Functions** → **Secrets**, o con CLI
   (proyecto ya linkeado: `npx supabase link`):

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA"
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(Get-Content -Raw '.\ruta\al-servicio.json')"
```

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase en el
runtime de Edge Functions; no hace falta pegarlos a mano en la mayoría de proyectos.

## 3. SQL (SQL Editor)

Si aún no lo aplicaste (ver `supabase/APPLY_ES.md`):

1. `20261102260000_sos_events.sql` (y si hubo 404 antes:
   `20261102261000_sos_events_api_fix.sql`)
2. `20261102270000_device_push_tokens.sql`
   → crea `device_push_tokens` + RPC `list_group_push_tokens`

Éxito esperado: **Success. No rows returned**.

## 4. Desplegar Edge Function `notify-sos`

Código listo en `supabase/functions/notify-sos/`. Desde el repo:

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA"
npx supabase functions deploy notify-sos
```

Flujo ya cableado en la app:

1. Usuario pulsa SOS → se inserta fila en `sos_events`.
2. App llama `functions.invoke('notify-sos', …)`.
3. La función lista tokens del grupo (`device_push_tokens` / RPC) y envía FCM.
4. Cada teléfono, al iniciar sesión con Firebase OK, registra su token con
   `PushService.registerToken` → upsert en `device_push_tokens`.

Si la función no está desplegada o falta el secret, el SOS **igual se guarda**
y el banner in-app funciona; solo falla el push.

## 5. Rebuild APK (obligatorio tras el JSON)

Tras colocar `google-services.json`:

```powershell
cd "D:\APPS PROYECTOS\GPS-FMRA"
flutter pub get
flutter build apk --debug
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" "APK\gps-fmra-debug-01.apk"
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" "APK\gps-fmra-debug-02.apk"
```

Instala **01** y **02** en dos teléfonos. En Android 13+ acepta el permiso
de notificaciones la primera vez que abra la app.

## 6. Probar push

1. Dos teléfonos, mismo grupo, ambos con sesión.
2. Teléfono A: app en segundo plano o pantalla bloqueada.
3. Teléfono B: Mapa → botón rojo **SOS** → confirmar.
4. A debe recibir notificación: **«SOS — GPS-FMRA»** /
   **«¡SOS! {nombre} necesita ayuda.»**
5. Con la app abierta: banner rojo **SOS de {Nombre}** + botón **Aceptar**
   (oculta el banner en ese teléfono; no cancela el SOS del emisor).

### Cómo verificar tokens

En Supabase → Table Editor → `device_push_tokens`: tras abrir la app con
Firebase configurado debe aparecer una fila por usuario/dispositivo.
Si la tabla está vacía, el push no tiene a quién enviar (revisa
`google-services.json` + rebuild + permiso de notificaciones).

## Notas

- No es un chat: solo alerta corta SOS.
- Canal Android: `sos_alerts` (“Alertas SOS”).
- Permiso: `POST_NOTIFICATIONS` ya está en el manifiesto.
- Tokens: RLS solo el dueño escribe/lee su fila; el envío masivo lo hace
  `notify-sos` con service role.
- Documentación relacionada: `supabase/APPLY_ES.md`, `docs/APK_ES.md`,
  `docs/SOS_RETEST_ES.md`.
