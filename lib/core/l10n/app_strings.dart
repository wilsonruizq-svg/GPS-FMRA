/// Cadenas de UI en español (Fase 1 — sin gen_l10n todavía).
abstract final class AppStrings {
  static const appName = 'GPS-FMRA';
  static const tagline = 'Protección familiar y localización';

  static const splashLoading = 'Cargando…';
  static const cancel = 'Cancelar';
  static const close = 'Cerrar';
  static const retry = 'Reintentar';

  static const biometricTitle = 'Desbloqueo con huella';
  static const biometricBody =
      'Usa la huella o el desbloqueo del teléfono. '
      'No pedimos la clave mientras tu sesión siga activa.';
  static const biometricReason =
      'Confirma tu identidad para abrir GPS-FMRA';
  static const biometricRetry = 'Usar huella';
  static const biometricFailed =
      'No se pudo verificar. Intenta de nuevo o usa la contraseña.';
  static const biometricUsePassword = 'Usar contraseña';

  static const loginTitle = 'Iniciar sesión';
  static const loginSubtitle =
      'Entra con tu cuenta para ver el mapa familiar.';
  static const emailLabel = 'Correo electrónico';
  static const passwordLabel = 'Contraseña';
  static const passwordShow = 'Mostrar contraseña';
  static const passwordHide = 'Ocultar contraseña';
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
  static const mapExpandTooltip = 'Ampliar mapa';
  static const mapCollapseTooltip = 'Mostrar integrantes';

