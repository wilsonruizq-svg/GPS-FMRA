import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/profiles/profile_validation.dart';

void main() {
  group('ProfileValidation.validateDisplayName', () {
    test('rechaza vacío o solo espacios', () {
      expect(ProfileValidation.validateDisplayName(null), isNotNull);
      expect(ProfileValidation.validateDisplayName(''), isNotNull);
      expect(ProfileValidation.validateDisplayName('   '), isNotNull);
    });

    test('rechaza demasiado corto', () {
      expect(ProfileValidation.validateDisplayName('A'), isNotNull);
    });

    test('acepta nombre válido', () {
      expect(ProfileValidation.validateDisplayName('Wilson'), isNull);
      expect(ProfileValidation.validateDisplayName('  Wilson Ruiz  '), isNull);
    });

    test('rechaza demasiado largo', () {
      final long = 'x' * (ProfileValidation.displayNameMax + 1);
      expect(ProfileValidation.validateDisplayName(long), isNotNull);
    });
  });

  group('ProfileValidation.normalizePhone', () {
    test('vacío → null', () {
      expect(ProfileValidation.normalizePhone(null), isNull);
      expect(ProfileValidation.normalizePhone(''), isNull);
      expect(ProfileValidation.normalizePhone('  '), isNull);
    });

    test('acepta teléfono con formato', () {
      expect(
        ProfileValidation.normalizePhone('+57 300 123 4567'),
        '+57 300 123 4567',
      );
    });

    test('rechaza pocos dígitos', () {
      expect(
        () => ProfileValidation.normalizePhone('123'),
        throwsFormatException,
      );
    });
  });
}
