import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/auth/auth_email.dart';

void main() {
  group('AuthEmail.normalize', () {
    test('googlemail → gmail', () {
      expect(
        AuthEmail.normalize('Usuario@Googlemail.com'),
        'usuario@gmail.com',
      );
    });

    test('trim y minúsculas', () {
      expect(
        AuthEmail.normalize('  User@Example.COM  '),
        'user@example.com',
      );
    });
  });

  group('AuthEmail.validateForNewAccount', () {
    test('acepta correos habituales', () {
      expect(AuthEmail.validateForNewAccount('a@gmail.com'), isNull);
      expect(AuthEmail.validateForNewAccount('x@hotmail.com'), isNull);
      expect(AuthEmail.validateForNewAccount('b@empresa.co'), isNull);
    });

    test('rechaza formato inválido', () {
      expect(AuthEmail.validateForNewAccount(''), isNotNull);
      expect(AuthEmail.validateForNewAccount('sinarroba'), isNotNull);
      expect(AuthEmail.validateForNewAccount('@dominio.com'), isNotNull);
    });
  });
}