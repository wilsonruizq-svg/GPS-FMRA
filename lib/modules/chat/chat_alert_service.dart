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
import 'dm_service.dart';

/// Alertas app-wide: chat de grupo + DM 1:1 (Realtime + polling).
class ChatAlertService {
  ChatAlertService._();
  static final ChatAlertService instance = ChatAlertService._();

  final _chat = ChatService();
  final _dm = DmService();
  final _groups = GroupsService();
  final _push = PushService();

  RealtimeChannel? _groupChannel;
  RealtimeChannel? _dmChannel;
  Timer? _pollTimer;
  bool _running = false;
  int _muteGroupDepth = 0;
  int _mutePeerDepth = 0;
  String? mutedGroupId;
  String? mutedPeerId;
  final Set<String> _seenIds = {};
  DateTime? _startedAt;

  String get _myUid =>
      (supabase.auth.currentUser?.id ?? '').trim().toLowerCase();

  void muteGroup(String? groupId) {
    final id = groupId?.trim();
    if (id == null || id.isEmpty) {
      if (_muteGroupDepth > 0) _muteGroupDepth -= 1;
      if (_muteGroupDepth <= 0) {
        _muteGroupDepth = 0;
        mutedGroupId = null;
      }
      return;
    }
    mutedGroupId = id;
    _muteGroupDepth += 1;
  }