  static const mapSavePlaceTooltip = 'Guardar ubicación con nombre';
  static const mapSavePlaceTitle = 'Guardar este lugar';
  static const mapSavePlaceNameLabel = 'Título';
  static const mapSavePlaceNameHint = 'Nombre del lugar';
  static const mapSavePlaceDescLabel = 'Detalle';
  static const mapSavePlaceDescHint = 'Notas u observaciones';
  static const mapSavePlacePhoto = 'Foto de referencia';
  static const mapSavePlacePhotoAdd = 'Agregar foto';
  static const mapSavePlacePhotoCamera = 'Cámara';
  static const mapSavePlacePhotoGallery = 'Galería';
  static const mapSavePlacePhotoClear = 'Quitar foto';
  static const mapSavePlaceOnlyMe = 'Solo yo';
  static const mapSavePlaceShareGroup = 'Compartir con el grupo';
  static const mapSavePlaceSave = 'Guardar';
  static const mapSavePlaceWhatsApp = 'WhatsApp';
  static const mapSavePlaceNeedGps = 'No hay GPS aún. Activa ubicación e inténtalo.';
  static const mapSavePlaceNeedGroup =
      'Elige un grupo para compartir el lugar.';
  static const mapSavePlaceSaved = 'Lugar guardado.';
  static const mapSavePlaceShared = 'Lugar compartido con el grupo.';
  static const mapSavePlaceWhatsAppOk = 'Abriendo WhatsApp…';
  static const mapSavePlaceWhatsAppError =
      'No se pudo abrir WhatsApp. ¿Está instalado?';
  static const mapSavePlaceError =
      'No se pudo guardar el lugar. Revisa la conexión.';
  static const mapSavePlaceApply =
      'Falta APPLY SQL: 20261102284300_named_places_photos.sql '
      '(named_places_photos_ok = true). Guía: docs/PLACES_ES.md';
  static const groupsPlacesTitle = 'Ubicaciones guardadas';
  static const groupsPlacesEmpty =
      'Sin ubicaciones aún. Crea una categoría (ej. Restaurantes) '
      'y guarda lugares desde el Mapa con “Compartir con el grupo”.';
  static const groupsPlacesDelete = 'Eliminar ubicación';
  static const groupsPlacesDeleted = 'Ubicación eliminada.';
  static const groupsPlacesDeleteConfirm =
      '¿Eliminar esta ubicación del grupo?';
  static const groupsPlacesOpenMap = 'Ver en mapa';
  static const groupsPlacesUncategorized = 'Sin categoría';
  static const groupsPlacesSoloTitle = 'Solo yo';
  static const groupsPlacesSoloHint =
      'Guardados sin compartir con el grupo. En el Mapa elige '
      '“Compartir con el grupo” para que los vea toda la familia.';
  static const groupsPlacesSharedTitle = 'Ubicaciones guardadas';
  static const groupsPlacesSectionHint = 'Toca para ver ubicaciones';
  static const groupsPlacesSearchHint =
      'Buscar ubicaciones (nombre, detalle…)';
  static const groupsPlacesSearchEmpty =
      'Ninguna ubicación coincide con la búsqueda.';
  static const groupsCategoryCreateTitle = 'Nueva categoría';
  static const groupsCategoryCreateAction = 'Nueva carpeta';
  static const groupsCategoryNameLabel = 'Nombre';
  static const groupsCategoryNameHint = 'Ej. Restaurantes, Negocios';
  static const groupsCategoryDelete = 'Eliminar categoría';
  static String groupsCategoryCreated(String name) =>
      'Categoría creada: $name';
  static String groupsCategoryDeleteConfirm(String name) =>
      '¿Eliminar la categoría «$name»? Las ubicaciones quedan sin carpeta.';
  static const groupsCategoryEmpty = 'Sin ubicaciones en esta carpeta.';
  static String groupsCategoryPlaceCount(int n) =>
      n == 1 ? '1 ubicación' : '$n ubicaciones';
  static const mapSavePlaceCategoryLabel = 'Categoría / carpeta';
  static const mapSavePlaceCategoryHint =
      'Elige una carpeta o pulsa «Nueva categoría» abajo';
  static const mapSavePlaceCategoryNone = 'Sin categoría';
  static const mapSavePlaceCategoryNew = 'Nueva categoría';
  static const groupsPlacesPhotoYes = 'Con foto';
  static const groupsPlacesPhotoNo = 'Sin foto';
  static const groupsPlacesFilterAll = 'Todas';
  static const groupsMembersSection = 'Integrantes';
  static const groupsMembersEmpty = 'Sin integrantes visibles.';
  static const groupsMembersLoading = 'Cargando integrantes…';
  static const groupsOpenDetail = 'Invitar / administrar';
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
  static const mapMyLocationTooltip = 'Mi ubicación';
  static const mapLocationDenied =
      'Necesitamos el permiso de ubicación para centrar el mapa.';
  static const mapLocationDeniedForever =
      'El permiso de ubicación está bloqueado. Actívalo en Ajustes del sistema.';
  static const mapLocationDisabled =
      'Activa el GPS / ubicación del dispositivo e inténtalo de nuevo.';
  static const mapLocationError =
      'No se pudo obtener tu ubicación. Inténtalo de nuevo.';
  static const mapOpenSettings = 'Abrir ajustes';
  static const mapMarkerYou = 'Tú';
  static const mapMarkerMember = 'Integrante';
  static const memberShareActiveNoFix = 'Estado: Sin señal';
  static String memberLastUpdateAt(String time) =>
      'Última actualización: $time';

  static const groupsTitle = 'Grupos';
  static const groupsEmpty =
      'Aún no hay grupos. Crea uno para invitar a tu familia, '
      'o únete con un código que te hayan compartido.';
  static const groupsEmptyCreateHint =
      'Si eres el admin: crea el grupo y genera un código.';
  static const groupsEmptyJoinHint =
      'Si te invitaron: pega el código en “Unirme con código”.';
  static const groupsAlreadyMemberHint =
      'Ya perteneces a un grupo. Para invitar, abre el grupo → Invitar.';
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
  static const memberShareActive = 'Estado: Compartiendo';
  static const memberSharePaused = 'Estado: En pausa';
  static const memberShareRevoked = 'Estado: Revocado';
  static const memberShareNone = 'Estado: Pendiente';
  static const memberShareUnknown = 'Estado: Pendiente';
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
  static const settingsPrivacySubtitle =
      'Quién puede ver tu ubicación en el mapa';
  static const settingsProfile = 'Perfil';
  static const settingsProfileTap = 'Editar nombre, teléfono y foto';
  static const settingsSignOut = 'Cerrar sesión';
  static const settingsAbout = 'Acerca de GPS-FMRA';
  static const settingsVersion = 'Versión 1.0.0 — Fase 1';
  static const settingsSectionAccount = 'Tu cuenta';
  static const settingsSectionPrivacy = 'Privacidad';
  static const settingsSectionSession = 'Sesión';
  static const settingsSectionAbout = 'Información';
  static const settingsHistory = 'Historial de ubicaciones';
  static const settingsHistorySubtitle =
      'Tus puntos GPS recientes (solo tu cuenta)';
  static const settingsProfileMissing =
      'Perfil no encontrado. Se intentará crear al recargar.';

