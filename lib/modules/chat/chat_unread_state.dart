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