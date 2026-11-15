import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../groups/groups_service.dart';
import '../push/push_service.dart';
import 'chat_alert_logic.dart';
import 'chat_service.dart';
import 'chat_unread_state.dart';
import 'dm_service.dart';

/// Alertas app-wide: chat de grupo + DM 1:1 (Realtime + polling).
class ChatAlertService extends ChangeNotifier {
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
  final Set<String> _unreadCountedIds = {};
  final Map<String, int> _unreadByGroup = {};
  final Map<String, int> _unreadByDmPeer = {};
  DateTime? _startedAt;

  int get totalUnread => ChatUnreadCounters.total([
        _unreadByGroup,
        _unreadByDmPeer,
      ]);

  int unreadCountForGroup(String groupId) =>
      ChatUnreadCounters.countFor(_unreadByGroup, groupId);

  int unreadCountForDmPeer(String peerUserId) =>
      ChatUnreadCounters.countFor(_unreadByDmPeer, peerUserId);

  void clearGroupUnread(String groupId) {
    ChatUnreadCounters.clearThread(_unreadByGroup, groupId);
    notifyListeners();
  }

  void clearDmUnread(String peerUserId) {
    ChatUnreadCounters.clearThread(_unreadByDmPeer, peerUserId);
    notifyListeners();
  }

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
    mutedGroupId = ChatAlertLogic.normId(id);
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
    mutedPeerId = ChatAlertLogic.normId(id);
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

