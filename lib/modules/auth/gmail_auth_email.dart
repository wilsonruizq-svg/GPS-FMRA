/// Validación y normalización de correo Gmail para registro y recuperación.
abstract final class GmailAuthEmail {
  /// Normaliza: recorta, minúsculas, `googlemail.com` → `gmail.com`.
  static String normalize(String raw) {
    final email = raw.trim().toLowerCase();
    final at = email.lastIndexOf('@');
    if (at < 1) return email;
    final local = email.substring(0, at);
    final domain = email.substring(at + 1);
    if (domain == 'googlemail.com') {
      return '$local@gmail.com';
    }
    return email;
  }

  static bool isGmailAddress(String normalizedEmail) {
    final at = normalizedEmail.lastIndexOf('@');
    if (at < 1) return false;
    return normalizedEmail.substring(at + 1) == 'gmail.com';
  }

  /// Solo registro y “olvidé mi clave”. El inicio de sesión no usa esto.
  static String? validateForNewAccount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Ingresa tu correo de Gmail.';
    }
    if (!trimmed.contains('@') || trimmed.startsWith('@')) {
      return 'Ingresa un correo válido.';
    }
    final normalized = normalize(trimmed);
    if (!isGmailAddress(normalized)) {
      return 'Solo se permiten cuentas de Gmail (@gmail.com o @googlemail.com). '
          'Usa un correo de Google para que la recuperación de contraseña funcione.';
    }
    return null;
  }
}