  void mutePeer(String? peerUserId) {
    final id = peerUserId?.trim();
    if (id == null || id.isEmpty) {
      if (_mutePeerDepth > 0) _mutePeerDepth -= 1;
      if (_mutePeerDepth <= 0) {
        _mutePeerDepth = 0;
        mutedPeerId = null;
      }
      return;
    }
    mutedPeerId = id;
    _mutePeerDepth += 1;
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

    try {
      await _seedSeenFromRecent();
    } catch (e) {
      debugPrint('ChatAlertService seed: $e');
    }

    _subscribeRealtime();
    _pollTimer?.cancel();
    // Fallback corto: Realtime es lo principal; poll ~2s si Realtime falla.
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollRecent());
    });
    unawaited(_pollRecent());
    debugPrint('ChatAlertService: started (group+dm, poll=2s)');
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final g = _groupChannel;
    final d = _dmChannel;
    _groupChannel = null;
    _dmChannel = null;
    _running = false;
    _muteGroupDepth = 0;
    _mutePeerDepth = 0;
    mutedGroupId = null;
    mutedPeerId = null;
    if (g != null) {
      try {
        await _chat.unsubscribe(g);
      } catch (_) {}
    }
    if (d != null) {
      try {
        await _dm.unsubscribe(d);
      } catch (_) {}
    }
  }

  Future<void> ensureRunning() async {
    if (!_running) {
      await start();
      return;
    }
    if (_groupChannel == null || _dmChannel == null) {
      _subscribeRealtime();
    }
  }

  void _subscribeRealtime() {
    unawaited(_chat.unsubscribe(_groupChannel));
    unawaited(_dm.unsubscribe(_dmChannel));

    _groupChannel = supabase.channel(
      'group_messages_alerts_${DateTime.now().millisecondsSinceEpoch}',
    );
    _groupChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          callback: (payload) {
            unawaited(
              _handleGroupRaw(
                payload.newRecord,
                source: 'rt-group',
                enrichNames: false,
              ),
            );
          },
        )
        .subscribe((status, err) {
          debugPrint('ChatAlertService group rt=$status err=$err');
        });

    _dmChannel = _dm.subscribeMine(
      onInsert: (msg) {
        // Sin enrich en Realtime: alerta inmediata.
        unawaited(_maybeAlertDm(msg, source: 'rt-dm', enrichNames: false));
      },
    );
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
    try {
      final dms = await _dm.listMyRecent(limit: 40);
      for (final m in dms) {
        final id = m.id.trim();
        if (id.isNotEmpty) _seenIds.add(id);
      }
    } catch (e) {
      debugPrint('ChatAlertService seed dm: $e');
    }
  }

  Future<void> _pollRecent() async {
    if (!_running || supabase.auth.currentUser == null) return;
    try {
      final groups = await _groups.listMyGroups();
      for (final g in groups) {
        final list = await _chat.listRecent(groupId: g.id, limit: 15);
        for (final m in list) {
          await _maybeAlertGroup(m, source: 'poll-group');
        }
      }
    } catch (e) {
      debugPrint('ChatAlertService poll group: $e');
    }
    try {
      final dms = await _dm.listMyRecent(limit: 20);
      for (final m in dms) {
        await _maybeAlertDm(m, source: 'poll-dm');
      }
    } catch (e) {
      debugPrint('ChatAlertService poll dm: $e');
    }
  }

  Future<void> _handleGroupRaw(
    Map<String, dynamic> raw, {
    required String source,
    bool enrichNames = true,
  }) async {
    try {
      final msg = GroupMessage.fromMap(Map<String, dynamic>.from(raw));
      await _maybeAlertGroup(
        msg,
        source: source,
        enrichNames: enrichNames,
      );
    } catch (e) {
      debugPrint('ChatAlertService parse group ($source): $e');
    }
  }

  bool _markSeen(String id) {
    if (id.isEmpty || _seenIds.contains(id)) return false;
    _seenIds.add(id);
    if (_seenIds.length > 400) {
      _seenIds.remove(_seenIds.first);
    }
    return true;
  }

  bool _tooOld(DateTime createdAt) {
    final started = _startedAt;
    if (started == null) return false;
    return createdAt.isBefore(started.subtract(const Duration(seconds: 2)));
  }

  Future<void> _maybeAlertGroup(
    GroupMessage msg, {
    required String source,
    bool enrichNames = true,
  }) async {
    final id = msg.id.trim();
    if (!_markSeen(id)) return;

    final sender = msg.senderId.trim().toLowerCase();
    if (sender.isEmpty || sender == _myUid) return;
    if (_tooOld(msg.createdAt)) return;

    final muted = mutedGroupId?.trim();
    if (_muteGroupDepth > 0 &&
        muted != null &&
        muted.isNotEmpty &&
        msg.groupId.trim() == muted) {
      return;
    }

    var enriched = msg;
    if (enrichNames) {
      try {
        enriched = await _chat.enrich(msg).timeout(const Duration(milliseconds: 400));
      } catch (_) {}
    }

    await _showAlert(
      title: AppStrings.chatPushTitle,
      body: AppStrings.chatPushBody(enriched.senderLabel, enriched.body),
      notifId: id.hashCode & 0x7fffffff,
      payload: enriched.groupId,
      source: source,
    );
  }

  Future<void> _maybeAlertDm(
    DirectMessage msg, {
    required String source,
    bool enrichNames = true,
  }) async {
    final id = msg.id.trim();
    if (!_markSeen(id)) return;

    final sender = msg.senderId.trim().toLowerCase();
    final recipient = msg.recipientId.trim().toLowerCase();
    if (sender.isEmpty || sender == _myUid) return;
    // Solo alertar si soy el destinatario.
    if (recipient != _myUid) return;
    if (_tooOld(msg.createdAt)) return;

    final muted = mutedPeerId?.trim().toLowerCase();
    if (_mutePeerDepth > 0 &&
        muted != null &&
        muted.isNotEmpty &&
        sender == muted) {
      return;
    }

    var enriched = msg;
    if (enrichNames) {
      try {
        enriched = await _dm.enrich(msg).timeout(const Duration(milliseconds: 400));
      } catch (_) {}
    }

    await _showAlert(
      title: AppStrings.dmPushTitle,
      body: AppStrings.chatPushBody(enriched.senderLabel, enriched.body),
      notifId: id.hashCode & 0x7fffffff,
      payload: sender,
      source: source,
    );
  }

  Future<void> _showAlert({
    required String title,
    required String body,
    required int notifId,
    required String? payload,
    required String source,
  }) async {
    debugPrint('ChatAlertService: ALERT $source → $body');
    await _push.showChatLocalNotification(
      id: notifId,
      title: title,
      body: body,
      groupId: payload,
      messageId: '$notifId',
    );

    final messenger = GpsFmraApp.messengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(body),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
