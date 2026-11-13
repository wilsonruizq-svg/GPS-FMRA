import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/screens/direct_chat_screen.dart';
import '../../chat/screens/group_chat_screen.dart';
import '../../groups/groups_service.dart';
import '../../groups/widgets/member_card.dart';
import '../../location/consent_service.dart';
import '../../location/location_fix_filter.dart';
import '../../location/location_share_service.dart';
import '../../places/named_places_service.dart';
import '../../places/whatsapp_share.dart';
import '../../profiles/avatar_compress.dart';
import '../../sos/sos_service.dart';
import 'package:image_picker/image_picker.dart';
import '../map_place_focus.dart';
import '../person_marker_bitmaps.dart';

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
  static const _placeFocusZoom = 16.5;

  /// Heartbeat de publicación (documentado): cada 8 s como máximo de espera
  /// aunque el dispositivo esté quieto. El stream también publica al moverse
  /// ≥8 m, con piso de 5 s entre upserts.
  static const _publishHeartbeat = Duration(seconds: 8);
  static const _pollInterval = Duration(seconds: 15);
  static const _sosPollInterval = Duration(seconds: 5);
  static const _consentCacheTtl = Duration(seconds: 45);

  final _groups = GroupsService();
  final _consent = ConsentService();
  final _locationShare = LocationShareService();
  final _sos = SosService();
  final _places = NamedPlacesService();
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

  final Map<String, Symbol> _figuresByUser = {};
  final Map<String, Circle> _accuracyByUser = {};
  final Map<String, Symbol> _labelsByUser = {};
  final Set<String> _registeredPersonImages = {};
  final Map<String, Circle> _placeCirclesById = {};
  final Map<String, Symbol> _placeLabelsById = {};
  List<NamedPlace> _namedPlaces = const [];
  String? _highlightedPlaceId;
  Timer? _highlightClearTimer;
  bool _savingPlace = false;
  Timer? _placeSyncTimer;

  /// false = mapa + integrantes; true = mapa ampliado (franja + nav abajo).
  bool _mapExpanded = false;

  Timer? _publishTimer;
  Timer? _pollTimer;
  Timer? _sosPollTimer;
  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _sosChannel;
  bool _publishing = false;
  bool _syncingMarkers = false;
  bool _markersDirty = false;
  bool _didFitMembers = false;
  bool _sosSending = false;
  List<SosEvent> _activeSos = const [];
  SosAckProgress? _sosAckProgress;
  /// Receptores: ocultar tras Aceptar en este dispositivo (además del ack en servidor).
  static final Set<String> _sosDismissedLocally = <String>{};
  static final Map<String, DateTime> _sosDismissedSenderAt = <String, DateTime>{};
  /// Invalida refrescos in-flight para que un poll viejo no resuscite el banner.
  int _sosRefreshEpoch = 0;

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
    _highlightClearTimer?.cancel();
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
      if (!MapPlaceFocus.hasPending) {
        _maybeAutoCenter();
      }
      await _syncMarkers();
      await _loadNamedPlaces();
      await _consumePendingPlaceFocus();
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

  String get _myUid =>
      (supabase.auth.currentUser?.id ?? '').trim().toLowerCase();

  bool _isOwnSos(SosEvent e) =>
      e.userId.trim().toLowerCase() == _myUid && _myUid.isNotEmpty;

  /// Paleta fija de pines (peers). El propio usuario usa [_selfPinColor].
  /// El color se elige con hash del user id → estable entre sesiones.
  static const _selfPinColor = '#4DB6D4';
  static const _peerPinPalette = <String>[
    '#1565C0', // azul
    '#2E7D32', // verde
    '#6A1B9A', // morado
    '#EF6C00', // naranja
    '#00838F', // teal
    '#AD1457', // rosa
    '#4527A0', // índigo
    '#558B2F', // verde oliva
    '#C62828', // rojo (uno entre varios)
    '#0277BD', // azul claro
    '#5D4037', // café
    '#F9A825', // ámbar
  ];

  String _pinColorFor(String userId, {required bool isSelf}) {
    if (isSelf) return _selfPinColor;
    final id = userId.trim().toLowerCase();
    if (id.isEmpty) return _peerPinPalette.first;
    var hash = 0;
    for (var i = 0; i < id.length; i++) {
      hash = 0x1fffffff & (hash * 31 + id.codeUnitAt(i));
    }
    return _peerPinPalette[hash % _peerPinPalette.length];
  }

  Color _colorFromHex(String hex) {
    final h = hex.replaceAll('#', '').trim();
    final value = int.parse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return Color(value);
  }

  Future<String> _ensurePersonImage({
    required bool female,
    required String colorHex,
  }) async {
    final controller = _mapController;
    final name = PersonMarkerBitmaps.imageName(
      female: female,
      colorHex: colorHex,
    );
    if (controller == null || _registeredPersonImages.contains(name)) {
      return name;
    }
    final bytes = await PersonMarkerBitmaps.png(
      female: female,
      color: _colorFromHex(colorHex),
    );
    await controller.addImage(name, bytes);
    _registeredPersonImages.add(name);
    return name;
  }

  /// Distancia aproximada en metros (suficiente para agrupar pines en casa).
  double _approxMeters(double lat1, double lon1, double lat2, double lon2) {
    final dLat = (lat1 - lat2) * 111320.0;
    final cosLat = math.cos(lat1 * math.pi / 180.0).abs().clamp(0.2, 1.0);
    final dLon = (lon1 - lon2) * 111320.0 * cosLat;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  /// Si varios están a <~28 m, reparte pin+etiqueta en un círculo (spiderfy).
  /// El halo de precisión sigue en la coordenada GPS real.
  Map<String, LatLng> _spiderfyDisplayPositions(
    Map<String, MemberLocation> desired,
  ) {
    final ids = desired.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final assigned = <String>{};
    final out = <String, LatLng>{};
    const clusterM = 28.0;

    for (final seed in ids) {
      if (assigned.contains(seed)) continue;
      final cluster = <String>[seed];
      assigned.add(seed);
      var grew = true;
      while (grew) {
        grew = false;
        for (final cand in ids) {
          if (assigned.contains(cand)) continue;
          final cLoc = desired[cand]!;
          for (final member in cluster) {
            final mLoc = desired[member]!;
            if (_approxMeters(
                  mLoc.lat,
                  mLoc.lon,
                  cLoc.lat,
                  cLoc.lon,
                ) <=
                clusterM) {
              cluster.add(cand);
              assigned.add(cand);
              grew = true;
              break;
            }
          }
        }
      }

      cluster.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (cluster.length == 1) {
        final loc = desired[cluster.first]!;
        out[cluster.first] = LatLng(loc.lat, loc.lon);
        continue;
      }

      var sumLat = 0.0;
      var sumLon = 0.0;
      for (final id in cluster) {
        sumLat += desired[id]!.lat;
        sumLon += desired[id]!.lon;
      }
      final n = cluster.length;
      final cLat = sumLat / n;
      final cLon = sumLon / n;
      // Radio ~14–22 m para separar etiquetas sin alejarse mucho del hogar.
      final radiusM = (14.0 + (n - 2) * 3.0).clamp(14.0, 28.0);
      final cosLat = math.cos(cLat * math.pi / 180.0).abs().clamp(0.2, 1.0);

      for (var i = 0; i < n; i++) {
        final angle = (2 * math.pi * i / n) - (math.pi / 2);
        final dLat = (radiusM * math.cos(angle)) / 111320.0;
        final dLon = (radiusM * math.sin(angle)) / (111320.0 * cosLat);
        out[cluster[i]] = LatLng(cLat + dLat, cLon + dLon);
      }
    }
    return out;
  }

  String _shareFor(GroupMember m) {
    final c = _consentsBySharer[m.userId];
    final isSelf =
        m.userId.trim().toLowerCase() == _myUid && _myUid.isNotEmpty;
    if (isSelf) {
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

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    _markerImageReady = false;
    _registeredPersonImages.clear();
    await _ensureMarkerImages();
    if (!MapPlaceFocus.hasPending) {
      _maybeAutoCenter();
    }
    await _syncMarkers();
    await _loadNamedPlaces();
    await _consumePendingPlaceFocus();
  }

  Future<void> _ensureMarkerImages() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await controller.setSymbolIconAllowOverlap(true);
      await controller.setSymbolTextAllowOverlap(true);
      // Precalienta mujer/hombre en color “tú”.
      await _ensurePersonImage(female: true, colorHex: _selfPinColor);
      await _ensurePersonImage(female: false, colorHex: _selfPinColor);
      _markerImageReady = true;
    } catch (_) {
      _markerImageReady = true;
    }
  }

  /// Si el mapa ya montó con fallback (o GPS llegó tarde), anima a la posición.
  void _maybeAutoCenter() {
    if (_didAutoCenter) return;
    if (MapPlaceFocus.hasPending) return;
    if (!_styleReady || _mapController == null) return;
    _didAutoCenter = true;
    _centerOnMyLocation(fromUser: false);
  }

  Future<void> _consumePendingPlaceFocus() async {
    final req = MapPlaceFocus.take();
    if (req == null || !mounted) return;
    await _focusSavedPlace(req);
  }

  Future<void> _focusSavedPlace(MapPlaceFocusRequest req) async {
    if (!_styleReady || _mapController == null) {
      // Mapa aún no listo: reencola para el próximo _onStyleLoaded/_load.
      MapPlaceFocus.request(req);
      return;
    }
    final isHistoryFocus = req.placeId?.startsWith('history:') == true;
    if (!isHistoryFocus &&
        req.placeId != null &&
        !_namedPlaces.any((p) => p.id == req.placeId)) {
      await _loadNamedPlaces();
    }
    if (req.placeId != null &&
        !_namedPlaces.any((p) => p.id == req.placeId)) {
      _namedPlaces = [
        NamedPlace(
          id: req.placeId!,
          ownerId: '',
          name: (req.name ?? (isHistoryFocus ? 'Historial' : 'Lugar'))
                  .trim()
                  .isEmpty
              ? (isHistoryFocus ? 'Historial' : 'Lugar')
              : req.name!.trim(),
          lat: req.lat,
          lon: req.lon,
          createdAt: DateTime.now().toUtc(),
        ),
        ..._namedPlaces.where((p) => !p.id.startsWith('history:')),
      ];
    }

    _highlightedPlaceId = req.placeId;
    _didAutoCenter = true;
    await _syncPlaceMarkers();
    final controller = _mapController;
    if (controller == null || !mounted) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(req.lat, req.lon),
          _placeFocusZoom,
        ),
      );
    } catch (e) {
      debugPrint('focusSavedPlace camera: $e');
    }

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _highlightedPlaceId = null;
      unawaited(_syncPlaceMarkersSafe());
    });
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
    _sosPollTimer?.cancel();
    _sosPollTimer = null;
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
    _sosPollTimer?.cancel();
    _sosPollTimer = null;
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
    });
    // SOS: poll corto para que el compañero vea el banner aunque Realtime falle.
    _sosPollTimer = Timer.periodic(_sosPollInterval, (_) {
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

  String _sosSenderDismissKey(SosEvent e) => '${e.groupId}|${e.userId}';

  bool _isSosHiddenLocally(SosEvent e) {
    final id = e.id.trim().toLowerCase();
    if (id.isNotEmpty && _sosDismissedLocally.contains(id)) return true;
    final until = _sosDismissedSenderAt[_sosSenderDismissKey(e)];
    if (until != null && !e.createdAt.toUtc().isAfter(until.toUtc())) {
      return true;
    }
    return false;
  }

  void _markSosDismissedLocally(SosEvent event) {
    final id = event.id.trim().toLowerCase();
    if (id.isNotEmpty) _sosDismissedLocally.add(id);
    final key = _sosSenderDismissKey(event);
    final at = event.createdAt.toUtc();
    final prev = _sosDismissedSenderAt[key];
    if (prev == null || !at.isBefore(prev)) {
      _sosDismissedSenderAt[key] = at;
    }
  }

  bool _shouldShowSosEvent(SosEvent e, Set<String> myAcked) {
    // Emisor: siempre ve su SOS activo hasta resolved/cancelled en servidor.
    if (_isOwnSos(e)) return true;
    // Receptor: ocultar si Aceptar local o ack en servidor.
    if (_isSosHiddenLocally(e)) return false;
    if (myAcked.contains(e.id.trim().toLowerCase())) return false;
    return true;
  }

  Future<void> _refreshActiveSos() async {
    final group = _selected;
    if (group == null) {
      if (mounted && (_activeSos.isNotEmpty || _sosAckProgress != null)) {
        setState(() {
          _activeSos = const [];
          _sosAckProgress = null;
        });
      }
      return;
    }
    final epoch = ++_sosRefreshEpoch;
    try {
      final list = await _sos.listActiveForGroup(group.id);
      if (!mounted || epoch != _sosRefreshEpoch) return;
      final named = _withMemberNames(list);
      final myAcked = await _sos.listMyAckedSosIds(named.map((e) => e.id));
      if (!mounted || epoch != _sosRefreshEpoch) return;

      var visible =
          named.where((e) => _shouldShowSosEvent(e, myAcked)).toList();

      SosAckProgress? progress;
      final own = visible.where(_isOwnSos).toList();
      if (own.isNotEmpty) {
        try {
          progress = await _sos.listAckProgress(own.first.id);
          if (!mounted || epoch != _sosRefreshEpoch) return;
          if (progress.allPeersAcked) {
            await _sos.tryResolveIfAllAcked(own.first.id);
            if (!mounted || epoch != _sosRefreshEpoch) return;
            final again = await _sos.listActiveForGroup(group.id);
            if (!mounted || epoch != _sosRefreshEpoch) return;
            final namedAgain = _withMemberNames(again);
            final acked2 =
                await _sos.listMyAckedSosIds(namedAgain.map((e) => e.id));
            if (!mounted || epoch != _sosRefreshEpoch) return;
            visible = namedAgain
                .where((e) => _shouldShowSosEvent(e, acked2))
                .toList();
            progress =
                visible.any(_isOwnSos) ? progress : null;
          }
        } catch (_) {
          progress = null;
        }
      }

      setState(() {
        _activeSos = visible;
        _sosAckProgress = progress;
      });
    } catch (_) {
      // Tabla aún no aplicada o red: no tumbar el mapa.
    }
  }

  /// Prioriza el nombre del integrante del grupo ya cargado en el mapa.
  List<SosEvent> _withMemberNames(List<SosEvent> events) {
    if (events.isEmpty || _members.isEmpty) return events;
    final nameById = {
      for (final m in _members)
        if (m.displayName != null && m.displayName!.trim().isNotEmpty)
          m.userId: m.displayName!.trim()
        else if (m.label.trim().isNotEmpty && m.label != 'Miembro')
          m.userId: m.label.trim(),
    };
    if (nameById.isEmpty) return events;
    return [
      for (final e in events)
        (e.displayName == null || e.displayName!.trim().isEmpty) &&
                nameById.containsKey(e.userId)
            ? e.copyWith(displayName: nameById[e.userId])
            : e,
    ];
  }

  String _sosSenderLabel(SosEvent event) {
    final fromEvent = event.displayName?.trim();
    if (fromEvent != null && fromEvent.isNotEmpty) return fromEvent;
    for (final m in _members) {
      if (m.userId != event.userId) continue;
      final n = m.displayName?.trim();
      if (n != null && n.isNotEmpty) return n;
      if (m.label.trim().isNotEmpty && m.label != 'Miembro') return m.label;
    }
    return event.label;
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

      var event = await _sos.raise(groupId: group.id, lat: lat, lon: lon);
      if (!mounted) return;
      event = _withMemberNames([event]).first;
      // Si no hay otros miembros, resuelve de inmediato.
      unawaited(_sos.tryResolveIfAllAcked(event.id));
      // Banner inmediato en este teléfono (sin esperar poll/Realtime).
      setState(() {
        _activeSos = [
          event,
          ..._activeSos.where((e) => e.id != event.id),
        ];
        _sosAckProgress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.sosSent} ${AppStrings.sosPeerHint}'),
        ),
      );
      unawaited(_refreshActiveSos());
    } catch (e) {
      if (!mounted) return;
      if (SosService.isMissingApiObject(e)) {
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
        final short = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              short.length > 160
                  ? '${AppStrings.sosSendError} (${short.substring(0, 160)}…)'
                  : '${AppStrings.sosSendError} ($short)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sosSending = false);
    }
  }

  Future<void> _cancelOwnSos(SosEvent event) async {
    _sosRefreshEpoch++;
    setState(() {
      _activeSos = _activeSos.where((e) => e.id != event.id).toList();
      if (_sosAckProgress?.sosId == event.id) _sosAckProgress = null;
    });
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
      // GPS real en [desired]; pin+label pueden spiderfy si se apilan en casa.
      // El halo de precisión usa siempre la coordenada real.
      final desired = Map<String, MemberLocation>.from(_locationsByUser);
      final display = _spiderfyDisplayPositions(desired);

      final stale = <String>{
        ..._figuresByUser.keys,
        ..._accuracyByUser.keys,
        ..._labelsByUser.keys,
      }.where((id) => !desired.containsKey(id)).toList();
      for (final id in stale) {
        final figure = _figuresByUser.remove(id);
        final accuracy = _accuracyByUser.remove(id);
        final label = _labelsByUser.remove(id);
        if (figure != null) {
          try {
            await controller.removeSymbol(figure);
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

      final memberById = {for (final m in _members) m.userId: m};
      final nameById = {for (final m in _members) m.userId: m.label};

      for (final entry in desired.entries) {
        final userId = entry.key;
        final loc = entry.value;
        final realGeometry = LatLng(loc.lat, loc.lon);
        final pinGeometry = display[userId] ?? realGeometry;
        final isSelf =
            userId.trim().toLowerCase() == _myUid && _myUid.isNotEmpty;
        final color = _pinColorFor(userId, isSelf: isSelf);
        final member = memberById[userId];
        final female = PersonMarkerGender.isFemale(
          gender: member?.gender,
          displayName: member?.displayName ?? nameById[userId],
        );
        final iconName = await _ensurePersonImage(
          female: female,
          colorHex: color,
        );
        final label = nameById[userId] ??
            (isSelf ? AppStrings.mapMarkerYou : AppStrings.mapMarkerMember);
        final accRadius = _accuracyRadiusPx(loc);

        final existingAccuracy = _accuracyByUser[userId];
        if (existingAccuracy == null) {
          try {
            final halo = await controller.addCircle(
              CircleOptions(
                geometry: realGeometry,
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
                geometry: realGeometry,
                circleRadius: accRadius,
                circleColor: color,
              ),
            );
          } catch (_) {}
        }

        final existingFigure = _figuresByUser[userId];
        if (existingFigure == null) {
          try {
            final figure = await controller.addSymbol(
              SymbolOptions(
                geometry: pinGeometry,
                iconImage: iconName,
                // GF-22: ~4 mm más chicos y sin halo blanco.
                iconSize: PersonMarkerBitmaps.mapIconSize,
                iconAnchor: 'bottom',
              ),
            );
            _figuresByUser[userId] = figure;
          } catch (_) {}
        } else {
          try {
            await controller.updateSymbol(
              existingFigure,
              SymbolOptions(
                geometry: pinGeometry,
                iconImage: iconName,
                iconSize: PersonMarkerBitmaps.mapIconSize,
              ),
            );
          } catch (_) {}
        }

        final existingLabel = _labelsByUser[userId];
        if (existingLabel == null) {
          try {
            final symbol = await controller.addSymbol(
              SymbolOptions(
                geometry: pinGeometry,
                textField: label,
                textSize: 12,
                textColor: '#0B2A4A',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.4,
                textOffset: const Offset(0, 1.55),
                textAnchor: 'top',
              ),
            );
            _labelsByUser[userId] = symbol;
          } catch (_) {}
        } else {
          try {
            await controller.updateSymbol(
              existingLabel,
              SymbolOptions(geometry: pinGeometry, textField: label),
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

  Future<void> _loadNamedPlaces() async {
    try {
      final list = await _places.listVisible(groupId: _selected?.id);
      if (!mounted) return;
      _namedPlaces = list;
      // MapLibre + InheritedWidget: nunca sincronizar en el mismo frame
      // que cierra el diálogo (framework.dart:6281 _dependents.isEmpty).
      await _syncPlaceMarkersAfterFrame();
    } catch (e) {
      if (NamedPlacesService.looksLikeMissingTable(e)) {
        debugPrint('named_places: falta APPLY SQL');
      } else {
        debugPrint('named_places load: $e');
      }
    }
  }

  /// Espera N frames (ruta de diálogo / InheritedWidget ya deactivated).
  Future<void> _waitFrames(int count) async {
    for (var i = 0; i < count; i++) {
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!done.isCompleted) done.complete();
      });
      WidgetsBinding.instance.scheduleFrame();
      await done.future;
    }
  }

  /// Tras pop del AlertDialog: no setState / MapLibre hasta que el route muera.
  Future<void> _waitAfterDialogClosed() async {
    await _waitFrames(3);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await _waitFrames(1);
  }

  Future<void> _syncPlaceMarkersAfterFrame() async {
    if (!mounted) return;
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        // Solo MapLibre controller — sin setState (evita 6281 con dialog/route).
        await _syncPlaceMarkers();
      } catch (e) {
        debugPrint('syncPlaceMarkers deferred: $e');
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
    await done.future;
  }

  Future<void> _syncPlaceMarkers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await _syncPlaceMarkersBody(controller);
    } catch (e) {
      debugPrint('syncPlaceMarkers: $e');
    }
  }

  Future<void> _syncPlaceMarkersBody(MapLibreMapController controller) async {
    final desired = {for (final p in _namedPlaces) p.id: p};
    final stale = [
      ..._placeCirclesById.keys,
      ..._placeLabelsById.keys,
    ].where((id) => !desired.containsKey(id)).toSet();
    for (final id in stale) {
      final c = _placeCirclesById.remove(id);
      final l = _placeLabelsById.remove(id);
      if (c != null) {
        try {
          await controller.removeCircle(c);
        } catch (_) {}
      }
      if (l != null) {
        try {
          await controller.removeSymbol(l);
        } catch (_) {}
      }
    }

    for (final place in desired.values) {
      final geometry = LatLng(place.lat, place.lon);
      final highlight = place.id == _highlightedPlaceId;
      final color = highlight ? '#C62828' : '#6A1B9A';
      final radius = highlight ? 14.0 : 8.0;
      final stroke = highlight ? 3.0 : 2.0;
      final existing = _placeCirclesById[place.id];
      if (existing == null) {
        try {
          final circle = await controller.addCircle(
            CircleOptions(
              geometry: geometry,
              circleRadius: radius,
              circleColor: color,
              circleOpacity: 0.95,
              circleStrokeWidth: stroke,
              circleStrokeColor: '#FFFFFF',
            ),
          );
          _placeCirclesById[place.id] = circle;
        } catch (_) {}
      } else {
        try {
          await controller.updateCircle(
            existing,
            CircleOptions(
              geometry: geometry,
              circleColor: color,
              circleRadius: radius,
              circleStrokeWidth: stroke,
            ),
          );
        } catch (_) {}
      }

      final existingLabel = _placeLabelsById[place.id];
      // Etiqueta = nombre del lugar (categoría se muestra en lista Grupos).
      final label = place.name;
      final textColor = highlight ? '#C62828' : '#4A148C';
      final textSize = highlight ? 13.0 : 11.0;
      if (existingLabel == null) {
        try {
          final symbol = await controller.addSymbol(
            SymbolOptions(
              geometry: geometry,
              textField: label,
              textSize: textSize,
              textColor: textColor,
              textHaloColor: '#FFFFFF',
              textHaloWidth: 1.3,
              textOffset: const Offset(0, 1.3),
              textAnchor: 'top',
            ),
          );
          _placeLabelsById[place.id] = symbol;
        } catch (_) {}
      } else {
        try {
          await controller.updateSymbol(
            existingLabel,
            SymbolOptions(
              geometry: geometry,
              textField: label,
              textSize: textSize,
              textColor: textColor,
            ),
          );
        } catch (_) {}
      }
    }
  }

  /// Nueva categoría — mismo patrón bc1cc73: rootNavigator + wait + no setState
  /// mientras el route del diálogo anidado se desactiva (assert 6281).
  Future<PlaceCategory?> _promptCreatePlaceCategory({
    required String groupId,
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context, // State context, no el ctx del diálogo padre
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.groupsCategoryCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: AppStrings.groupsCategoryNameLabel,
            hintText: AppStrings.groupsCategoryNameHint,
          ),
          maxLength: 40,
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) {
              Navigator.of(ctx, rootNavigator: true).pop(t);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isEmpty) return;
              Navigator.of(ctx, rootNavigator: true).pop(t);
            },
            child: const Text(AppStrings.mapSavePlaceCategoryNew),
          ),
        ],
      ),
    );

    final trimmed = name?.trim() ?? '';
    // Crítico: esperar a que muera el route antes de dispose / RPC / snackbar.
    await _waitAfterDialogClosed();
    controller.dispose();
    if (trimmed.isEmpty || !mounted) return null;

    try {
      final created = await _places.createCategory(
        groupId: groupId,
        name: trimmed,
      );
      GpsFmraApp.messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(AppStrings.groupsCategoryCreated(created.name))),
      );
      return created;
    } catch (e) {
      GpsFmraApp.messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return null;
    }
  }

  Future<void> _onSavePlacePressed() async {
    if (_savingPlace) return;
    Position? fix = _lastAcceptedFix;
    if (fix == null) {
      final ok = await _ensureOsPermission(
        requestIfNeeded: true,
        showFeedback: true,
      );
      if (!ok || !mounted) return;
      try {
        fix = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      } catch (_) {
        fix = null;
      }
    }
    if (!mounted) return;
    if (fix == null) {
      GpsFmraApp.messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text(AppStrings.mapSavePlaceNeedGps)),
      );
      return;
    }

    final nameController = TextEditingController();
    final descController = TextEditingController();
    // Si hay grupo seleccionado, por defecto compartir (así aparece en Grupos).
    var shareWithGroup = _selected != null;
    Uint8List? photoBytes;
    String? selectedCategoryId;
    List<PlaceCategory> categories = const [];
    var categoriesLoaded = false;
    final picker = ImagePicker();
    final groupIdForCats = _selected?.id;

    Future<void> pickPhoto(ImageSource source, void Function(void Function()) setLocal) async {
      try {
        final file = await picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 88,
        );
        if (file == null) return;
        final raw = await file.readAsBytes();
        final compressed = AvatarCompress.compress(raw);
        setLocal(() => photoBytes = compressed);
      } catch (e) {
        debugPrint('place photo pick: $e');
      }
    }

    Future<void> ensureCategories(void Function(void Function()) setLocal) async {
      if (categoriesLoaded || groupIdForCats == null) return;
      try {
        final list = await _places.listCategories(groupIdForCats);
        setLocal(() {
          categories = list;
          categoriesLoaded = true;
        });
      } catch (e) {
        debugPrint('load place categories: $e');
        setLocal(() => categoriesLoaded = true);
      }
    }

    var scheduledCatLoad = false;

    // null = cancel; 'save' | 'wa'
    final action = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            if (shareWithGroup && !categoriesLoaded && !scheduledCatLoad) {
              scheduledCatLoad = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(ensureCategories(setLocal));
              });
            }
            final scheme = Theme.of(ctx).colorScheme;
            final pillShape = RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            );
            ButtonStyle pillStyle({required bool primary}) {
              if (primary) {
                return FilledButton.styleFrom(
                  shape: pillShape,
                  backgroundColor: AppColors.deepBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }
              return OutlinedButton.styleFrom(
                shape: pillShape,
                foregroundColor: AppColors.deepBlue,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: scheme.outlineVariant),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }

            Widget actionPill({
              required VoidCallback? onPressed,
              required String label,
              IconData? icon,
              bool primary = false,
            }) {
              final child = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
              if (primary) {
                return FilledButton(
                  style: pillStyle(primary: true),
                  onPressed: onPressed,
                  child: child,
                );
              }
              return OutlinedButton(
                style: pillStyle(primary: false),
                onPressed: onPressed,
                child: child,
              );
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              title: Text(
                AppStrings.mapSavePlaceTitle,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (_) {
                        InputDecoration pillDecoration(String hint) {
                          final border = OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                              width: 1,
                            ),
                          );
                          return InputDecoration(
                            isDense: true,
                            hintText: hint,
                            hintStyle: TextStyle(
                              color: AppColors.midBlue.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            // Hint siempre visible (no se apaga con tema claro/oscuro).
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: const BorderSide(
                                color: AppColors.signalCyan,
                                width: 1.2,
                              ),
                            ),
                            counterText: '',
                          );
                        }

                        Widget labeledPill({
                          required TextEditingController controller,
                          required String label,
                          required String hint,
                          int maxLines = 1,
                          int? maxLength,
                          bool autofocus = false,
                        }) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.deepBlue,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: controller,
                                autofocus: autofocus,
                                textAlign: TextAlign.center,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: maxLines,
                                maxLength: maxLength,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.deepBlue,
                                ),
                                decoration: pillDecoration(hint),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            labeledPill(
                              controller: nameController,
                              label: AppStrings.mapSavePlaceNameLabel,
                              hint: AppStrings.mapSavePlaceNameHint,
                              maxLength: 80,
                              autofocus: true,
                            ),
                            const SizedBox(height: 10),
                            labeledPill(
                              controller: descController,
                              label: AppStrings.mapSavePlaceDescLabel,
                              hint: AppStrings.mapSavePlaceDescHint,
                              maxLines: 2,
                              maxLength: 280,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.mapSavePlacePhoto,
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    if (photoBytes != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          photoBytes!,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              setLocal(() => photoBytes = null),
                          child: const Text(AppStrings.mapSavePlacePhotoClear),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: actionPill(
                            onPressed: () => unawaited(
                              pickPhoto(ImageSource.camera, setLocal),
                            ),
                            icon: Icons.photo_camera_outlined,
                            label: AppStrings.mapSavePlacePhotoCamera,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: actionPill(
                            onPressed: () => unawaited(
                              pickPhoto(ImageSource.gallery, setLocal),
                            ),
                            icon: Icons.photo_outlined,
                            label: AppStrings.mapSavePlacePhotoGallery,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    RadioListTile<bool>(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: false,
                      groupValue: shareWithGroup,
                      title: const Text(AppStrings.mapSavePlaceOnlyMe),
                      onChanged: (_) => setLocal(() {
                        shareWithGroup = false;
                        selectedCategoryId = null;
                      }),
                    ),
                    RadioListTile<bool>(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: true,
                      groupValue: shareWithGroup,
                      title: const Text(AppStrings.mapSavePlaceShareGroup),
                      onChanged: (_) {
                        setLocal(() => shareWithGroup = true);
                        unawaited(ensureCategories(setLocal));
                      },
                    ),
                    if (shareWithGroup) ...[
                      const SizedBox(height: 2),
                      DropdownButtonFormField<String?>(
                        key: ValueKey(selectedCategoryId ?? 'none'),
                        initialValue: selectedCategoryId,
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: AppStrings.mapSavePlaceCategoryLabel,
                          helperText: AppStrings.mapSavePlaceCategoryHint,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(AppStrings.mapSavePlaceCategoryNone),
                          ),
                          for (final c in categories)
                            DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => selectedCategoryId = v),
                      ),
                      const SizedBox(height: 6),
                      actionPill(
                        onPressed: groupIdForCats == null
                            ? null
                            : () async {
                                final created =
                                    await _promptCreatePlaceCategory(
                                  groupId: groupIdForCats,
                                );
                                await _waitFrames(2);
                                if (created == null || !ctx.mounted) {
                                  return;
                                }
                                setLocal(() {
                                  categories = [
                                    ...categories,
                                    created,
                                  ]..sort(
                                      (a, b) => a.name
                                          .toLowerCase()
                                          .compareTo(b.name.toLowerCase()),
                                    );
                                  selectedCategoryId = created.id;
                                  categoriesLoaded = true;
                                });
                              },
                        icon: Icons.create_new_folder_outlined,
                        label: AppStrings.mapSavePlaceCategoryNew,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: double.maxFinite,
                  child: Row(
                    children: [
                      Expanded(
                        child: actionPill(
                          onPressed: () =>
                              Navigator.of(ctx, rootNavigator: true).pop(),
                          label: AppStrings.cancel,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: actionPill(
                          onPressed: () => Navigator.of(ctx, rootNavigator: true)
                              .pop('wa'),
                          label: AppStrings.mapSavePlaceWhatsApp,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: actionPill(
                          onPressed: () => Navigator.of(ctx, rootNavigator: true)
                              .pop('save'),
                          label: AppStrings.mapSavePlaceSave,
                          primary: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // Capturar datos YA; no usar ctx del diálogo. No dispose aún (ruta animando).
    final name = nameController.text.trim();
    final description = descController.text.trim();
    final photoJpeg = photoBytes;
    if (action == null) {
      await _waitAfterDialogClosed();
      nameController.dispose();
      descController.dispose();
      return;
    }

    final placeName = name.isEmpty ? 'Mi ubicación' : name;
    final lat = fix.latitude;
    final lon = fix.longitude;
    final groupIdForSave = shareWithGroup ? _selected?.id : null;
    final wantGroup = shareWithGroup;
    final categoryIdForSave = wantGroup ? selectedCategoryId : null;

    // Crítico (assert 6281): route deactivated → _dependents.isEmpty.
    // Cero setState / MapLibre hasta que el diálogo termine de morir.
    await _waitAfterDialogClosed();
    nameController.dispose();
    descController.dispose();
    if (!mounted) return;

    void toast(String text, {int seconds = 4}) {
      GpsFmraApp.messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: Duration(seconds: seconds),
        ),
      );
    }

    if (action == 'wa') {
      final ok = await WhatsAppShare.sharePlace(
        name: placeName,
        lat: lat,
        lon: lon,
      );
      if (!mounted) return;
      toast(
        ok
            ? AppStrings.mapSavePlaceWhatsAppOk
            : AppStrings.mapSavePlaceWhatsAppError,
      );
      return;
    }

    if (action != 'save') return;

    if (wantGroup && (groupIdForSave == null || groupIdForSave.isEmpty)) {
      toast(AppStrings.mapSavePlaceNeedGroup);
      return;
    }

    // Spinner FAB solo después de settle (rebuild MapLibre seguro).
    _savingPlace = true;
    if (mounted) setState(() {});

    try {
      debugPrint(
        'named_places save: name=$placeName share=$wantGroup '
        'group=$groupIdForSave category=$categoryIdForSave '
        'lat=$lat lon=$lon photo=${photoJpeg != null}',
      );
      final created = await _places.createWithOptionalPhoto(
        name: placeName,
        lat: lat,
        lon: lon,
        groupId: groupIdForSave,
        description: description.isEmpty ? null : description,
        categoryId: categoryIdForSave,
        photoJpeg: photoJpeg,
      );
      debugPrint('named_places save ok id=${created.id}');
      // Lista en memoria; NO setState aquí (_namedPlaces no pinta Flutter UI).
      _namedPlaces = [
        created,
        ..._namedPlaces.where((p) => p.id != created.id),
      ];
      toast(
        wantGroup
            ? AppStrings.mapSavePlaceShared
            : AppStrings.mapSavePlaceSaved,
      );
      // Pines MapLibre mucho después, en frames propios.
      _placeSyncTimer?.cancel();
      _placeSyncTimer = Timer(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        await _waitFrames(2);
        if (!mounted) return;
        await _syncPlaceMarkersSafe();
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        await _loadNamedPlaces();
      });
    } catch (e, st) {
      debugPrint('named_places save ERROR: $e\n$st');
      final raw = e.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
      final msg = NamedPlacesService.looksLikeMissingRpc(e) ||
              raw.contains('Falta APPLY SQL')
          ? raw
          : NamedPlacesService.looksLikeMissingTable(e)
              ? AppStrings.mapSavePlaceApply
              : '${AppStrings.mapSavePlaceError}\n$raw';
      toast(msg, seconds: 12);
    } finally {
      _savingPlace = false;
      if (mounted) {
        // Un frame más por si el snackbar / map aún sincronizan.
        await _waitFrames(1);
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _syncPlaceMarkersSafe() async {
    try {
      if (!mounted || !_styleReady || _mapController == null) return;
      await _syncPlaceMarkers();
    } catch (e) {
      debugPrint('syncPlaceMarkersSafe: $e');
    }
  }

  Widget _buildMapPane(BuildContext context) {
    final styleUrl = Env.mapStyleUrl;
    final showMyLocation =
        _myConsent?.isActive == true || _osLocationGranted;
    final mapReady = _cameraResolved && _initialCamera != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!mapReady)
          const ColoredBox(
            color: Color(0xFFE8EEF4),
            child: Center(child: CircularProgressIndicator()),
          )
        else
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
            // Mantener pulsado = pin / guardar ubicación actual.
            onMapLongClick: (point, latLng) {
              unawaited(_onSavePlacePressed());
            },
          ),
        // SOS dentro del mapa, arriba; mismo tamaño que «mi ubicación».
        Positioned(
          right: 12,
          top: 12,
          child: FloatingActionButton.small(
            heroTag: 'map_sos',
            tooltip: AppStrings.sosButtonTooltip,
            backgroundColor: AppColors.accentRed,
            foregroundColor: Colors.white,
            onPressed: _sosSending ? null : _onSosPressed,
            child: _sosSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    AppStrings.sosButtonLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
        // Pin / guardar ubicación — siempre visible (también mientras carga el mapa).
        Positioned(
          right: 12,
          bottom: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'map_save_place',
                tooltip: AppStrings.mapSavePlaceTooltip,
                backgroundColor: AppColors.signalCyan,
                foregroundColor: AppColors.deepBlue,
                onPressed: _savingPlace ? null : _onSavePlacePressed,
                child: _savingPlace
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.push_pin),
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
      ],
    );
  }

  Future<void> _acceptSosPeer(SosEvent event) async {
    // Receptor: registra ack en servidor y oculta banner localmente.
    _sosRefreshEpoch++;
    _markSosDismissedLocally(event);
    setState(() {
      _activeSos = _activeSos.where((e) => !_isSosHiddenLocally(e)).toList();
    });
    final lat = event.lat;
    final lon = event.lon;
    final c = _mapController;
    if (lat != null && lon != null && c != null) {
      unawaited(
        c.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lon), _myLocationZoom),
        ),
      );
    }
    try {
      final allAcked = await _sos.acknowledge(event.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allAcked
                ? AppStrings.sosAcknowledgedAllDone
                : AppStrings.sosAcknowledged,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosAckError)),
      );
    }
  }

  Widget? _buildSosBanner() {
    final visible = _activeSos.where((e) {
      if (e.userId == _myUid) return true;
      return !_isSosHiddenLocally(e);
    }).toList();
    if (visible.isEmpty) return null;
    final event = visible.first;
    final isSelf = event.userId == _myUid;
    final senderName = _sosSenderLabel(event);
    final progress =
        isSelf && _sosAckProgress?.sosId == event.id ? _sosAckProgress : null;
    final pendingNames =
        progress?.pendingPeers.map((m) => m.displayName).toList() ?? const [];
    final acked = progress?.ackedCount ?? 0;
    final expected = progress?.expectedCount ?? 0;

    return Material(
      color: AppColors.accentRed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSelf
                        ? AppStrings.sosBannerSelfNamed(senderName)
                        : AppStrings.sosBannerPeer(senderName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (isSelf) ...[
              const SizedBox(height: 6),
              Text(
                expected == 0
                    ? AppStrings.sosAckNoPeers
                    : pendingNames.isEmpty
                        ? AppStrings.sosAckWaitingResolve
                        : AppStrings.sosAckPendingList(
                            acked,
                            expected,
                            pendingNames,
                          ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => unawaited(_cancelOwnSos(event)),
                  child: const Text(
                    AppStrings.sosBannerDismissOwn,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.accentRed,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => unawaited(_acceptSosPeer(event)),
                child: const Text(
                  AppStrings.sosBannerAck,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
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
        // Franja superior (siempre): grupo + ampliar + chat + refresh.
        Material(
          color: Colors.white,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text(
                    AppStrings.mapGroupSelector,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _groupsList.isEmpty
                        ? Text(
                            AppStrings.mapNoGroup,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                      child: Text(
                                        g.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _onSelectGroup,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: _mapExpanded
                        ? AppStrings.mapCollapseTooltip
                        : AppStrings.mapExpandTooltip,
                    onPressed: () {
                      setState(() => _mapExpanded = !_mapExpanded);
                    },
                    icon: Icon(
                      _mapExpanded
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                  ),
                  IconButton(
                    tooltip: AppStrings.chatAction,
                    onPressed: () {
                      final group = _selected;
                      if (group == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(AppStrings.chatNeedGroup),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupChatScreen(group: group),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
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
          flex: _mapExpanded ? 1 : 3,
          child: _buildMapPane(context),
        ),
        if (!_mapExpanded)
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
                                final isSelf =
                                    m.userId.trim().toLowerCase() == _myUid &&
                                        _myUid.isNotEmpty;
                                return MemberCard(
                                  name: m.label,
                                  photoUrl: m.photoUrl,
                                  isSelf: isSelf,
                                  shareStatusLabel: _shareFor(m),
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
                                  onMessage: isSelf
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => DirectChatScreen(
                                                peerUserId: m.userId,
                                                peerName: m.label,
                                                peerPhotoUrl: m.photoUrl,
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
