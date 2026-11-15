import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// Resultado de [LicenseService.ensureAccess] (GF-72).
class LicenseAccess {
  const LicenseAccess({
    required this.allowed,
    required this.reason,
    this.status,
    this.demoStartedAt,
    this.demoEndsAt,
    this.validUntil,
    this.isAdmin = false,
  });

  final bool allowed;

  /// `admin` | `demo` | `valid_until` | `expired` | `email_unconfirmed` |
  /// `no_session` | `error` | `unavailable`
  final String reason;
  final String? status;
  final DateTime? demoStartedAt;
  final DateTime? demoEndsAt;
  final DateTime? validUntil;
  final bool isAdmin;

  bool get isExpired => !allowed && reason == 'expired';
  bool get needsEmailConfirm => !allowed && reason == 'email_unconfirmed';

  factory LicenseAccess.fromJson(Map<String, dynamic> map) {
    return LicenseAccess(
      allowed: map['allowed'] == true,
      reason: (map['reason'] as String?)?.trim().isNotEmpty == true
          ? (map['reason'] as String).trim()
          : (map['allowed'] == true ? 'ok' : 'expired'),
      status: map['status'] as String?,
      demoStartedAt: _parseTs(map['demo_started_at']),
      demoEndsAt: _parseTs(map['demo_ends_at']),
      validUntil: _parseTs(map['valid_until']),
      isAdmin: map['is_admin'] == true,
    );
  }

  static DateTime? _parseTs(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }

  static const deniedExpired = LicenseAccess(
    allowed: false,
    reason: 'expired',
  );

  static const deniedUnavailable = LicenseAccess(
    allowed: false,
    reason: 'unavailable',
  );
}

/// Licencia por cuenta Supabase (demo 2 días / valid_until / admin).
class LicenseService {
  LicenseService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  static const adminEmail = 'wilsonruizq@gmail.com';

  /// Crea entitlement si falta y evalúa acceso vía RPC.
  Future<LicenseAccess> ensureAccess() async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      return const LicenseAccess(allowed: false, reason: 'no_session');
    }

    final email = user.email?.trim().toLowerCase();
    if (email == adminEmail) {
      // Fast-path local; el RPC también lo marca admin.
    }

    try {
      final raw = await _sb.rpc('ensure_my_license_access');
      final map = _asJsonMap(raw);
      if (map != null) {
        return LicenseAccess.fromJson(map);
      }
      return LicenseAccess.deniedUnavailable;
    } on PostgrestException catch (e) {
      // Migración aún no APPLY: no abrir AppShell (fail-closed).
      final msg = e.message.toLowerCase();
      if (msg.contains('ensure_my_license_access') ||
          msg.contains('could not find the function') ||
          msg.contains('schema cache') ||
          e.code == 'PGRST202') {
        return LicenseAccess.deniedUnavailable;
      }
      return const LicenseAccess(allowed: false, reason: 'error');
    } catch (_) {
      return LicenseAccess.deniedUnavailable;
    }
  }

  static Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }
}
