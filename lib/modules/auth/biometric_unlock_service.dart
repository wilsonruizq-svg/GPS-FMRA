import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desbloqueo por huella / biometría del dispositivo.
///
/// Primera vez: login con clave → se activa la preferencia.
/// Luego, si hay sesión Supabase válida, se pide biometría (no la clave).
class BiometricUnlockService {
  BiometricUnlockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  static const _prefsKey = 'gps_fmra_biometric_unlock_enabled';

  final LocalAuthentication _auth;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  Future<void> clear() => setEnabled(false);

  Future<bool> deviceSupportsBiometrics() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can || supported;
    } catch (e) {
      debugPrint('biometric support: $e');
      return false;
    }
  }

  /// True si debemos pedir huella en lugar de ir directo al shell.
  Future<bool> shouldGateWithBiometrics() async {
    if (!await isEnabled()) return false;
    return deviceSupportsBiometrics();
  }

  /// Tras login con clave exitoso: activa huella si el teléfono la tiene.
  Future<void> enableAfterPasswordLogin() async {
    if (await deviceSupportsBiometrics()) {
      await setEnabled(true);
    }
  }

  Future<bool> authenticate({
    String reason = 'Confirma tu identidad para abrir GPS-FMRA',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('biometric authenticate: $e');
      return false;
    }
  }
}
