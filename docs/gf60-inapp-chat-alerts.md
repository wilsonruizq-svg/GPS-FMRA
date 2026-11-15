# GF-60 — Alertas in-app de chat (Wilson)

**Rama:** `cursor/gf60-inapp-chat-alerts` (desde `cursor/gf59-google-sign-in-35af`)

## Qué se arregló

| Área | Cambio |
|------|--------|
| `ChatAlertService` | Filtros en `ChatAlertLogic`; no marca “visto” hasta snackbar o notif local; reintento en poll si falla el envío |
| Realtime | Desuscribe antes de resuscribir; log de estado DM; `ensureRunning()` dispara poll |
| Pestañas | `ensureRunning()` en **Mapa, Grupos y Ajustes** (antes solo Mapa) |
| Ciclo de vida | `AppShell` observa `resumed` → `onForeground()` |
| Mute | IDs de grupo/peer normalizados (`trim` + `lowerCase`) |
| Canal Android | Sin cambio de ID: `chat_messages` en `PushService` |
| FCM login | `syncTokenAfterLogin` reintenta si el primer `ensureInitialized` falló |

## Prueba mínima (2 usuarios)

1. B en **Grupos** o **Ajustes** (no dentro del chat del mismo grupo).
2. A envía mensaje de grupo.
3. En ≤6 s: snackbar flotante + notificación canal **Mensajes del grupo**; logcat: `ChatAlertService: ALERT rt-group` o `poll-group`.
4. B abre el chat del grupo → sin alertas duplicadas (mute).
5. B vuelve al mapa y recibe otro mensaje → alerta de nuevo.

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s 1627132010HA08SZ logcat -s flutter:I | Select-String "ChatAlert|ALERT"
```

## Tests automáticos

```powershell
flutter test test/chat_alert_logic_test.dart
```

Relacionado: `docs/gf58-notifications-diagnosis.md` (push background / FCM sigue en checklist Supabase).