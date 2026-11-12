import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/supabase/supabase_bootstrap.dart';

/// Handler de isolate para mensajes FCM en background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background: ${message.messageId} type=${message.data['type']}');
}

/// FCM opcional + notificaciones locales (SOS y chat).
/// Sin Firebase el SOS/chat in-app siguen; las locales de chat vía Realtime
/// funcionan si [ensureLocalNotificationsReady] se llamó.
class PushService {
  PushService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  static const androidChannelId = 'sos_alerts';
  static const androidChannelName = 'Alertas SOS';
  static const chatChannelId = 'chat_messages';
  static const chatChannelName = 'Mensajes del grupo';

  static bool _initialized = false;
  static bool _localReady = false;
  static bool ready = false;

  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Notificaciones locales sin depender de FCM.
  Future<void> ensureLocalNotificationsReady() async {
    if (kIsWeb || _localReady) return;
    try {
      await _initLocalNotifications();
      _localReady = true;
    } catch (e) {
      debugPrint('PushService local notifications: $e');
    }
  }

  /// Intenta inicializar Firebase + permisos + registro de token.
  Future<bool> ensureInitialized() async {
    if (_initialized) return ready;
    _initialized = true;

    if (kIsWeb) {
      ready = false;
      return false;
    }

    await ensureLocalNotificationsReady();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final enabled = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!enabled && Platform.isIOS) {
        ready = false;
        return false;
      }

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // ignore: deprecated_member_use
      _tokenRefreshSub = messaging.onTokenRefresh.listen((t) {
        unawaited(registerToken(t));
      });

      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) {
        await registerToken(token);
      }

      ready = true;
      return true;
    } catch (e, st) {
      debugPrint('PushService: FCM no disponible ($e)');
      debugPrint('$st');
      ready = false;
      return false;
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(settings: initSettings);

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: 'Alertas de emergencia del grupo familiar',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        chatChannelId,
        chatChannelName,
        description: 'Mensajes nuevos del chat familiar',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final type = message.data['type'];
    if (type == 'chat') {
      final title = message.notification?.title ?? AppStrings.chatPushTitle;
      final body = message.notification?.body ?? AppStrings.chatPushBodyFallback;
      await showChatLocalNotification(
        id: message.hashCode,
        title: title,
        body: body,
        groupId: message.data['group_id'],
        messageId: message.data['message_id'],
      );
      return;
    }
    if (type != 'sos') return;

    final title = message.notification?.title ?? AppStrings.sosPushTitle;
    final body = message.notification?.body ?? AppStrings.sosPushBodyFallback;

    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          androidChannelName,
          channelDescription: 'Alertas de emergencia del grupo familiar',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      payload: message.data['sos_id'],
    );
  }

  Future<void> showChatLocalNotification({
    required int id,
    required String title,
    required String body,
    String? groupId,
    String? messageId,
  }) async {
    await ensureLocalNotificationsReady();
    if (!_localReady) return;
    await _local.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          chatChannelId,
          chatChannelName,
          channelDescription: 'Mensajes nuevos del chat familiar',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
      ),
      payload: groupId ?? messageId,
    );
  }

  /// Guarda / actualiza el token FCM del usuario autenticado.
  Future<void> registerToken(String token) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || token.isEmpty) return;

    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : 'unknown';

    try {
      await _sb.from('device_push_tokens').upsert({
        'user_id': uid,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');
    } catch (e) {
      debugPrint('PushService.registerToken: $e');
    }
  }

  /// Reintenta registrar el token tras login.
  Future<void> syncTokenAfterLogin() async {
    if (!ready) {
      await ensureInitialized();
    }
    if (!ready) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await registerToken(token);
    } catch (_) {}
  }

  /// Pide a la Edge Function que envíe FCM a los compañeros del SOS.
  Future<void> notifyPeersOfSos({
    required String sosId,
    required String groupId,
    String? displayName,
  }) async {
    try {
      await _sb.functions.invoke(
        'notify-sos',
        body: {
          'sos_id': sosId,
          'group_id': groupId,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
        },
      );
    } catch (e) {
      debugPrint('PushService.notifyPeersOfSos: $e');
    }
  }

  /// Best-effort: push FCM de chat (requiere secret + deploy `notify-chat`).
  Future<void> notifyPeersOfChat({
    required String groupId,
    required String messageId,
    required String senderId,
    required String body,
    String? displayName,
  }) async {
    try {
      await _sb.functions.invoke(
        'notify-chat',
        body: {
          'group_id': groupId,
          'message_id': messageId,
          'sender_id': senderId,
          'body': body,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
        },
      );
    } catch (e) {
      debugPrint('PushService.notifyPeersOfChat: $e');
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
  }
}
