import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/app_strings.dart';

/// Traduce excepciones de Auth/red a un mensaje usable en UI (español).
String authErrorMessage(Object error) {
  if (error is AuthException) {
    if (_isEmailRateLimit(error)) {
      return AppStrings.loginEmailRateLimit;
    }

    // gotrue envuelve resets/timeouts en AuthRetryableFetchException / Unknown.
    if (error is AuthRetryableFetchException ||
        _looksLikeNetworkText(error.message) ||
        (error is AuthUnknownException &&
            _isNetworkFailure(error.originalError))) {
      final detail = error is AuthUnknownException
          ? _shortDetail(error.originalError) ?? _shortDetail(error.message)
          : _shortDetail(error.message);
      return detail == null
          ? AppStrings.loginNetworkError
          : '${AppStrings.loginNetworkError}\n\nDetalle: $detail';
    }

    final code = error.code?.trim();
    final msg = error.message.trim();
    if (code != null && code.isNotEmpty && msg.isNotEmpty) {
      return '$msg ($code)';
    }
    if (msg.isNotEmpty) return msg;
    return AppStrings.loginGenericError;
  }

  if (_isNetworkFailure(error)) {
    final detail = _shortDetail(error);
    return detail == null
        ? AppStrings.loginNetworkError
        : '${AppStrings.loginNetworkError}\n\nDetalle: $detail';
  }

  if (error is PostgrestException) {
    final bits = <String>[
      if (error.message.trim().isNotEmpty) error.message.trim(),
      if (error.code != null && error.code!.trim().isNotEmpty) error.code!.trim(),
      if (error.details != null) error.details.toString(),
    ];
    if (bits.isNotEmpty) return bits.join(' · ');
  }

  final raw = error.toString().trim();
  if (raw.isNotEmpty && raw != 'Exception') {
    return '${AppStrings.loginGenericError}\n\nDetalle: ${_clip(raw, 220)}';
  }
  return AppStrings.loginGenericError;
}

bool _isEmailRateLimit(AuthException error) {
  final code = (error.code ?? '').toLowerCase();
  final msg = error.message.toLowerCase();
  return code == 'over_email_send_rate_limit' ||
      code == 'email_rate_limit_exceeded' ||
      msg.contains('email rate limit') ||
      msg.contains('over_email_send_rate_limit') ||
      msg.contains('rate limit exceeded');
}

bool _isNetworkFailure(Object error) {
  if (error is SocketException) return true;
  if (error is HandshakeException) return true;
  if (error is TlsException) return true;
  if (error is HttpException) return true;
  // ClientException (package:http) llega como tipo runtime vía gotrue.
  final typeName = error.runtimeType.toString();
  if (typeName.contains('ClientException')) return true;
  return _looksLikeNetworkText(error.toString());
}

bool _looksLikeNetworkText(String text) {
  final lower = text.toLowerCase();
  return lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('connection refused') ||
      lower.contains('broken pipe');
}

String? _shortDetail(Object error) {
  if (error is SocketException) {
    final os = error.osError?.message;
    if (os != null && os.trim().isNotEmpty) return _clip(os.trim(), 120);
    if (error.message.trim().isNotEmpty) {
      return _clip(error.message.trim(), 120);
    }
  }
  if (error is String) {
    final t = error.trim();
    if (t.isEmpty) return null;
    return _clip(t, 160);
  }
  final raw = error.toString().trim();
  if (raw.isEmpty) return null;
  return _clip(raw, 160);
}

String _clip(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}…';
}

@visibleForTesting
bool authErrorIsNetworkForTest(Object error) => _isNetworkFailure(error);
