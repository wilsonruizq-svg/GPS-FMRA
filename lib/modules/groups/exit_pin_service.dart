import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// PIN de salida del grupo familiar (modo quiosco suave).
/// Hasheo y verificación solo en servidor (RPC bcrypt).
class ExitPinService {
  ExitPinService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  /// PIN numérico de 4 a 8 dígitos.
  static bool isValidPinFormat(String pin) =>
      RegExp(r'^[0-9]{4,8}$').hasMatch(pin.trim());

  Future<bool> isRequired() async {
    try {
      final raw = await _sb.rpc('exit_pin_is_required');
      if (raw is bool) return raw;
      return raw == true;
    } on PostgrestException catch (e) {
      if (_isMissingRpc(e)) return false;
      rethrow;
    }
  }

  Future<bool> groupHasPin(String groupId) async {
    try {
      final raw = await _sb.rpc(
        'group_has_exit_pin',
        params: {'p_group_id': groupId},
      );
      if (raw is bool) return raw;
      return raw == true;
    } on PostgrestException catch (e) {
      throw StateError(_mapError(e));
    }
  }

  Future<void> setPin({
    required String groupId,
    required String pin,
  }) async {
    final trimmed = pin.trim();
    if (!isValidPinFormat(trimmed)) {
      throw ArgumentError(
        'El PIN debe tener entre 4 y 8 dígitos numéricos.',
      );
    }
    try {
      await _sb.rpc(
        'set_group_exit_pin',
        params: {
          'p_group_id': groupId,
          'p_pin': trimmed,
        },
      );
    } on PostgrestException catch (e) {
      throw StateError(_mapError(e));
    }
  }

  Future<void> clearPin(String groupId) async {
    try {
      await _sb.rpc(
        'clear_group_exit_pin',
        params: {'p_group_id': groupId},
      );
    } on PostgrestException catch (e) {
      throw StateError(_mapError(e));
    }
  }

  /// Devuelve true si el PIN es correcto (o si no hay PIN requerido).
  Future<bool> verify(String pin) async {
    try {
      final raw = await _sb.rpc(
        'verify_exit_pin',
        params: {'p_pin': pin.trim()},
      );
      if (raw is Map) {
        return raw['ok'] == true;
      }
      return false;
    } on PostgrestException catch (e) {
      final mapped = _mapError(e);
      if (mapped.contains('PIN incorrecto') ||
          e.message.contains('PIN_WRONG') ||
          '${e.details}'.contains('PIN_WRONG')) {
        return false;
      }
      throw StateError(mapped);
    }
  }

  static bool _isMissingRpc(PostgrestException e) {
    final msg = e.message;
    return msg.contains('Could not find the function') ||
        msg.contains('PGRST202') ||
        msg.contains('exit_pin_is_required');
  }

  static String _mapError(PostgrestException e) {
    final msg = e.message;
    final details = '${e.details ?? ''} ${e.hint ?? ''} $msg';
    if (details.contains('AUTH_REQUIRED')) {
      return 'Debes iniciar sesión.';
    }
    if (details.contains('ADMIN_REQUIRED')) {
      return 'Solo un admin del grupo puede configurar el PIN de salida.';
    }
    if (details.contains('MEMBER_REQUIRED')) {
      return 'Debes ser integrante del grupo.';
    }
    if (details.contains('PIN_INVALID')) {
      return 'El PIN debe tener entre 4 y 8 dígitos.';
    }
    if (details.contains('PIN_WRONG')) {
      return 'PIN incorrecto.';
    }
    if (details.contains('GROUP_MISSING') ||
        details.contains('GROUP_REQUIRED')) {
      return 'No se encontró el grupo.';
    }
    if (msg.contains('Could not find the function') ||
        msg.contains('PGRST202')) {
      return 'Falta aplicar la migración del PIN de salida en Supabase. '
          'Ver supabase/APPLY_ES.md '
          '(archivo 20261102220000_group_exit_pin.sql).';
    }
    return msg.isNotEmpty ? msg : 'No se pudo verificar el PIN.';
  }
}