  static const historyTitle = 'Historial';
  static const historyConsentNote =
      'Solo ves tu propio historial (usuario en sesión). '
      'Los puntos se guardan al compartir ubicación en el mapa. '
      'SQL: 20261113043000_location_history_own_only.sql';
  static const historyEmpty =
      'Aún no hay puntos de tu historial. '
      'Comparte ubicación en el mapa unos minutos y aplica el SQL own-only '
      'si aún ves puntos de otra persona.';

  static const exitPinTitle = 'PIN de salida';
  static const exitPinSetAction = 'Configurar PIN de salida';
  static const exitPinChangeAction = 'Cambiar PIN de salida';
  static const exitPinClearAction = 'Quitar PIN de salida';
  static const exitPinSaveAction = 'Guardar PIN';
  static const exitPinConfirmAction = 'Continuar';
  static const exitPinLabel = 'PIN';
  static const exitPinConfirmLabel = 'Confirmar PIN';
  static const exitPinHint = '4 a 8 dígitos';
  static const exitPinSetBody =
      'Este PIN lo pedirá la app para cerrar sesión o salir con Atrás. '
      'Compártelo solo con quien deba poder salir del modo familiar.';
  static const exitPinChallengeBody =
      'Ingresa el PIN del admin del grupo familiar para continuar.';
  static const exitPinRequiredLogout =
      'PIN requerido para cerrar sesión';
  static const exitPinRequiredExit = 'PIN requerido para salir';
  static const exitPinWrong = 'PIN incorrecto. Inténtalo de nuevo.';
  static const exitPinMismatch = 'Los PIN no coinciden.';
  static const exitPinFormatError =
      'El PIN debe tener entre 4 y 8 dígitos numéricos.';
  static const exitPinSaved = 'PIN de salida guardado.';
  static const exitPinCleared = 'PIN de salida eliminado.';
  static const exitPinAdminOnly =
      'Solo un admin del grupo puede configurar el PIN de salida.';
  static const exitPinStatusOn =
      'PIN de salida activo: hace falta para cerrar sesión o salir.';
  static const exitPinStatusOff =
      'Sin PIN de salida: cualquiera puede cerrar sesión o salir.';
  static const exitPinClearConfirm =
      '¿Quitar el PIN de salida? La app dejará de pedirlo al salir.';

  static const profileEditTitle = 'Editar perfil';
  static const profileNameLabel = 'Nombre';
  static const profileNameHint = 'Ej. Wilson Ruiz';
  static const profilePhoneLabel = 'Teléfono (opcional)';
  static const profilePhoneHint = 'Ej. +57 300 123 4567';
  static const profilePhoneHelper = 'Solo tú lo editas; puedes dejarlo vacío.';
  static const profileGenderLabel = 'Figurita en el mapa';
  static const profileGenderHelper =
      'Mujer u hombre en el mapa. Si no eliges, se estima por el nombre.';
  static const profileGenderFemale = 'Mujer';
  static const profileGenderMale = 'Hombre';
  static const profileGenderUnset = 'Automático';
  static const profileEmailReadonly = 'Correo';
  static const profileSave = 'Guardar cambios';
  static const profileSaved = 'Perfil actualizado.';
  static const profileSaveError =
      'No se pudo guardar el perfil. Revisa la conexión e inténtalo de nuevo.';
  static const profileAddPhoto = 'Añadir foto';
  static const profileChangePhoto = 'Cambiar foto';
  static const profileRemovePhoto = 'Quitar foto';
  static const profilePhotoFromGallery = 'Elegir de la galería';
  static const profilePhotoFromCamera = 'Tomar foto';
  static const profilePhotoCropTitle = 'Ajustar foto';
  static const profilePhotoCropHint =
      'Mueve y recorta en cuadrado para que el rostro quede centrado.';
  static const profilePhotoCropCancel = 'Foto cancelada.';
  static const profilePhotoUploaded = 'Foto de perfil actualizada.';
  static const profilePhotoStorageNote =
      'La foto aún no está activa en el servidor. En Supabase → SQL Editor '
      'ejecuta 20261102251000_avatars_storage_hosted.sql '
      '(éxito esperado: Success. No rows returned). '
      'Luego vuelve a abrir esta pantalla. Puedes guardar nombre y teléfono ahora.';
  static const profilePhotoUploadError =
      'No se pudo subir la foto. Si acabas de crear el bucket, cierra y '
      'vuelve a entrar a Editar perfil. Si el error sigue: aplica '
      '20261102251000_avatars_storage_hosted.sql en el SQL Editor '
      '(Success. No rows returned) y revisa la conexión.';
  static const profilePhotoApplyTitle = 'Falta preparar Storage (avatars)';
  static const profilePhotoApplyBody =
      'Para fotos de perfil:\n'
      '1. Abre Supabase → SQL Editor → New query.\n'
      '2. Pega todo el archivo '
      'supabase/migrations/20261102251000_avatars_storage_hosted.sql\n'
      '3. Run. Éxito esperado: Success. No rows returned.\n'
      '4. Confirma en Storage → Buckets que exista “avatars”.\n'
      '5. Vuelve a intentar Añadir foto.\n\n'
      'Si viste ERROR 42501 con el SQL viejo: usa solo este archivo hosted.\n'
      'Nombre y teléfono sí se pueden guardar sin el bucket.';

