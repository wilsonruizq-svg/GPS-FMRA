import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/groups/exit_pin_service.dart';

void main() {
  group('ExitPinService.isValidPinFormat', () {
    test('acepta 4 a 8 dígitos', () {
      expect(ExitPinService.isValidPinFormat('1234'), isTrue);
      expect(ExitPinService.isValidPinFormat('12345678'), isTrue);
      expect(ExitPinService.isValidPinFormat(' 98765 '), isTrue);
    });

    test('rechaza formatos inválidos', () {
      expect(ExitPinService.isValidPinFormat(''), isFalse);
      expect(ExitPinService.isValidPinFormat('123'), isFalse);
      expect(ExitPinService.isValidPinFormat('123456789'), isFalse);
      expect(ExitPinService.isValidPinFormat('12ab'), isFalse);
      expect(ExitPinService.isValidPinFormat('12 34'), isFalse);
    });
  });
}
