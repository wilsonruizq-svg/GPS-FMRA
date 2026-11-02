/// Cadenas de UI en español (Fase 1 — sin gen_l10n todavía).
abstract final class AppStrings {
  static const appName = 'GPS-FMRA';
  static const tagline = 'Protección familiar y localización';

  static const splashLoading = 'Cargando…';

  static const loginTitle = 'Iniciar sesión';
  static const loginSubtitle =
      'Entra con tu cuenta para ver el mapa familiar.';
  static const emailLabel = 'Correo electrónico';
  static const passwordLabel = 'Contraseña';
  static const loginButton = 'Entrar';
  static const registerHint = '¿No tienes cuenta? Regístrate';
  static const loginShellNote =
      'Auth con Supabase se conectará en el siguiente paso.';

  static const mapTitle = 'Mapa';
  static const mapPlaceholderTitle = 'Mapa (próximamente)';
  static const mapPlaceholderBody =
      'Aquí irá Google Maps. Por ahora es un marcador de posición.';
  static const mapGroupSelector = 'Grupo';
  static const mapNoGroup = 'Sin grupo seleccionado';

  static const groupsTitle = 'Grupos';
  static const groupsEmpty =
      'Aún no hay grupos. Podrás crear e invitar aquí.';

  static const consentTitle = 'Consentimiento de ubicación';
  static const consentBody =
      'Decide con quién compartes tu ubicación. '
      'Podrás pausar o revocar en cualquier momento.';
  static const consentContinue = 'Continuar al mapa';

  static const settingsTitle = 'Ajustes';
  static const settingsPrivacy = 'Privacidad y consentimiento';
  static const settingsProfile = 'Perfil';
  static const settingsAbout = 'Acerca de GPS-FMRA';
  static const settingsVersion = 'Versión 1.0.0 — Fase 1 (scaffold)';

  static const navMap = 'Mapa';
  static const navGroups = 'Grupos';
  static const navSettings = 'Ajustes';
}