    unawaited(_subscribeRealtime());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_pollRecent());
    });
    unawaited(_pollRecent());
    debugPrint('ChatAlertService: started (group+dm)');
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
    _unreadByGroup.clear();
    _unreadByDmPeer.clear();
    _unreadCountedIds.clear();
    notifyListeners();
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
      await _subscribeRealtime();
    }
    unawaited(_pollRecent());
  }

  /// Tras volver de background o cambiar pestaña (reconecta Realtime + poll).
  Future<void> onForeground() async {
    await ensureRunning();
  }

  Future<void> _subscribeRealtime() async {
    final prevG = _groupChannel;
    final prevD = _dmChannel;
    _groupChannel = null;
    _dmChannel = null;
    await _chat.unsubscribe(prevG);
    await _dm.unsubscribe(prevD);

    _groupChannel = supabase.channel(
      'group_messages_alerts_${DateTime.now().millisecondsSinceEpoch}',
    );
    _groupChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          callback: (payload) {
            unawaited(_handleGroupRaw(payload.newRecord, source: 'rt-group'));
          },
        )
        .subscribe((status, err) {
          debugPrint('ChatAlertService group rt=$status err=$err');
        });

    _dmChannel = _dm.subscribeMine(
      onInsert: (msg) {
        unawaited(_maybeAlertDm(msg, source: 'rt-dm'));
      },
      onStatus: (status, err) {
        debugPrint('ChatAlertService dm rt=$status err=$err');
      },
    );
  }

  Future<void> _seedSeenFromRecent() async {
    final groups = await _groups.listMyGroups();
    for (final g in groups) {
      final list = await _chat.listRecent(groupId: g.id, limit: 40);
      for (final m in list) {
        final id = m.id.trim();
        if (id.isNotEmpty) {
          _seenIds.add(id);
          _unreadCountedIds.add(id);
        }
      }
    }
    try {
      final dms = await _dm.listMyRecent(limit: 40);
      for (final m in dms) {
        final id = m.id.trim();
        if (id.isNotEmpty) {
          _seenIds.add(id);
          _unreadCountedIds.add(id);
        }
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
  }) async {
    try {
      final msg = GroupMessage.fromMap(Map<String, dynamic>.from(raw));
      await _maybeAlertGroup(msg, source: source);
    } catch (e) {
      debugPrint('ChatAlertService parse group ($source): $e');
    }
  }

  void _recordSeen(String id) {
    if (id.isEmpty) return;
    _seenIds.add(id);
    if (_seenIds.length > 400) {
      _seenIds.remove(_seenIds.first);
    }
  }

  void _bumpUnreadOnce(
    String messageId, {
    required String threadId,
    required bool dm,
    required String source,
  }) {
    final mid = messageId.trim();
    if (mid.isEmpty || _unreadCountedIds.contains(mid)) return;
    _unreadCountedIds.add(mid);
    if (dm) {
      ChatUnreadCounters.bump(_unreadByDmPeer, threadId);
    } else {
      ChatUnreadCounters.bump(_unreadByGroup, threadId);
    }
    debugPrint(
      'ChatAlertService: unread +1 ${dm ? "dm" : "group"}='
      '${ChatAlertLogic.normId(threadId)} total=$totalUnread src=$source',
    );
    notifyListeners();
  }

  void _trackUnreadGroup(GroupMessage msg, {required String source}) {
    final id = msg.id.trim();
    if (id.isEmpty || _unreadCountedIds.contains(id)) {
      return;
    }
    if (!ChatAlertLogic.isNewUnreadGroupMessage(
      messageId: id,
      senderId: msg.senderId,
      myUid: _myUid,
      groupId: msg.groupId,
      createdAt: msg.createdAt,
      serviceStartedAt: _startedAt,
      mutedGroupId: mutedGroupId,
      muteGroupDepth: _muteGroupDepth,
    )) {
      return;
    }
    _bumpUnreadOnce(id, threadId: msg.groupId, dm: false, source: source);
  }

  void _trackUnreadDm(DirectMessage msg, {required String source}) {
    final id = msg.id.trim();
    if (id.isEmpty || _unreadCountedIds.contains(id)) {
      return;
    }
    if (!ChatAlertLogic.isNewUnreadDmMessage(
      messageId: id,
      senderId: msg.senderId,
      recipientId: msg.recipientId,
      myUid: _myUid,
      createdAt: msg.createdAt,
      serviceStartedAt: _startedAt,
      mutedPeerId: mutedPeerId,
      mutePeerDepth: _mutePeerDepth,
    )) {
      return;
    }
    _bumpUnreadOnce(id, threadId: msg.senderId, dm: true, source: source);
  }

  Future<void> _maybeAlertGroup(
    GroupMessage msg, {
    required String source,
  }) async {
    final id = msg.id.trim();
    // Badge in-app: siempre antes de notif/snackbar (no depende de delivered).
    _trackUnreadGroup(msg, source: source);

    if (ChatAlertLogic.ignoreGroupMessage(
      messageId: id,
      senderId: msg.senderId,
      myUid: _myUid,
      groupId: msg.groupId,
      createdAt: msg.createdAt,
      serviceStartedAt: _startedAt,
      alreadySeen: _seenIds.contains(id),
      mutedGroupId: mutedGroupId,
      muteGroupDepth: _muteGroupDepth,
    )) {
      if (id.isNotEmpty &&
          !_unreadCountedIds.contains(id) &&
          !ChatAlertLogic.isNewUnreadGroupMessage(
            messageId: id,
            senderId: msg.senderId,
            myUid: _myUid,
            groupId: msg.groupId,
            createdAt: msg.createdAt,
            serviceStartedAt: _startedAt,
            mutedGroupId: mutedGroupId,
            muteGroupDepth: _muteGroupDepth,
          )) {
        _recordSeen(id);
      }
      return;
    }

    var enriched = msg;
    try {
      enriched = await _chat.enrich(msg);
    } catch (_) {}

    final delivered = await _showAlert(
      title: AppStrings.chatPushTitle,
      body: AppStrings.chatPushBody(enriched.senderLabel, enriched.body),
      notifId: id.hashCode & 0x7fffffff,
      payload: enriched.groupId,
      source: source,
    );
    if (delivered) {
      _recordSeen(id);
    } else if (id.isNotEmpty) {
      debugPrint('ChatAlertService: alert undelivered msg=$id (unread=$totalUnread)');
    }
  }

  Future<void> _maybeAlertDm(
    DirectMessage msg, {
    required String source,
  }) async {
    final id = msg.id.trim();
    _trackUnreadDm(msg, source: source);

    if (ChatAlertLogic.ignoreDmMessage(
      messageId: id,
      senderId: msg.senderId,
      recipientId: msg.recipientId,
      myUid: _myUid,
      createdAt: msg.createdAt,
      serviceStartedAt: _startedAt,
      alreadySeen: _seenIds.contains(id),
      mutedPeerId: mutedPeerId,
      mutePeerDepth: _mutePeerDepth,
    )) {
      if (id.isNotEmpty &&
          !_unreadCountedIds.contains(id) &&
          !ChatAlertLogic.isNewUnreadDmMessage(
            messageId: id,
            senderId: msg.senderId,
            recipientId: msg.recipientId,
            myUid: _myUid,
            createdAt: msg.createdAt,
            serviceStartedAt: _startedAt,
            mutedPeerId: mutedPeerId,
            mutePeerDepth: _mutePeerDepth,
          )) {
        _recordSeen(id);
      }
      return;
    }

    var enriched = msg;
    try {
      enriched = await _dm.enrich(msg);
    } catch (_) {}

    final delivered = await _showAlert(
      title: AppStrings.dmPushTitle,
      body: AppStrings.chatPushBody(enriched.senderLabel, enriched.body),
      notifId: id.hashCode & 0x7fffffff,
      payload: ChatAlertLogic.normId(msg.senderId),
      source: source,
    );
    if (delivered) {
      _recordSeen(id);
    }
  }

  Future<bool> _showAlert({
    required String title,
    required String body,
    required int notifId,
    required String? payload,
    required String source,
  }) async {
    debugPrint('ChatAlertService: ALERT $source → $body');
    final notifOk = await _push.showChatLocalNotification(
      id: notifId,
      title: title,
      body: body,
      groupId: payload,
      messageId: '$notifId',
    );

    var snackOk = false;
    final messenger = GpsFmraApp.messengerKey.currentState;
    if (messenger != null) {
      snackOk = true;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(body),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      debugPrint('ChatAlertService: messenger null (¿sin scaffoldMessenger?)');
    }
    return notifOk || snackOk;
  }
}
