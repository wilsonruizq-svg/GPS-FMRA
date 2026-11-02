import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/core/l10n/app_strings.dart';
import 'package:gps_fmra/modules/auth/auth_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('AuthRetryableFetchException con reset → mensaje de red', () {
    final err = AuthRetryableFetchException(
      message:
          'ClientException with SocketException: Connection reset by peer '
          '(OS Error: Connection reset by peer, errno = 104), '
          'uri=https://dgmzewsxbnwxjpnrtgyb.supabase.co/auth/v1/signup',
    );
    final msg = authErrorMessage(err);
    expect(msg, contains(AppStrings.loginNetworkError.split('.').first));
    expect(msg.toLowerCase(), contains('connection reset'));
  });

  test('AuthException de validación conserva mensaje Supabase', () {
    const err = AuthException(
      'Password should be at least 6 characters.',
      code: 'weak_password',
    );
    expect(
      authErrorMessage(err),
      'Password should be at least 6 characters. (weak_password)',
    );
  });

  test('email rate limit → español con consejo Confirm email', () {
    const err = AuthException(
      'email rate limit exceeded',
      code: 'over_email_send_rate_limit',
    );
    final msg = authErrorMessage(err);
    expect(msg, AppStrings.loginEmailRateLimit);
    expect(msg.toLowerCase(), contains('confirm email'));
  });

  test('SocketException se clasifica como red', () {
    expect(
      authErrorIsNetworkForTest(const SocketException('Connection reset by peer')),
      isTrue,
    );
  });
}
