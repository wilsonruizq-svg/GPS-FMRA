import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../../groups/widgets/member_card.dart';
import '../../location/consent_service.dart';
import '../../location/location_fix_filter.dart';
import '../../location/location_share_service.dart';
import '../../sos/sos_service.dart';

/// Shell del mapa: MapLibre + pines de integrantes con consentimiento activo.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key});

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

class _MapShellScreenState extends State<MapShellScreen>
    with WidgetsBindingObserver {
  /// Bogotá — solo si no hay GPS disponible al abrir el mapa.
  static const _fallbackCamera = CameraPosition(
    target: LatLng(4.7110, -74.0721),
    zoom: 11,
  );

  static const _myLocationZoom = 15.0;

  /// Heartbeat de publicación (documentado): cada 8 s como máximo de espera
  /// aunque el dispositivo esté quieto. El stream también publica al moverse
  /// ≥8 m, con piso de 5 s entre upserts.
  static const _publishHeartbeat = Duration(seconds: 8);
  static const _pollInterval = Duration(seconds: 15);
  static const _consentCacheTtl = Duration(seconds: 45);

  final _groups = GroupsService();
  final _consent = ConsentService();
  final _locationShare = LocationShareService();
  final _sos = SosService();
  final _fixFilter = const LocationFixFilter();

  MapLibreMapController? _mapController;
  bool _styleReady = false;
  bool _didAutoCenter = false;
  bool _locating = false;
  bool _osLocationGranted = false;
  bool _markerImageReady = false;

  /// Cámara inicial resuelta (GPS o fallback). Null = aún obteniendo ubicación.
  CameraPosition? _initialCamera;
  bool _cameraResolved = false;

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groupsList = const [];
  FamilyGroup? _selected;
  List<GroupMember> _members = const [];
  LocationConsent? _myConsent;
  Map<String, LocationConsent> _consentsBySharer = {};
  Map<String, MemberLocation> _locationsByUser = {};

  final Map<String, Circle> _circlesByUser = {};
  final Map<String, Circle> _accuracyByUser = {};
  final Map<String, Symbol> _labelsByUser = {};

  Timer? _publishTimer;
  Timer? _pollTimer;
  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _sosChannel;
  bool _publishing = false;
  bool _syncingMarkers = false;
  bool _markersDirty = false;
  bool _didFitMembers = false;
  bool _sosSending = false;
  List<SosEvent> _activeSos = const [];

  Position? _lastAcceptedFix;
  Position? _lastPublishedFix;
  DateTime? _lastPublishedAt;
  bool? _cachedCanPublish;
  DateTime? _cachedCanPublishAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveInitialCamera();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSharingLoop();
    _unsubscribeRealtime();
    _mapController = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cachedCanPublish = null;
      _cachedCanPublishAt = null;
      unawaited(_publishFromFix(force: true));
    }
  }

  /// Pide permiso OS al abrir el mapa y fija [initialCameraPosition] con GPS
  /// si está disponible (sin esperar al FAB).
  Future<void> _resolveInitialCamera() async {
    CameraPosition camera = _fallbackCamera;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final granted = await _ensureOsPermission(
          requestIfNeeded: true,
          showFeedback: false,
        );
        if (granted) {
          Position? pos = await Geolocator.getLastKnownPosition();
          pos ??= await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
          );
          camera = CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: _myLocationZoom,
          );
          _didAutoCenter = true;
        }
      }
    } catch (_) {
      camera = _fallbackCamera;
    }
    if (!mounted || _cameraResolved) return;
    setState(() {
      _initialCamera = camera;
      _cameraResolved = true;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _groups.listMyGroups();
      final previousId = _selected?.id;
      FamilyGroup? selected;
      if (previousId != null) {
        for (final g in groups) {
          if (g.id == previousId) {
            selected = g;
            break;
          }
        }
      }
      selected ??= groups.isNotEmpty ? groups.first : null;
      List<GroupMember> members = const [];
      LocationConsent? mine;
      Map<String, LocationConsent> consentsBySharer = {};
      Map<String, MemberLocation> locations = {};
      if (selected != null) {
        members = await _groups.listMembers(selected.id);
        final ownConsents = await _consent.listOwnGroupConsents();
        mine = ownConsents.cast<LocationConsent?>().firstWhere(
              (c) => c?.groupId == selected!.id,
              orElse: () => null,
            );
        final groupConsents = await _consent.listGroupConsents(selected.id);
        consentsBySharer = {
          for (final c in groupConsents) c.sharerId: c,
        };
        locations = await _fetchLocationsMap(members, groupId: selected.id);
      }
      if (!mounted) return;
      setState(() {
        _groupsList = groups;
        _selected = selected;
        _members = members;
        _myConsent = mine;
        _consentsBySharer = consentsBySharer;
        _locationsByUser = locations;
        _loading = false;
        _didFitMembers = false;
      });
      _maybeAutoCenter();
      await _syncMarkers();
      _restartSharingLoop();
      _restartRealtimeAndPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onSelectGroup(FamilyGroup? group) async {
    if (group == null) return;
    setState(() => _selected = group);
    try {
      final members = await _groups.listMembers(group.id);
      final ownConsents = await _consent.listOwnGroupConsents();
      final mine = ownConsents.cast<LocationConsent?>().firstWhere(
            (c) => c?.groupId == group.id,
            orElse: () => null,
          );
      final groupConsents = await _consent.listGroupConsents(group.id);
      final consentsBySharer = {
        for (final c in groupConsents) c.sharerId: c,
      };
      final locations =
          await _fetchLocationsMap(members, groupId: group.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _myConsent = mine;
        _consentsBySharer = consentsBySharer;
        _locationsByUser = locations;
        _didFitMembers = false;
      });
      _maybeAutoCenter();
      await _syncMarkers();
      _restartSharingLoop();
      _restartRealtimeAndPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<Map<String, MemberLocation>> _fetchLocationsMap(
    List<GroupMember> members, {
    String? groupId,
  }) async {
    final ids = members.map((m) => m.userId).toList();
    final gid = groupId ?? _selected?.id;
    final list = gid == null
        ? await _locationShare.fetchVisibleLocations(ids)
        : await _locationShare.fetchGroupLocations(
            groupId: gid,
            memberIds: ids,
          );
    return {for (final loc in list) loc.userId: loc};
  }

  String get _myUid => supabase.auth.currentUser?.id ?? '';

  String _shareFor(GroupMember m) {
    final c = _consentsBySharer[m.userId];
    if (m.userId == _myUid) {
      if (_myConsent?.isActive == true) return AppStrings.memberShareActive;
      if (_myConsent?.isPaused == true) return AppStrings.memberSharePaused;
      if (_myConsent?.status == 'revoked') return AppStrings.memberShareRevoked;
      return AppStrings.memberShareNone;
    }
    if (c == null) return AppStrings.memberShareUnknown;
    if (c.isActive) {
      return _locationsByUser.containsKey(m.userId)
          ? AppStrings.memberShareActive
          : AppStrings.memberShareActiveNoFix;
    }
    if (c.isPaused) return AppStrings.memberSharePaused;
    if (c.status == 'revoked') return AppStrings.memberShareRevoked;
    return AppStrings.memberShareUnknown;
  }

  String _lastUpdateFor(GroupMember m) {
    final loc = _locationsByUser[m.userId];
    if (loc == null) return AppStrings.memberLastUpdateUnknown;
    return AppStrings.memberLastUpdateAt(_formatClock(loc.recordedAt.toLocal()));
  }

  String _formatClock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    _markerImageReady = false;
    await _ensureMarkerImages();
    _maybeAutoCenter();
    await _syncMarkers();
  }

  Future<void> _ensureMarkerImages() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await controller.setSymbolIconAllowOverlap(true);
      await controller.setSymbolTextAllowOverlap(true);
      _markerImageReady = true;
    } catch (_) {
      _markerImageReady = true;
    }
  }

  /// Si el mapa ya montó con fallback (o GPS llegó tarde), anima a la posición.
  void _maybeAutoCenter() {
    if (_didAutoCenter) return;
    if (!_styleReady || _mapController == null) return;
    _didAutoCenter = true;
    _centerOnMyLocation(fromUser: false);
  }

  Future<bool> _ensureOsPermission({
    required bool requestIfNeeded,
    bool showFeedback = false,
  }) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }
    final granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (mounted && granted != _osLocationGranted) {
      setState(() => _osLocationGranted = granted);
    }
    if (!granted && mounted && showFeedback) {
      final forever = permission == LocationPermission.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forever
                ? AppStrings.mapLocationDeniedForever
                : AppStrings.mapLocationDenied,
          ),
          action: forever
              ? SnackBarAction(
                  label: AppStrings.mapOpenSettings,
                  onPressed: Geolocator.openAppSettings,
                )
              : null,
        ),
      );
    }
    return granted;
  }

  Future<void> _centerOnMyLocation({required bool fromUser}) async {
    if (_locating) return;
    final controller = _mapController;
    if (controller == null) return;

    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && fromUser) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.mapLocationDisabled)),
          );
        }
        return;
      }

      final granted = await _ensureOsPermission(
        requestIfNeeded: true,
        showFeedback: fromUser,
      );
      if (!granted) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pos.latitude, pos.longitude),
          _myLocationZoom,
        ),
      );
    } catch (_) {
      if (mounted && fromUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.mapLocationError)),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // --- Publicar / refrescar / Realtime ------------------------------------

  LocationSettings _trackingSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        intervalDuration: const Duration(seconds: 5),
        maxUpdateAge: const Duration(seconds: 20),
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

  void _stopSharingLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_positionSub?.cancel());
    _positionSub = null;
  }

  void _unsubscribeRealtime() {
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch != null) {
      unawaited(supabase.removeChannel(ch));
    }
    final sos = _sosChannel;
    _sosChannel = null;
    if (sos != null) {
      unawaited(_sos.unsubscribe(sos));
    }
  }

  void _restartSharingLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
    unawaited(_positionSub?.cancel());
    _positionSub = null;
    _lastAcceptedFix = null;
    _lastPublishedFix = null;
    _lastPublishedAt = null;
    _cachedCanPublish = null;
    _cachedCanPublishAt = null;

    final group = _selected;
    if (group == null || _myConsent?.isActive != true) return;

    unawaited(_ensureOsPermission(requestIfNeeded: false, showFeedback: false)
        .then((granted) {
      if (!granted || !mounted) return;
      _positionSub = Geolocator.getPositionStream(
        locationSettings: _trackingSettings(),
      ).listen(
        _onPositionFix,
        onError: (_) {},
        cancelOnError: false,
      );
    }));

    unawaited(_publishFromFix(force: true));
    _publishTimer = Timer.periodic(_publishHeartbeat, (_) {
      unawaited(_publishFromFix(force: true));
    });
  }

  void _onPositionFix(Position pos) {
    if (!_fixFilter.accept(pos, previous: _lastAcceptedFix)) return;
    _lastAcceptedFix = pos;
    _applySelfLocal(pos);
    unawaited(_publishFromFix(force: false));
  }

  void _applySelfLocal(Position pos) {
    if (!mounted || _myUid.isEmpty) return;
    final self = MemberLocation(
      userId: _myUid,
      lat: pos.latitude,
      lon: pos.longitude,
      recordedAt: DateTime.now().toUtc(),
      accuracyM: pos.accuracy.isFinite ? pos.accuracy : null,
    );
    setState(() {
      _locationsByUser = Map<String, MemberLocation>.from(_locationsByUser)
        ..[self.userId] = self;
    });
    unawaited(_syncMarkers());
  }

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

  Future<void> _publishFromFix({required bool force}) async {
    if (_publishing) return;
    final group = _selected;
    if (group == null || _myConsent?.isActive != true) return;

    final granted = await _ensureOsPermission(
      requestIfNeeded: false,
      showFeedback: false,
    );
    if (!granted) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    Position? pos = _lastAcceptedFix;
    final acceptedAge = pos == null
        ? null
        : DateTime.now().toUtc().difference(
              pos.timestamp.isUtc ? pos.timestamp : pos.timestamp.toUtc(),
            );
    final needsFresh = pos == null ||
        (force && (acceptedAge == null || acceptedAge > const Duration(seconds: 15)));

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
          _applySelfLocal(fresh);
        }
      } catch (_) {
        // Usa lastAccepted si existe.
      }
    }

    if (pos == null) return;
    if (!_fixFilter.shouldPublish(
      pos,
      lastPublished: _lastPublishedFix,
      lastPublishedAt: _lastPublishedAt,
    )) {
      return;
    }

    // Consentimiento con caché + timeout: no bloquear el candado _publishing.
    final allowed = await _canPublishCached(group.id);
    if (!allowed) return;

    _publishing = true;
    try {
      await _locationShare
          .publishPosition(pos)
          .timeout(const Duration(seconds: 10));
      _lastPublishedFix = pos;
      _lastPublishedAt = DateTime.now().toUtc();
      _applySelfLocal(pos);
    } catch (_) {
      // Silencioso: el siguiente heartbeat / stream reintenta.
    } finally {
      _publishing = false;
    }
  }

  void _mergeIncomingLocations(Map<String, MemberLocation> incoming) {
    final merged = Map<String, MemberLocation>.from(_locationsByUser);
    for (final e in incoming.entries) {
      final existing = merged[e.key];
      if (existing == null ||
          !e.value.recordedAt.isBefore(existing.recordedAt)) {
        merged[e.key] = e.value;
      }
    }
    _locationsByUser = merged;
  }

  void _restartRealtimeAndPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _unsubscribeRealtime();

    if (_selected == null) {
      if (_activeSos.isNotEmpty && mounted) {
        setState(() => _activeSos = const []);
      }
      return;
    }

    if (_members.isNotEmpty) {
      try {
        _realtimeChannel = _locationShare.subscribeLocationUpdates(
          onChange: (loc) {
            if (!mounted) return;
            final memberIds = _members.map((m) => m.userId).toSet();
            if (!memberIds.contains(loc.userId)) return;
            final existing = _locationsByUser[loc.userId];
            if (existing != null &&
                loc.recordedAt.isBefore(existing.recordedAt)) {
              return;
            }
            setState(() {
              _locationsByUser =
                  Map<String, MemberLocation>.from(_locationsByUser)
                    ..[loc.userId] = loc;
            });
            unawaited(_syncMarkers());
          },
          onDelete: (userId) {
            if (!mounted) return;
            // No borrar el pin propio local por un DELETE remoto obsoleto.
            if (userId == _myUid && _lastAcceptedFix != null) return;
            setState(() {
              _locationsByUser =
                  Map<String, MemberLocation>.from(_locationsByUser)
                    ..remove(userId);
            });
            unawaited(_syncMarkers());
          },
        );
      } catch (_) {
        // Fallback: solo polling.
      }
    }

    unawaited(_refreshMemberLocations());
    unawaited(_refreshActiveSos());
    _subscribeSosRealtime();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_refreshMemberLocations());
      unawaited(_refreshActiveSos());
    });
  }

  void _subscribeSosRealtime() {
    final group = _selected;
    if (group == null) return;
    try {
      _sosChannel = _sos.subscribeGroup(
        groupId: group.id,
        onChange: () {
          if (!mounted) return;
          unawaited(_refreshActiveSos());
        },
      );
    } catch (_) {
      // Polling cubre el fallback.
    }
  }

  Future<void> _refreshActiveSos() async {
    final group = _selected;
    if (group == null) {
      if (mounted && _activeSos.isNotEmpty) {
        setState(() => _activeSos = const []);
      }
      return;
    }
    try {
      final list = await _sos.listActiveForGroup(group.id);
      if (!mounted) return;
      setState(() => _activeSos = list);
    } catch (_) {
      // Tabla aún no aplicada o red: no tumbar el mapa.
    }
  }

  Future<void> _onSosPressed() async {
    final group = _selected;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosNeedGroup)),
      );
      return;
    }
    if (_sosSending) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.sosConfirmTitle),
        content: Text(AppStrings.sosConfirmBody(group.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.sosCancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.sosConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sosSending = true);
    try {
      double? lat;
      double? lon;
      try {
        final granted = await _ensureOsPermission(
          requestIfNeeded: true,
          showFeedback: false,
        );
        if (granted && await Geolocator.isLocationServiceEnabled()) {
          final pos = _lastAcceptedFix ??
              await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 8),
                ),
              );
          lat = pos.latitude;
          lon = pos.longitude;
        }
      } catch (_) {
        // SOS sin coords sigue siendo válido.
      }

      await _sos.raise(groupId: group.id, lat: lat, lon: lon);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosSent)),
      );
      await _refreshActiveSos();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final needsMigration = raw.contains('sos_events') ||
          raw.contains('relation') ||
          raw.contains('does not exist') ||
          raw.contains('schema cache') ||
          raw.contains('pgrst');
      if (needsMigration) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.sosNeedMigrationTitle),
            content: const SingleChildScrollView(
              child: Text(AppStrings.sosNeedMigrationBody),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.close),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.sosSendError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sosSending = false);
    }
  }

  Future<void> _cancelOwnSos(SosEvent event) async {
    try {
      await _sos.cancel(event.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosCancelled)),
      );
      await _refreshActiveSos();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosSendError)),
      );
    }
  }

  Future<void> _refreshMemberLocations() async {
    if (_members.isEmpty) return;
    try {
      final locations = await _fetchLocationsMap(_members);
      if (!mounted) return;
      setState(() => _mergeIncomingLocations(locations));
      await _syncMarkers();
    } catch (_) {
      // Silencioso en poll.
    }
  }

  double _accuracyRadiusPx(MemberLocation loc) {
    final meters = (loc.accuracyM ?? 35).clamp(12.0, 120.0);
    final zoom = _mapController?.cameraPosition?.zoom ?? _myLocationZoom;
    final mPerPx = 156543.03392 *
        math.cos(loc.lat * math.pi / 180).clamp(0.2, 1.0) /
        math.pow(2, zoom);
    return (meters / mPerPx).clamp(10.0, 90.0);
  }

  Future<void> _fitToMemberLocations(Map<String, LatLng> positions) async {
    final controller = _mapController;
    if (controller == null || !_styleReady || positions.isEmpty) return;
    if (positions.length == 1) {
      final only = positions.values.first;
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(only, _myLocationZoom),
        );
      } catch (_) {}
      return;
    }
    var minLat = positions.values.first.latitude;
    var maxLat = minLat;
    var minLon = positions.values.first.longitude;
    var maxLon = minLon;
    for (final p in positions.values) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // Padding mínimo si están muy juntos.
    if ((maxLat - minLat).abs() < 0.0004) {
      minLat -= 0.0005;
      maxLat += 0.0005;
    }
    if ((maxLon - minLon).abs() < 0.0004) {
      minLon -= 0.0005;
      maxLon += 0.0005;
    }
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLon),
            northeast: LatLng(maxLat, maxLon),
          ),
          left: 56,
          top: 56,
          right: 56,
          bottom: 56,
        ),
      );
    } catch (_) {}
  }

  Future<void> _syncMarkers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    if (_syncingMarkers) {
      _markersDirty = true;
      return;
    }
    if (!_markerImageReady) await _ensureMarkerImages();

    _syncingMarkers = true;
    _markersDirty = false;
    try {
      // Coordenadas reales (sin nudge artificial): el nudge de 35 m era la
      // causa de que el pin "tú" no coincidiera con el anillo GPS del dispositivo.
      final desired = Map<String, MemberLocation>.from(_locationsByUser);
      final display = <String, LatLng>{
        for (final e in desired.entries)
          e.key: LatLng(e.value.lat, e.value.lon),
      };

      final stale = <String>{
        ..._circlesByUser.keys,
        ..._accuracyByUser.keys,
        ..._labelsByUser.keys,
      }.where((id) => !desired.containsKey(id)).toList();
      for (final id in stale) {
        final circle = _circlesByUser.remove(id);
        final accuracy = _accuracyByUser.remove(id);
        final label = _labelsByUser.remove(id);
        if (circle != null) {
          try {
            await controller.removeCircle(circle);
          } catch (_) {}
        }
        if (accuracy != null) {
          try {
            await controller.removeCircle(accuracy);
          } catch (_) {}
        }
        if (label != null) {
          try {
            await controller.removeSymbol(label);
          } catch (_) {}
        }
      }

      final nameById = {for (final m in _members) m.userId: m.label};

      for (final entry in desired.entries) {
        final userId = entry.key;
        final loc = entry.value;
        final geometry = display[userId]!;
        final isSelf = userId == _myUid;
        final color = isSelf ? '#4DB6D4' : '#C62828';
        final label = nameById[userId] ??
            (isSelf ? AppStrings.mapMarkerYou : AppStrings.mapMarkerMember);
        final accRadius = _accuracyRadiusPx(loc);

        final existingAccuracy = _accuracyByUser[userId];
        if (existingAccuracy == null) {
          try {
            final halo = await controller.addCircle(
              CircleOptions(
                geometry: geometry,
                circleRadius: accRadius,
                circleColor: color,
                circleOpacity: 0.16,
                circleStrokeWidth: 1,
                circleStrokeColor: color,
                circleStrokeOpacity: 0.35,
              ),
            );
            _accuracyByUser[userId] = halo;
          } catch (_) {}
        } else {
          try {
            await controller.updateCircle(
              existingAccuracy,
              CircleOptions(
                geometry: geometry,
                circleRadius: accRadius,
                circleColor: color,
              ),
            );
          } catch (_) {}
        }

        final existingCircle = _circlesByUser[userId];
        if (existingCircle == null) {
          try {
            final circle = await controller.addCircle(
              CircleOptions(
                geometry: geometry,
                circleRadius: isSelf ? 10 : 12,
                circleColor: color,
                circleOpacity: 0.92,
                circleStrokeWidth: 2.5,
                circleStrokeColor: '#FFFFFF',
              ),
            );
            _circlesByUser[userId] = circle;
          } catch (_) {}
        } else {
          try {
            await controller.updateCircle(
              existingCircle,
              CircleOptions(
                geometry: geometry,
                circleColor: color,
                circleRadius: isSelf ? 10 : 12,
              ),
            );
          } catch (_) {}
        }

        final existingLabel = _labelsByUser[userId];
        if (existingLabel == null) {
          try {
            final symbol = await controller.addSymbol(
              SymbolOptions(
                geometry: geometry,
                textField: label,
                textSize: 12,
                textColor: '#0B2A4A',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.4,
                textOffset: const Offset(0, 1.4),
                textAnchor: 'top',
              ),
            );
            _labelsByUser[userId] = symbol;
          } catch (_) {}
        } else {
          try {
            await controller.updateSymbol(
              existingLabel,
              SymbolOptions(geometry: geometry, textField: label),
            );
          } catch (_) {}
        }
      }

      if (!_didFitMembers && display.length >= 2) {
        _didFitMembers = true;
        await _fitToMemberLocations(display);
      }
    } finally {
      _syncingMarkers = false;
      if (_markersDirty && mounted) {
        unawaited(_syncMarkers());
      }
    }
  }

  Widget _buildMapPane(BuildContext context) {
    if (!_cameraResolved || _initialCamera == null) {
      return const ColoredBox(
        color: Color(0xFFE8EEF4),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final styleUrl = Env.mapStyleUrl;
    final showMyLocation =
        _myConsent?.isActive == true || _osLocationGranted;
    return Stack(
      fit: StackFit.expand,
      children: [
        MapLibreMap(
          styleString: styleUrl,
          initialCameraPosition: _initialCamera!,
          compassEnabled: true,
          myLocationEnabled: showMyLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          trackCameraPosition: true,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: () {
            unawaited(_onStyleLoaded());
          },
        ),
        Positioned(
          right: 12,
          bottom: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'map_sos',
                tooltip: AppStrings.sosButtonTooltip,
                backgroundColor: AppColors.accentRed,
                foregroundColor: Colors.white,
                onPressed: _sosSending ? null : _onSosPressed,
                child: _sosSending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        AppStrings.sosButtonLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'map_my_location',
                tooltip: AppStrings.mapMyLocationTooltip,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.deepBlue,
                onPressed: _locating
                    ? null
                    : () => _centerOnMyLocation(fromUser: true),
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                Env.hasMapTilerKey
                    ? AppStrings.mapEngineMapTiler
                    : AppStrings.mapEngineLibre,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.deepBlue,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildSosBanner() {
    if (_activeSos.isEmpty) return null;
    final event = _activeSos.first;
    final isSelf = event.userId == _myUid;
    return Material(
      color: AppColors.accentRed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSelf
                    ? AppStrings.sosBannerSelf
                    : AppStrings.sosBannerPeer(event.label),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelf)
              TextButton(
                onPressed: () => _cancelOwnSos(event),
                child: const Text(
                  AppStrings.sosBannerDismissOwn,
                  style: TextStyle(color: Colors.white),
                ),
              )
            else
              TextButton(
                onPressed: () {
                  final lat = event.lat;
                  final lon = event.lon;
                  final c = _mapController;
                  if (lat == null || lon == null || c == null) return;
                  unawaited(
                    c.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(lat, lon),
                        _myLocationZoom,
                      ),
                    ),
                  );
                },
                child: const Text(
                  AppStrings.sosBannerAck,
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sosBanner = _buildSosBanner();
    return Column(
      children: [
        ?sosBanner,
        Material(
          color: Colors.white,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    AppStrings.mapGroupSelector,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _groupsList.isEmpty
                        ? Text(
                            AppStrings.mapNoGroup,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<FamilyGroup>(
                              isExpanded: true,
                              value: _selected,
                              items: _groupsList
                                  .map(
                                    (g) => DropdownMenuItem(
                                      value: g,
                                      child: Text(g.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _onSelectGroup,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: AppStrings.retry,
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _buildMapPane(context),
        ),
        Expanded(
          flex: 2,
          child: Material(
            color: AppColors.surface,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    : _members.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                AppStrings.mapMembersEmpty,
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _members.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final m = _members[i];
                              return MemberCard(
                                name: m.label,
                                isSelf: m.userId == _myUid,
                                shareStatusLabel: _shareFor(m),
                                lastUpdateLabel: _lastUpdateFor(m),
                                onTap: () {
                                  final loc = _locationsByUser[m.userId];
                                  final c = _mapController;
                                  if (loc == null || c == null) return;
                                  unawaited(
                                    c.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                        LatLng(loc.lat, loc.lon),
                                        _myLocationZoom,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }
}
