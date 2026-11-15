import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/license/license_service.dart';

void main() {
  group('LicenseAccess.fromJson', () {
    test('parses allowed demo', () {
      final a = LicenseAccess.fromJson({
        'allowed': true,
        'reason': 'demo',
        'status': 'demo',
        'demo_started_at': '2026-11-15T12:00:00Z',
        'demo_ends_at': '2026-11-17T12:00:00Z',
        'valid_until': null,
        'is_admin': false,
      });
      expect(a.allowed, isTrue);
      expect(a.reason, 'demo');
      expect(a.status, 'demo');
      expect(a.isExpired, isFalse);
      expect(a.demoEndsAt, isNotNull);
    });

    test('parses expired', () {
      final a = LicenseAccess.fromJson({
        'allowed': false,
        'reason': 'expired',
        'status': 'expired',
        'is_admin': false,
      });
      expect(a.allowed, isFalse);
      expect(a.isExpired, isTrue);
      expect(a.needsEmailConfirm, isFalse);
    });

    test('parses email_unconfirmed', () {
      final a = LicenseAccess.fromJson({
        'allowed': false,
        'reason': 'email_unconfirmed',
      });
      expect(a.needsEmailConfirm, isTrue);
    });

    test('parses admin', () {
      final a = LicenseAccess.fromJson({
        'allowed': true,
        'reason': 'admin',
        'status': 'active',
        'is_admin': true,
      });
      expect(a.allowed, isTrue);
      expect(a.isAdmin, isTrue);
    });
  });

  test('admin email constant', () {
    expect(LicenseService.adminEmail, 'wilsonruizq@gmail.com');
  });
}
