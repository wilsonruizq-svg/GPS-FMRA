import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/chat/chat_unread_state.dart';

void main() {
  test('bump y total por grupo', () {
    final groups = <String, int>{};
    expect(ChatUnreadCounters.bump(groups, 'G1'), 1);
    expect(ChatUnreadCounters.bump(groups, 'g1'), 2);
    expect(ChatUnreadCounters.countFor(groups, 'G1'), 2);
    expect(ChatUnreadCounters.total([groups]), 2);
  });

  test('clearThread y DM separado', () {
    final groups = <String, int>{'a': 3};
    final dms = <String, int>{'peer': 1};
    ChatUnreadCounters.clearThread(groups, 'A');
    expect(ChatUnreadCounters.total([groups, dms]), 1);
  });
}