  static const sosButtonTooltip = 'Emergencia SOS';
  static const sosButtonLabel = 'SOS';
  static const sosConfirmTitle = '¿Enviar alerta de emergencia?';
  static String sosConfirmBody(String groupName) =>
      'Se avisará a los integrantes de “$groupName”. '
      'Verán una alerta en la app con tu ubicación si el GPS está disponible. '
      'No se llama a servicios de emergencia externos.';
  static const sosConfirmAction = 'Enviar SOS';
  static const sosCancelAction = 'No enviar';
  static const sosSent = 'Alerta SOS enviada al grupo.';
  static const sosSendError =
      'No se pudo enviar el SOS. Revisa la conexión e inténtalo de nuevo.';
  static const sosNeedGroup =
      'Elige o crea un grupo antes de enviar un SOS.';
  static const sosNeedMigration =
      'El API no ve la tabla sos_events (404). Aplica '
      '20261102261000_sos_events_api_fix.sql en SQL Editor y reintenta.';
  static const sosNeedMigrationTitle = 'SOS: falta activar en el API';
  static const sosNeedMigrationBody =
      'El botón SOS está en la app, pero el servidor responde 404 '
      '(tabla no visible al API). Arreglo:\n\n'
      '1. Abre Supabase → SQL Editor → New query.\n'
      '2. Pega TODO el archivo:\n'
      '   supabase/migrations/20261102261000_sos_events_api_fix.sql\n'
      '3. Run. Al final debes ver sos_events_ok = true.\n'
      '4. Cierra sesión en la app o reiníciala y pulsa SOS otra vez.\n\n'
      'Ese script crea la tabla si falta, da permisos GRANT y recarga '
      'el schema cache (NOTIFY pgrst). No hace falta chat/FCM para el banner.';
  /// Exact banner title for peer SOS, e.g. "SOS de Wilson C".
  static String sosBannerPeer(String name) => 'SOS de $name';
  static String sosBannerSelfNamed(String name) => 'SOS de $name';
  static const sosBannerSelf = 'Tu alerta SOS está activa.';
  /// Solo emisor: anula el SOS en el servidor (no es el Aceptar del compañero).
  static const sosBannerDismissOwn = 'Anular mi SOS';
  static const sosAbortConfirmTitle = '¿Anular tu SOS?';
  static const sosAbortConfirmBody =
      'Se cancelará la alerta para todo el grupo. '
      'Esto no es “Aceptar”: los compañeros usan Aceptar en su teléfono.';
  static const sosAbortConfirmYes = 'Sí, anular';
  static const sosBannerAck = 'Aceptar';
  static const sosBannerAckHint =
      'Confirma que viste el SOS. El emisor espera a todo el grupo.';
  static const sosAcknowledged =
      'Aceptado. Tu banner se ocultó; el emisor verá tu confirmación.';
  static const sosAcknowledgedAllDone =
      'Aceptado. Todos confirmaron: SOS cerrado.';
  static const sosAckError =
      'No se pudo guardar Aceptar en el servidor. '
      'El aviso SOS sigue visible; inténtalo de nuevo.';
  static const sosAckErrorNetwork =
      'Sin conexión con el servidor (Wi‑Fi/datos o certificado). '
      'Revisa internet e inténtalo otra vez. El SOS sigue visible.';
  static const sosAckNeedMigrationTitle = 'SOS Aceptar: falta activar en el API';
  static const sosAckNeedMigrationBody =
      'El botón Aceptar está en la app, pero el servidor no encuentra '
      'ack_sos / sos_acks (404). Arreglo:\n\n'
      '1. Supabase → SQL Editor → New query.\n'
      '2. Pega TODO:\n'
      '   supabase/migrations/20261102273000_sos_acks.sql\n'
      '3. Run. Al final: sos_acks_ok = true.\n'
      '4. Reinicia la app y pulsa Aceptar otra vez.\n\n'
      'Sin ese SQL el banner no puede confirmar al emisor.';
  static const sosAckLoading = 'Cargando confirmaciones del grupo…';
  static const sosAckNoPeers =
      'No hay otros integrantes en el grupo para confirmar.';
  static const sosAckWaitingResolve = 'Todos aceptaron. Cerrando alerta…';
  static const sosAckWaitingPeers =
      'Esperando a que todos los compañeros pulsen Aceptar…';
  static String sosAckPendingList(
    int acked,
    int expected,
    List<String> pendingNames,
  ) {
    final names = pendingNames.take(4).join(', ');
    final more = pendingNames.length > 4
        ? ' +${pendingNames.length - 4}'
        : '';
    return 'Confirmaciones $acked/$expected. Pendiente: $names$more';
  }
  static const sosCancelled = 'SOS anulado.';
  static const sosSending = 'Enviando alerta…';
  static const sosPushTitle = 'SOS — GPS-FMRA';
  static const sosPushBodyFallback = 'Un integrante del grupo necesita ayuda.';
  static const sosPushNotConfigured =
      'Alerta guardada. Push FCM aún no está activo en este teléfono '
      '(falta google-services.json / Firebase). Los compañeros la verán '
      'en la app si la tienen abierta.';
  static const sosPeerHint =
      'Los compañeros deben pulsar Aceptar. Tu alerta sigue hasta que todos confirmen.';

