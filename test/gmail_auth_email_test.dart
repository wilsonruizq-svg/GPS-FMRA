import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/auth/gmail_auth_email.dart';

void main() {
  group('GmailAuthEmail.normalize', () {
    test('googlemail → gmail', () {
      expect(
        GmailAuthEmail.normalize('Usuario@Googlemail.com'),
        'usuario@gmail.com',
      );
    });

    test('gmail sin cambios de dominio', () {
      expect(
        GmailAuthEmail.normalize('  wilsonruizq@gmail.com  '),
        'wilsonruizq@gmail.com',
      );
    });
  });

  group('GmailAuthEmail.validateForNewAccount', () {
    test('acepta gmail y googlemail', () {
      expect(GmailAuthEmail.validateForNewAccount('a@gmail.com'), isNull);
      expect(
        GmailAuthEmail.validateForNewAccount('b@googlemail.com'),
        isNull,
      );
    });

    test('rechaza otros dominios', () {
      expect(
        GmailAuthEmail.validateForNewAccount('x@hotmail.com'),
        isNotNull,
      );
    });
  });
}