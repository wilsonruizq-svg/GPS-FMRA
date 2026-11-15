import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'consent_service.dart';
import 'location_fix_filter.dart';
import 'location_keep_alive.dart';
import 'location_share_service.dart';

/// Publicación GPS al servidor mientras la sesión en [AppShell] está activa.
///
/// GF-65: el stream ya no vive en [MapShellScreen]; cambiar pestaña no detiene
/// los fixes hacia `location_updates` si hay grupo activo y consentimiento ON.
class LocationShareSession {
  LocationShareSession._();

  static final LocationShareSession instance = LocationShareSession._();

  static const _publishHeartbeat = Duration(seconds: 8);
  static const _consentCacheTtl = Duration(seconds: 45);

  final _consent = ConsentService();
  final _locationShare = LocationShareService();
  final _fixFilter = const LocationFixFilter();

  /// Último fix propio aceptado (mapa u otros listeners).
  final ValueNotifier<MemberLocation?> selfFix = ValueNotifier(null);

  String? _activeGroupId;
  Timer? _publishTimer;
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

  void setActiveGroup(String? groupId) {
    final id = groupId?.trim();
    if (id == null || id.isEmpty) {
      _activeGroupId = null;
      stopLoop();
      return;
    }
    if (_activeGroupId == id && _positionSub != null) return;
    _activeGroupId = id;
    if (_sessionActive) {
      restartLoop();
    }
  }

  void onAppResumed() {
    if (!_sessionActive || _activeGroupId == null) return;
    _cachedCanPublish = null;
    _cachedCanPublishAt = null;
    unawaited(publishFromFix(force: true));
  }

  void stopLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
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

    unawaited(_consent.acceptShareWithGroup(groupId).catchError((_) {}));

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

  Future<bool> _canPublishCached(String groupId) async {
    final now = DateTime.now().toUtc();
    final cachedAt = _cachedCanPublishAt;
    if (_cachedCanPublish != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _consentCacheTtl) {
      return _cachedCanPublish!;
    }
    try {
      final allowed = await _locationShare
          .canPublishForGroup(groupId)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      _cachedCanPublish = allowed;
      _cachedCanPublishAt = now;
      return allowed;
    } catch (_) {
      return _cachedCanPublish ?? false;
    }
  }

  Future<void> publishFromFix({required bool force}) async {
    if (_publishing || !_sessionActive) return;
    final groupId = _activeGroupId;
    if (groupId == null) return;

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

    final allowed = await _canPublishCached(groupId);
    if (!allowed) return;

    _publishing = true;
    try {
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
