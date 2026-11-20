import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'location_fix_filter.dart';
import 'location_keep_alive.dart';
import 'location_share_service.dart';

/// Publicación GPS al servidor mientras la sesión en [AppShell] está activa.
///
/// GF-65: el stream ya no vive en [MapShellScreen]; cambiar pestaña no detiene
/// los fixes hacia `location_updates` si hay grupo activo y consentimiento ON.
///
/// GF-67: el dropdown del mapa solo elige qué grupo se **muestra** (pines de
/// otros). La propia posición se publica una vez (`location_updates` por
/// user_id) y el consentimiento RLS se activa en **todos** los grupos donde
/// el usuario es miembro (share activo), no solo en el seleccionado.
class LocationShareSession {
  LocationShareSession._();

  static final LocationShareSession instance = LocationShareSession._();

  static const _publishHeartbeat = Duration(seconds: 8);
  /// GF-74: cache corto; el timer de consents cubre Grupo W aunque el
  /// dropdown del mapa se quede en el grupo creado (Grupo M).
  static const _consentCacheTtl = Duration(seconds: 20);
  static const _consentRefreshInterval = Duration(seconds: 20);

  final _locationShare = LocationShareService();
  final _fixFilter = const LocationFixFilter();

  /// Último fix propio aceptado (mapa u otros listeners).
  final ValueNotifier<MemberLocation?> selfFix = ValueNotifier(null);

  /// Grupo seleccionado en el mapa (UI). No limita a qué grupos se publica.
  String? _activeGroupId;
  Timer? _publishTimer;
  Timer? _consentTimer;
  StreamSubscription<Position>? _positionSub;
  bool _publishing = false;
  Position? _lastAcceptedFix;
  Position? _lastPublishedFix;
  DateTime? _lastPublishedAt;
  bool? _cachedCanPublish;
  DateTime? _cachedCanPublishAt;
  bool _sessionActive = false;

  void attach() {
    _sessionActive = true;
    if (_activeGroupId != null && _positionSub == null) {
      restartLoop();
    }
  }

  void detach() {
    _sessionActive = false;
    stopLoop();
    selfFix.value = null;
  }

  /// Marca el grupo del mapa (UI / pines ajenos). Arranca el loop GPS si hace
  /// falta; al **cambiar** de grupo no reinicia el stream — solo refresca
  /// consentimientos en todos los grupos (GF-67).
  void setActiveGroup(String? groupId) {
    final id = groupId?.trim();
    if (id == null || id.isEmpty) {
      _activeGroupId = null;
      stopLoop();
      return;
    }
    final changed = _activeGroupId != id;
    _activeGroupId = id;
    if (!_sessionActive) return;

    if (_positionSub == null) {
      restartLoop();
      return;
    }
    if (changed) {
      _cachedCanPublish = null;
      _cachedCanPublishAt = null;
      unawaited(_refreshAllGroupConsents());
    }
  }

  void onAppResumed() {
    if (!_sessionActive || _activeGroupId == null) return;
    _cachedCanPublish = null;
    _cachedCanPublishAt = null;
    unawaited(publishFromFix(force: true));
  }

  /// GF-74: tras crear/unirse a un grupo, refresca consents de **todas**
  /// las membresías (el dropdown del mapa no debe ser el único camino).
  void notifyMembershipsChanged() {
    _cachedCanPublish = null;
    _cachedCanPublishAt = null;
    if (!_sessionActive) return;
    unawaited(_refreshAllGroupConsents());
    if (_activeGroupId != null) {
      unawaited(publishFromFix(force: true));
    }
  }

