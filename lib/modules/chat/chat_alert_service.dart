import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../push/push_service.dart';
import 'chat_service.dart';

/// Escucha Realtime de `group_messages` y avisa con notificación local
/// (y snackbar) cuando llega un mensaje de otro integrante y no estás
/// viendo ese chat.
class ChatAlertService {
  ChatAlertService._();
  static final ChatAlertService instance = ChatAlertService._();

  final _chat = ChatService();
  final _push = PushService();

  RealtimeChannel? _channel;
  bool _started = false;
  String? mutedGroupId;
  final Set<String> _seenIds = {};

  String get _myUid =>
      (supabase.auth.currentUser?.id ?? '').trim().toLowerCase();

  /// Silencia alertas del grupo cuyo chat está abierto.
  void muteGroup(String? groupId) {
    mutedGroupId = groupId?.trim();
  }

  Future<void> start() async {
    if (_started) return;
    if (supabase.auth.currentUser == null) return;

    await _push.ensureLocalNotificationsReady();

    _channel = supabase.channel(
      'group_messages_alerts_${DateTime.now().millisecondsSinceEpoch}',
    );
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          callback: (payload) {
            unawaited(_onInsert(payload.newRecord));
          },
        )
        .subscribe();

    _started = true;
  }

  Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    _started = false;
    mutedGroupId = null;
    if (ch != null) {
      await _chat.unsubscribe(ch);
    }
  }

  Future<void> _onInsert(Map<String, dynamic> raw) async {
    try {
      var msg = GroupMessage.fromMap(Map<String, dynamic>.from(raw));
      final id = msg.id.trim();
      if (id.isEmpty || _seenIds.contains(id)) return;
      _seenIds.add(id);
      if (_seenIds.length > 300) {
        _seenIds.remove(_seenIds.first);
      }

      final sender = msg.senderId.trim().toLowerCase();
      if (sender.isEmpty || sender == _myUid) return;

      final muted = mutedGroupId?.trim();
      if (muted != null &&
          muted.isNotEmpty &&
          msg.groupId.trim() == muted) {
        return;
      }

      msg = await _chat.enrich(msg);
      final title = AppStrings.chatPushTitle;
      final body = AppStrings.chatPushBody(msg.senderLabel, msg.body);

      await _push.showChatLocalNotification(
        id: id.hashCode,
        title: title,
        body: body,
        groupId: msg.groupId,
        messageId: id,
      );

      final messenger = GpsFmraApp.messengerKey.currentState;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('$title: ${msg.senderLabel} — ${msg.body}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('ChatAlertService._onInsert: $e');
    }
  }
}
