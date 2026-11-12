import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../groups/groups_service.dart';
import '../push/push_service.dart';
import 'chat_service.dart';

/// Alertas de chat app-wide (Mapa incluido): Realtime + polling de respaldo.
class ChatAlertService {
  ChatAlertService._();
  static final ChatAlertService instance = ChatAlertService._();

  final _chat = ChatService();
  final _groups = GroupsService();
  final _push = PushService();

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _running = false;
  int _muteDepth = 0;
  String? mutedGroupId;
  final Set<String> _seenIds = {};
  DateTime? _startedAt;

  String get _myUid =>
      (supabase.auth.currentUser?.id ?? '').trim().toLowerCase();

  /// Silencia un grupo mientras su pantalla de chat está abierta (refcount).
  void muteGroup(String? groupId) {
    final id = groupId?.trim();
    if (id == null || id.isEmpty) {
      if (_muteDepth > 0) _muteDepth -= 1;
      if (_muteDepth <= 0) {
        _muteDepth = 0;
        mutedGroupId = null;
      }
      return;
    }
    mutedGroupId = id;
    _muteDepth += 1;
  }

  Future<void> start() async {
    if (_running) return;
    if (supabase.auth.currentUser == null) {
      debugPrint('ChatAlertService: sin sesión, no arranca');
      return;
    }
    _running = true;
    _startedAt = DateTime.now().toUtc();

    try {
      await Permission.notification.request();
    } catch (e) {
      debugPrint('ChatAlertService: permission $e');
    }
    await _push.ensureLocalNotificationsReady();

    // Seed: no alertar historial viejo.
    try {
      await _seedSeenFromRecent();
    } catch (e) {
      debugPrint('ChatAlertService seed: $e');
    }

    _subscribeRealtime();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_pollRecent());
    });
    // Primer poll pronto por si Realtime no está en la publication.
    unawaited(_pollRecent());
    debugPrint('ChatAlertService: started (realtime+poll)');
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final ch = _channel;
    _channel = null;
    _running = false;
    _muteDepth = 0;
    mutedGroupId = null;
    if (ch != null) {
      try {
        await _chat.unsubscribe(ch);
      } catch (_) {}
    }
  }

  /// Reinicia suscripción (p. ej. al volver al Mapa).
  Future<void> ensureRunning() async {
    if (!_running) {
      await start();
      return;
    }
    if (_channel == null) {
      _subscribeRealtime();
    }
  }

  void _subscribeRealtime() {
    unawaited(_chat.unsubscribe(_channel));
    _channel = supabase.channel(
      'group_messages_alerts_${DateTime.now().millisecondsSinceEpoch}',
    );
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          callback: (payload) {
            debugPrint('ChatAlertService: realtime insert');
            unawaited(_handleRaw(payload.newRecord, source: 'realtime'));
          },
        )
        .subscribe((status, err) {
          debugPrint('ChatAlertService: realtime status=$status err=$err');
        });
  }

  Future<void> _seedSeenFromRecent() async {
    final groups = await _groups.listMyGroups();
    for (final g in groups) {
      final list = await _chat.listRecent(groupId: g.id, limit: 40);
      for (final m in list) {
        final id = m.id.trim();
        if (id.isNotEmpty) _seenIds.add(id);
      }
    }
  }

  Future<void> _pollRecent() async {
    if (!_running || supabase.auth.currentUser == null) return;
    try {
      final groups = await _groups.listMyGroups();
      for (final g in groups) {
        final list = await _chat.listRecent(groupId: g.id, limit: 15);
        for (final m in list) {
          await _maybeAlert(m, source: 'poll');
        }
      }
    } catch (e) {
      debugPrint('ChatAlertService poll: $e');
    }
  }

  Future<void> _handleRaw(
    Map<String, dynamic> raw, {
    required String source,
  }) async {
    try {
      final msg = GroupMessage.fromMap(Map<String, dynamic>.from(raw));
      await _maybeAlert(msg, source: source);
    } catch (e) {
      debugPrint('ChatAlertService parse ($source): $e raw=$raw');
    }
  }

  Future<void> _maybeAlert(GroupMessage msg, {required String source}) async {
    final id = msg.id.trim();
    if (id.isEmpty) return;
    if (_seenIds.contains(id)) return;
    _seenIds.add(id);
    if (_seenIds.length > 400) {
      _seenIds.remove(_seenIds.first);
    }

    final sender = msg.senderId.trim().toLowerCase();
    if (sender.isEmpty || sender == _myUid) return;

    // Ignorar mensajes anteriores al arranque del servicio (seed incompleto).
    final started = _startedAt;
    if (started != null && msg.createdAt.isBefore(started.subtract(const Duration(seconds: 2)))) {
      return;
    }

    final muted = mutedGroupId?.trim();
    if (_muteDepth > 0 &&
        muted != null &&
        muted.isNotEmpty &&
        msg.groupId.trim() == muted) {
      debugPrint('ChatAlertService: muted group $muted ($source)');
      return;
    }

    var enriched = msg;
    try {
      enriched = await _chat.enrich(msg);
    } catch (_) {}

    final title = AppStrings.chatPushTitle;
    final body = AppStrings.chatPushBody(enriched.senderLabel, enriched.body);
    debugPrint('ChatAlertService: ALERT $source → $body');

    await _push.showChatLocalNotification(
      id: id.hashCode & 0x7fffffff,
      title: title,
      body: body,
      groupId: enriched.groupId,
      messageId: id,
    );

    final messenger = GpsFmraApp.messengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${enriched.senderLabel}: ${enriched.body}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: AppStrings.chatAction,
            onPressed: () {},
          ),
        ),
      );
    } else {
      debugPrint('ChatAlertService: messengerKey null (snackbar skipped)');
    }
  }
}
