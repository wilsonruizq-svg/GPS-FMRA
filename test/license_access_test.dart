import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/core/l10n/app_strings.dart';
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

  group('LicenseAccess expiry display (GF-73)', () {
    test('uses valid_until over demo', () {
      final a = LicenseAccess.fromJson({
        'allowed': true,
        'reason': 'valid_until',
        'demo_started_at': '2026-11-15T12:00:00Z',
        'demo_ends_at': '2026-11-17T12:00:00Z',
        'valid_until': '2026-12-01T18:30:00Z',
        'is_admin': false,
      });
      expect(a.expiryForDisplay, isNotNull);
      expect(a.expiryForDisplay!.toUtc(), DateTime.utc(2026, 12, 1, 18, 30));
      expect(a.expiryLabelEs, startsWith(AppStrings.settingsLicenseExpiresPrefix));
      expect(a.expiryLabelEs, contains('de diciembre de 2026'));
    });

    test('falls back to demo_started_at + 2d', () {
      final a = LicenseAccess.fromJson({
        'allowed': true,
        'reason': 'demo',
        'demo_started_at': '2026-11-15T12:00:00Z',
        'demo_ends_at': '2026-11-17T12:00:00Z',
        'valid_until': null,
        'is_admin': false,
      });
      expect(a.expiryForDisplay!.toUtc(), DateTime.utc(2026, 11, 17, 12, 0));
      expect(a.expiryLabelEs, contains('de noviembre de 2026'));
    });

    test('admin without valid_until shows sin caducidad', () {
      final a = LicenseAccess.fromJson({
        'allowed': true,
        'reason': 'admin',
        'demo_started_at': '2026-11-15T12:00:00Z',
        'demo_ends_at': '2026-11-17T12:00:00Z',
        'valid_until': null,
        'is_admin': true,
      });
      expect(a.expiryForDisplay, isNull);
      expect(a.expiryLabelEs, AppStrings.settingsLicenseNoExpiry);
    });
  });

  test('admin email constant', () {
    expect(LicenseService.adminEmail, 'wilsonruizq@gmail.com');
  });

  test('admin phone has country code (GF-73)', () {
    expect(AppStrings.licenseAdminPhone, '+593 0989067887');
    expect(AppStrings.settingsAboutCreditPhone, '+593 0989067887');
    expect(AppStrings.licenseExpiredBody, contains('+593 0989067887'));
    expect(AppStrings.licenseUnavailableBody, contains('+593 0989067887'));
  });
}
