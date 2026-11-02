/// Cadenas de UI en español (Fase 1 — sin gen_l10n todavía).
abstract final class AppStrings {
  static const appName = 'GPS-FMRA';
  static const tagline = 'Protección familiar y localización';

  static const splashLoading = 'Cargando…';
  static const cancel = 'Cancelar';
  static const close = 'Cerrar';
  static const retry = 'Reintentar';

  static const loginTitle = 'Iniciar sesión';
  static const loginSubtitle =
      'Entra con tu cuenta para ver el mapa familiar.';
  static const emailLabel = 'Correo electrónico';
  static const passwordLabel = 'Contraseña';
  static const displayNameLabel = 'Nombre para mostrar';
  static const loginButton = 'Entrar';
  static const registerButton = 'Crear cuenta';
  static const registerHint = '¿No tienes cuenta? Regístrate';
  static const loginHint = '¿Ya tienes cuenta? Inicia sesión';
  static const loginShellNote =
      'Usa el correo y contraseña de tu cuenta GPS-FMRA.';
  static const loginValidationError =
      'Ingresa un correo válido y una contraseña de al menos 6 caracteres.';
  static const loginMissingConfig =
      'Falta configurar SUPABASE_URL / SUPABASE_ANON_KEY en el archivo .env.';
  static const loginJwtHint =
      'Clave publishable detectada. Si Auth responde 401/invalid API key: '
      'Supabase → Project Settings → API → anon public (JWT eyJ…). '
      'Un “Connection reset” NO se arregla cambiando la clave.';
  static const loginGenericError =
      'No se pudo autenticar. Revisa credenciales y conexión.';
  static const loginNetworkError =
      'No hay conexión con el servidor (red o firewall). '
      'Prueba Wi‑Fi/datos distintos, desactiva VPN/ahorro de datos o abre '
      'https://dgmzewsxbnwxjpnrtgyb.supabase.co/auth/v1/health en el navegador del teléfono.';
  static const loginConfirmEmail =
      'Cuenta creada. Revisa tu correo y confirma el enlace antes de iniciar sesión. '
      'Para pruebas sin correo: Dashboard → Authentication → Sign In / Providers → '
      'Email → desactiva “Confirm email” → Save.';
  static const loginEmailRateLimit =
      'Supabase limitó el envío de correos de confirmación (demasiados intentos). '
      'Espera unos minutos o, para pruebas: Dashboard → Authentication → '
      'Sign In / Providers → Email → desactiva “Confirm email” → Save '
      '(así el registro no manda email y entra al instante).';

  static const mapTitle = 'Mapa';
  static const mapPlaceholderTitle = 'Mapa (marcador de posición)';
  static const mapPlaceholderBody =
      'Para ver Google Maps, crea una clave y ponla en .env y en '
      'android/local.properties. Guía: docs/GOOGLE_MAPS_ES.md';
  static const mapMissingKeyHint =
      'GOOGLE_MAPS_API_KEY vacía en .env — el mapa real no se carga.';
  static const mapGroupSelector = 'Grupo';
  static const mapNoGroup = 'Sin grupo — créalo en Grupos';
  static const mapMembersEmpty =
      'No hay integrantes. Crea un grupo en la pestaña Grupos.';

  static const groupsTitle = 'Grupos';
  static const groupsEmpty =
      'Aún no hay grupos. Pulsa “Crear grupo” para empezar.';
  static const groupsCreateTitle = 'Nuevo grupo familiar';
  static const groupsCreateAction = 'Crear grupo';
  static const groupsNameLabel = 'Nombre del grupo';
  static const groupsNameHint = 'Ej. Familia Ruiz';
  static const groupsCreatedPrefix = 'Grupo creado:';
  static const groupsTapMembers = 'Ver integrantes e invitar';

  static const membersHeading = 'Integrantes';
  static const membersEmpty = 'Este grupo aún no tiene integrantes visibles.';
  static const memberYouSuffix = '(tú)';
  static const memberShareActive = 'Compartiendo ubicación';
  static const memberSharePaused = 'Ubicación en pausa';
  static const memberShareRevoked = 'Compartir revocado';
  static const memberShareNone = 'Aún no compartes con este grupo';
  static const memberShareUnknown = 'Estado de compartir: pendiente';
  static const memberLastUpdateUnknown = 'Última actualización: —';

  static const inviteAction = 'Invitar';
  static const inviteTitle = 'Invitación (stub)';
  static const inviteBody =
      'Comparte este token con quien quieras invitar. '
      'La aceptación por QR/enlace llegará después; por ahora solo se guarda el hash en Supabase.';
  static const inviteCopyToken = 'Copiar token';
  static const inviteExpires = 'Vence:';
  static const inviteLastToken = 'Último token:';

  static const consentTitle = 'Consentimiento de ubicación';
  static const consentHeadline = 'Tú decides con quién compartir';
  static const consentBody =
      'GPS-FMRA usa tu ubicación para el mapa familiar. '
      'Puedes aceptar compartir con tus grupos, pausar en cualquier momento '
      'o saltarte este paso y configurar después.';
  static const consentNoSilent =
      'No hay seguimiento en segundo plano silencioso en esta fase. '
      'El permiso del sistema se pide solo cuando aceptas, en este contexto.';
  static const consentGroupsHeading = 'Tus grupos';
  static const consentNoGroupsYet =
      'Todavía no perteneces a ningún grupo. '
      'Puedes aceptar ahora (quita la pausa global) y crear un grupo después.';
  static const consentAccept = 'Aceptar y compartir';
  static const consentPause = 'Pausar compartir';
  static const consentSkipForNow = 'Continuar sin decidir ahora';
  static const consentContinue = 'Continuar al mapa';
  static const consentPausedSnack = 'Compartir ubicación en pausa.';
  static const consentCurrentlyPaused =
      'Ahora mismo el compartir está en pausa global.';
  static const consentStatusNone = 'Sin consentimiento registrado';
  static const consentStatusActive = 'Activo';
  static const consentStatusPaused = 'En pausa';
  static const consentStatusRevoked = 'Revocado';

  static const settingsTitle = 'Ajustes';
  static const settingsPrivacy = 'Privacidad y consentimiento';
  static const settingsProfile = 'Perfil';
  static const settingsSignOut = 'Cerrar sesión';
  static const settingsAbout = 'Acerca de GPS-FMRA';
  static const settingsVersion = 'Versión 1.0.0 — Fase 1 (MVP pantallas)';
  static const settingsProfileMissing =
      'Perfil no encontrado. Se intentará crear al recargar.';

  static const navMap = 'Mapa';
  static const navGroups = 'Grupos';
  static const navSettings = 'Ajustes';
}
