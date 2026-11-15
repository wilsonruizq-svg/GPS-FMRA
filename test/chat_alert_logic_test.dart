import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/chat/chat_alert_logic.dart';

void main() {
  final started = DateTime.utc(2026, 6, 1, 12, 0, 0);

  group('ChatAlertLogic.ignoreGroupMessage', () {
    test('ignora mensaje propio', () {
      expect(
        ChatAlertLogic.ignoreGroupMessage(
          messageId: 'm1',
          senderId: 'USER-A',
          myUid: 'user-a',
          groupId: 'g1',
          createdAt: started,
          serviceStartedAt: started,
          alreadySeen: false,
          mutedGroupId: null,
          muteGroupDepth: 0,
        ),
        isTrue,
      );
    });

    test('alerta mensaje ajeno si no mute', () {
      expect(
        ChatAlertLogic.ignoreGroupMessage(
          messageId: 'm1',
          senderId: 'user-b',
          myUid: 'user-a',
          groupId: 'g1',
          createdAt: started,
          serviceStartedAt: started,
          alreadySeen: false,
          mutedGroupId: null,
          muteGroupDepth: 0,
        ),
        isFalse,
      );
    });

    test('mute por grupo (case insensitive)', () {
      expect(
        ChatAlertLogic.ignoreGroupMessage(
          messageId: 'm1',
          senderId: 'user-b',
          myUid: 'user-a',
          groupId: 'G1',
          createdAt: started,
          serviceStartedAt: started,
          alreadySeen: false,
          mutedGroupId: 'g1',
          muteGroupDepth: 1,
        ),
        isTrue,
      );
    });
  });

  group('ChatAlertLogic.isNewUnreadGroupMessage', () {
    test('cuenta mensaje ajeno nuevo', () {
      expect(
        ChatAlertLogic.isNewUnreadGroupMessage(
          messageId: 'm2',
          senderId: 'user-b',
          myUid: 'user-a',
          groupId: 'g1',
          createdAt: started,
          serviceStartedAt: started,
          mutedGroupId: null,
          muteGroupDepth: 0,
        ),
        isTrue,
      );
    });
  });

  group('ChatAlertLogic.ignoreDmMessage', () {
    test('solo destinatario recibe alerta', () {
      expect(
        ChatAlertLogic.ignoreDmMessage(
          messageId: 'd1',
          senderId: 'user-b',
          recipientId: 'user-a',
          myUid: 'user-a',
          createdAt: started,
          serviceStartedAt: started,
          alreadySeen: false,
          mutedPeerId: null,
          mutePeerDepth: 0,
        ),
        isFalse,
      );
      expect(
        ChatAlertLogic.ignoreDmMessage(
          messageId: 'd1',
          senderId: 'user-b',
          recipientId: 'user-c',
          myUid: 'user-a',
          createdAt: started,
          serviceStartedAt: started,
          alreadySeen: false,
          mutedPeerId: null,
          mutePeerDepth: 0,
        ),
        isTrue,
      );
    });
  });
}