  void stopLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _consentTimer?.cancel();
    _consentTimer = null;
    unawaited(_positionSub?.cancel());
    _positionSub = null;
  }

  void restartLoop() {
    stopLoop();
    _lastAcceptedFix = null;
    _lastPublishedFix = null;
    _lastPublishedAt = null;
    _cachedCanPublish = null;
    _cachedCanPublishAt = null;

    final groupId = _activeGroupId;
    if (!_sessionActive || groupId == null) return;

    // GF-67/74: consent en todos los grupos con membresía, no solo [groupId].
    unawaited(_refreshAllGroupConsents());

    unawaited(
      _ensureOsPermission().then((granted) {
        if (!granted || !_sessionActive || _activeGroupId != groupId) return;
        unawaited(LocationKeepAlive.startNativeKeepAlive());
        unawaited(LocationKeepAlive.maybeRequestBatteryExemptionOnce());
        _positionSub = Geolocator.getPositionStream(
          locationSettings: _trackingSettings(),
        ).listen(
          _onPositionFix,
          onError: (_) {},
          cancelOnError: false,
        );
      }),
    );

    unawaited(publishFromFix(force: true));
    _publishTimer = Timer.periodic(_publishHeartbeat, (_) {
      unawaited(publishFromFix(force: true));
    });
    // Independiente del dropdown: mantiene location_consents en Grupo W
    // aunque el mapa del sharer se quede en Grupo M.
    _consentTimer = Timer.periodic(_consentRefreshInterval, (_) {
      unawaited(_refreshAllGroupConsents());
    });
  }

  Future<void> _refreshAllGroupConsents() async {
    try {
      await _locationShare.ensurePublishForAllMemberships();
    } catch (_) {}
  }

  LocationSettings _trackingSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        intervalDuration: const Duration(seconds: 5),
        maxUpdateAge: const Duration(seconds: 20),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: LocationKeepAlive.fgsTitle,
          notificationText: LocationKeepAlive.fgsBody,
          notificationChannelName: LocationKeepAlive.fgsChannel,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );
  }

  Future<bool> _ensureOsPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  void _onPositionFix(Position pos) {
    if (!_fixFilter.accept(pos, previous: _lastAcceptedFix)) return;
    _lastAcceptedFix = pos;
    _emitSelf(pos);
    unawaited(publishFromFix(force: false));
  }

  void _emitSelf(Position pos) {
    final uid = _myUid();
    if (uid.isEmpty) return;
    selfFix.value = MemberLocation(
      userId: uid,
      lat: pos.latitude,
      lon: pos.longitude,
      recordedAt: DateTime.now().toUtc(),
      accuracyM: pos.accuracy.isFinite ? pos.accuracy : null,
    );
  }

  String _myUid() =>
      (supabase.auth.currentUser?.id ?? '').trim().toLowerCase();

  Future<bool> _canPublishCached() async {
    final now = DateTime.now().toUtc();
    final cachedAt = _cachedCanPublishAt;
    if (_cachedCanPublish != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _consentCacheTtl) {
      return _cachedCanPublish!;
    }
    try {
      // GF-74: si el lote all-groups tarda/falla, aún intenta el grupo del
      // mapa para no cortar la publicación live.
      final allowed = await _locationShare
          .canPublishForGroup(_activeGroupId ?? '')
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      _cachedCanPublish = allowed;
      _cachedCanPublishAt = now;
      return allowed;
    } catch (_) {
      return _cachedCanPublish ?? false;
    }
  }

  Future<void> publishFromFix({required bool force}) async {
    if (_publishing || !_sessionActive) return;
    if (_activeGroupId == null) return;

    final granted = await _ensureOsPermission();
    if (!granted) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    Position? pos = _lastAcceptedFix;
    final acceptedAge = pos == null
        ? null
        : DateTime.now().toUtc().difference(
            pos.timestamp.isUtc ? pos.timestamp : pos.timestamp.toUtc(),
          );
    final needsFresh =
        pos == null ||
        (force &&
            (acceptedAge == null || acceptedAge > const Duration(seconds: 15)));

    if (needsFresh) {
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (_fixFilter.accept(fresh, previous: _lastAcceptedFix)) {
          pos = fresh;
          _lastAcceptedFix = fresh;
          _emitSelf(fresh);
        }
      } catch (_) {}
    }

    if (pos == null) return;
    if (!_fixFilter.shouldPublish(
      pos,
      lastPublished: _lastPublishedFix,
      lastPublishedAt: _lastPublishedAt,
    )) {
      return;
    }

    final allowed = await _canPublishCached();
    if (!allowed) return;

    _publishing = true;
    try {
      // Un solo upsert por user_id; visibilidad por grupo = location_consents.
      await _locationShare
          .publishPosition(pos)
          .timeout(const Duration(seconds: 10));
      _lastPublishedFix = pos;
      _lastPublishedAt = DateTime.now().toUtc();
      _emitSelf(pos);
    } catch (_) {
      // El siguiente heartbeat / stream reintenta.
    } finally {
      _publishing = false;
    }
  }
}
