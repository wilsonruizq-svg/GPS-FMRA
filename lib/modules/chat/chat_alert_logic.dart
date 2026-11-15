/// Reglas puras para decidir si un mensaje dispara alerta in-app (testable).
class ChatAlertLogic {
  const ChatAlertLogic._();

  static String normId(String? id) => (id ?? '').trim().toLowerCase();

  /// Ignorar mensaje de grupo (sin marcar como «visto» para alerta).
  static bool ignoreGroupMessage({
    required String messageId,
    required String senderId,
    required String myUid,
    required String groupId,
    required DateTime createdAt,
    required DateTime? serviceStartedAt,
    required bool alreadySeen,
    required String? mutedGroupId,
    required int muteGroupDepth,
  }) {
    if (messageId.trim().isEmpty || alreadySeen) return true;
    final sender = normId(senderId);
    final me = normId(myUid);
    if (sender.isEmpty || sender == me) return true;
    if (_tooOld(createdAt, serviceStartedAt)) return true;
    if (muteGroupDepth > 0) {
      final muted = normId(mutedGroupId);
      if (muted.isNotEmpty && normId(groupId) == muted) return true;
    }
    return false;
  }

  static bool ignoreDmMessage({
    required String messageId,
    required String senderId,
    required String recipientId,
    required String myUid,
    required DateTime createdAt,
    required DateTime? serviceStartedAt,
    required bool alreadySeen,
    required String? mutedPeerId,
    required int mutePeerDepth,
  }) {
    if (messageId.trim().isEmpty || alreadySeen) return true;
    final sender = normId(senderId);
    final recipient = normId(recipientId);
    final me = normId(myUid);
    if (sender.isEmpty || sender == me) return true;
    if (recipient != me) return true;
    if (_tooOld(createdAt, serviceStartedAt)) return true;
    if (mutePeerDepth > 0) {
      final muted = normId(mutedPeerId);
      if (muted.isNotEmpty && sender == muted) return true;
    }
    return false;
  }

  static bool _tooOld(DateTime createdAt, DateTime? serviceStartedAt) {
    final started = serviceStartedAt;
    if (started == null) return false;
    return createdAt.isBefore(started.subtract(const Duration(seconds: 2)));
  }

  /// Mensaje entrante que debería sumar al badge (sin mirar ids ya vistos).
  static bool isNewUnreadGroupMessage({
    required String messageId,
    required String senderId,
    required String myUid,
    required String groupId,
    required DateTime createdAt,
    required DateTime? serviceStartedAt,
    required String? mutedGroupId,
    required int muteGroupDepth,
  }) {
    if (messageId.trim().isEmpty) return false;
    if (normId(groupId).isEmpty) return false;
    return !ignoreGroupMessage(
      messageId: messageId,
      senderId: senderId,
      myUid: myUid,
      groupId: groupId,
      createdAt: createdAt,
      serviceStartedAt: serviceStartedAt,
      alreadySeen: false,
      mutedGroupId: mutedGroupId,
      muteGroupDepth: muteGroupDepth,
    );
  }

  static bool isNewUnreadDmMessage({
    required String messageId,
    required String senderId,
    required String recipientId,
    required String myUid,
    required DateTime createdAt,
    required DateTime? serviceStartedAt,
    required String? mutedPeerId,
    required int mutePeerDepth,
  }) {
    if (messageId.trim().isEmpty) return false;
    return !ignoreDmMessage(
      messageId: messageId,
      senderId: senderId,
      recipientId: recipientId,
      myUid: myUid,
      createdAt: createdAt,
      serviceStartedAt: serviceStartedAt,
      alreadySeen: false,
      mutedPeerId: mutedPeerId,
      mutePeerDepth: mutePeerDepth,
    );
  }
}