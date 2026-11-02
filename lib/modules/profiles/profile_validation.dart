/// Validación de campos de perfil (sin dependencias de UI).
abstract final class ProfileValidation {
  static const displayNameMin = 2;
  static const displayNameMax = 80;
  static const phoneMax = 20;

  /// Devuelve mensaje de error en español, o `null` si es válido.
  static String? validateDisplayName(String? raw) {
    final name = raw?.trim() ?? '';
    if (name.isEmpty) {
      return 'El nombre es obligatorio.';
    }
    if (name.length < displayNameMin) {
      return 'El nombre debe tener al menos $displayNameMin caracteres.';
    }
    if (name.length > displayNameMax) {
      return 'El nombre no puede superar $displayNameMax caracteres.';
    }
    return null;
  }

  /// Normaliza teléfono opcional. Cadena vacía → `null` (borrar).
  /// Si hay valor, exige dígitos suficientes; lanza [FormatException] con mensaje ES.
  static String? normalizePhone(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > phoneMax) {
      throw const FormatException(
        'Teléfono no válido. Usa al menos 7 dígitos o déjalo vacío.',
      );
    }
    if (trimmed.length > phoneMax + 4) {
      throw const FormatException(
        'Teléfono demasiado largo.',
      );
    }
    return trimmed;
  }
}
