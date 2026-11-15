import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/push/push_service.dart';

void main() {
  test('canal chat v2 para sonido en OEMs que silenciaron v1', () {
    expect(PushService.chatChannelId, 'chat_messages_v2');
  });
}