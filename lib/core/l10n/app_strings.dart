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
      'El mapa usa MapLibre sin clave de pago. Guía: docs/MAPLIBRE_ES.md';
  static const mapMissingKeyHint =
      'Google Maps sigue pausado; el mapa visible es MapLibre.';
  static const mapEngineLibre = 'MapLibre · estilo libre (sin clave)';
  static const mapEngineMapTiler = 'MapLibre · MapTiler';
  static const mapGroupSelector = 'Grupo';
  static const mapNoGroup = 'Sin grupo — créalo en Grupos';
  static const mapMembersEmpty =
      'No hay integrantes. Crea un grupo en la pestaña Grupos.';

  static const groupsTitle = 'Grupos';
  static const groupsEmpty =
      'Aún no hay grupos. Crea uno para invitar a tu familia, '
      'o únete con un código que te hayan compartido.';
  static const groupsEmptyCreateHint =
      'Si eres el admin: crea el grupo y genera un código.';
  static const groupsEmptyJoinHint =
      'Si te invitaron: pega el código en “Unirme con código”.';
  static const groupsCreateTitle = 'Nuevo grupo familiar';
  static const groupsCreateAction = 'Crear grupo';
  static const groupsJoinAction = 'Unirme con código';
  static const groupsNameLabel = 'Nombre del grupo';
  static const groupsNameHint = 'Ej. Familia Ruiz';
  static const groupsCreatedPrefix = 'Grupo creado:';
  static const groupsTapMembers = 'Ver integrantes e invitar';
  static const groupsYouAreAdmin = 'Eres admin de este grupo';
  static const groupsYouAreMember = 'Eres integrante';
  static const groupsInviteHowTo =
      'Para invitar: toca el icono de persona (+) arriba → copia el código '
      '→ compártelo. Tu familia abre Grupos → Unirme con código.';

  static const membersHeading = 'Integrantes';
  static const membersEmpty = 'Este grupo aún no tiene integrantes visibles.';
  static const memberYouSuffix = '(tú)';
  static const memberRoleAdmin = 'Admin del grupo';
  static const memberRoleMember = 'Integrante';
  static const memberShareActive = 'Compartiendo ubicación';
  static const memberSharePaused = 'Ubicación en pausa';
  static const memberShareRevoked = 'Compartir revocado';
  static const memberShareNone = 'Aún no compartes con este grupo';
  static const memberShareUnknown = 'Estado de compartir: pendiente';
  static const memberLastUpdateUnknown = 'Última actualización: —';

  static const inviteAction = 'Invitar';
  static const inviteTitle = 'Código listo para compartir';
  static const inviteBody =
      'Comparte este código con tu familia (WhatsApp, SMS, etc.). '
      'Es de un solo uso y caduca en 7 días.';
  static const inviteFamilySteps =
      'Ellos deben: abrir la app → pestaña Grupos → '
      '“Unirme con código” → pegar el código → Aceptar invitación.';
  static const inviteCopyToken = 'Copiar código';
  static const inviteCopyLink = 'Copiar enlace';
  static const inviteCopied = 'Código copiado. Ya puedes compartirlo.';
  static const inviteLinkCopied = 'Enlace copiado. Ya puedes compartirlo.';
  static const inviteExpires = 'Vence:';
  static const inviteLastHeading = 'Código pendiente de usar';
  static const inviteLastToken = 'Último código:';
  static const inviteAdminOnly =
      'Solo un admin del grupo puede generar invitaciones.';
  static const inviteAcceptTitle = 'Unirme a un grupo';
  static const inviteAcceptHeadline = 'Pega el código o el enlace';
  static const inviteAcceptBody =
      'Pide el código al admin de la familia. '
      'Te unirás como integrante; el admin conserva su rol.';
  static const inviteCodeLabel = 'Código o enlace';
  static const inviteCodeHint = 'Ej. AbCd… o gpsfmra://invite/…';
  static const inviteAcceptAction = 'Aceptar invitación';
  static const inviteAccepting = 'Uniendo…';
  static const inviteJoinedPrefix = 'Te uniste a';
  static const inviteAlreadyMember = 'Ya pertenecías a';
  static const inviteRoleMember = 'rol: integrante';

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
  static const settingsProfileTap = 'Toca para editar tu perfil';
  static const settingsSignOut = 'Cerrar sesión';
  static const settingsAbout = 'Acerca de GPS-FMRA';
  static const settingsVersion = 'Versión 1.0.0 — Fase 1 (MVP pantallas)';
  static const settingsProfileMissing =
      'Perfil no encontrado. Se intentará crear al recargar.';

  static const profileEditTitle = 'Editar perfil';
  static const profileNameLabel = 'Nombre';
  static const profileNameHint = 'Ej. Wilson Ruiz';
  static const profilePhoneLabel = 'Teléfono (opcional)';
  static const profilePhoneHint = 'Ej. +57 300 123 4567';
  static const profilePhoneHelper = 'Solo tú lo editas; puedes dejarlo vacío.';
  static const profileEmailReadonly = 'Correo';
  static const profileSave = 'Guardar cambios';
  static const profileSaved = 'Perfil actualizado.';
  static const profileSaveError =
      'No se pudo guardar el perfil. Revisa la conexión e inténtalo de nuevo.';
  static const profileChangePhoto = 'Cambiar foto';
  static const profileRemovePhoto = 'Quitar foto';
  static const profilePhotoStorageNote =
      'La foto de perfil aún no está disponible: falta el bucket Storage '
      '“avatars” en Supabase. Puedes guardar nombre y teléfono ahora.';
  static const profilePhotoUploadError =
      'No se pudo subir la foto. Inténtalo de nuevo.';

  static const navMap = 'Mapa';
  static const navGroups = 'Grupos';
  static const navSettings = 'Ajustes';
}
