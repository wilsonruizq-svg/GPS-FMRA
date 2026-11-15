/// Normalización y validación de correo para registro y recuperación.
abstract final class AuthEmail {
  static final _format = RegExp(
    r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$',
  );

  /// Recorta, minúsculas, y opcionalmente `googlemail.com` → `gmail.com`.
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

  static bool isWellFormed(String normalizedEmail) =>
      _format.hasMatch(normalizedEmail);

  /// Registro y “olvidé mi clave”. El inicio de sesión usa solo [normalize].
  static String? validateForNewAccount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Ingresa tu correo electrónico.';
    }
    final normalized = normalize(trimmed);
    if (!isWellFormed(normalized)) {
      return 'Ingresa un correo electrónico válido.';
    }
    return null;
  }
}