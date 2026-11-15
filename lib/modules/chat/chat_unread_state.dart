import 'chat_alert_logic.dart';

/// Contadores por hilo (grupo / peer DM). Lógica pura para tests.
class ChatUnreadCounters {
  const ChatUnreadCounters._();

  static int bump(Map<String, int> perThread, String threadId) {
    final k = ChatAlertLogic.normId(threadId);
    if (k.isEmpty) return 0;
    final next = (perThread[k] ?? 0) + 1;
    perThread[k] = next;
    return next;
  }

  static int countFor(Map<String, int> perThread, String threadId) {
    return perThread[ChatAlertLogic.normId(threadId)] ?? 0;
  }

  static void clearThread(Map<String, int> perThread, String threadId) {
    perThread.remove(ChatAlertLogic.normId(threadId));
  }

  static void decrement(Map<String, int> perThread, String threadId) {
    final k = ChatAlertLogic.normId(threadId);
    final cur = perThread[k];
    if (cur == null || cur <= 0) return;
    if (cur <= 1) {
      perThread.remove(k);
    } else {
      perThread[k] = cur - 1;
    }
  }

  static int total(Iterable<Map<String, int>> maps) {
    var sum = 0;
    for (final m in maps) {
      for (final v in m.values) {
        sum += v;
      }
    }
    return sum;
  }
}