  static const navMap = 'Mapa';
  static const navGroups = 'Grupos';
  static const navSettings = 'Ajustes';

  static const chatAction = 'Chat';
  static const chatHint = 'Escribe un mensaje…';
  static const chatSend = 'Enviar';
  static const chatEmpty =
      'Aún no hay mensajes. Escribe el primero para el grupo.';
  static String chatTitleFor(String groupName) => 'Chat · $groupName';
  static const chatMissingSql =
      'Falta aplicar el SQL del chat en Supabase. '
      'SQL Editor → pega todo supabase/migrations/'
      '20261102280000_group_messages.sql → Run '
      '(group_messages_ok = true). Guía: docs/CHAT_ES.md';
  static const chatNeedGroup =
      'Elige un grupo arriba para abrir el chat.';
  static const chatPushTitle = 'Chat — GPS-FMRA';
  static const chatPushBodyFallback = 'Nuevo mensaje en tu grupo.';
  static String chatPushBody(String sender, String text) {
    final preview = text.length > 80 ? '${text.substring(0, 77)}…' : text;
    return '$sender: $preview';
  }

  static const dmAction = 'Mensaje';
  static const dmHint = 'Mensaje privado…';
  static const dmEmpty =
      'Aún no hay mensajes privados. Escribe el primero.';
  static String dmTitleFor(String peerName) => 'Chat · $peerName';
  static const dmPushTitle = 'Mensaje privado — GPS-FMRA';
  static const dmMissingSql =
      'Falta aplicar el SQL de mensajes 1:1. '
      'SQL Editor → pega todo supabase/migrations/'
      '20261102282000_direct_messages.sql → Run '
      '(direct_messages_ok = true). Guía: docs/DM_ES.md';
  static const dmSelfDisabled =
      'No puedes enviarte un mensaje a ti mismo.';
}
