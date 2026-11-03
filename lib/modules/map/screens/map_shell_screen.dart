import 'dart:async';
import 'dart:math' as math;

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
import '../../location/location_share_service.dart';

/// Shell del mapa: MapLibre + pines de integrantes con consentimiento activo.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key});

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

class _MapShellScreenState extends State<MapShellScreen> {
  /// Bogotá — solo si no hay GPS disponible al abrir el mapa.
  static const _fallbackCamera = CameraPosition(
    target: LatLng(4.7110, -74.0721),
    zoom: 11,
  );

  static const _myLocationZoom = 15.0;
  static const _publishInterval = Duration(seconds: 20);
  static const _pollInterval = Duration(seconds: 25);

  final _groups = GroupsService();
  final _consent = ConsentService();
  final _locationShare = LocationShareService();

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
  final Map<String, Symbol> _labelsByUser = {};

  Timer? _publishTimer;
  Timer? _pollTimer;
  RealtimeChannel? _realtimeChannel;
  bool _publishing = false;
  bool _syncingMarkers = false;
  bool _markersDirty = false;
  bool _didFitMembers = false;

  @override
  void initState() {
    super.initState();
    _resolveInitialCamera();
    _load();
  }

  @override
  void dispose() {
    _stopSharingLoop();
    _unsubscribeRealtime();
    _mapController = null;
    super.dispose();
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

  void _stopSharingLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _unsubscribeRealtime() {
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch != null) {
      unawaited(supabase.removeChannel(ch));
    }
  }

  void _restartSharingLoop() {
    _publishTimer?.cancel();
    _publishTimer = null;
    final group = _selected;
    if (group == null || _myConsent?.isActive != true) return;

    unawaited(_publishOnce());
    _publishTimer = Timer.periodic(_publishInterval, (_) {
      unawaited(_publishOnce());
    });
  }

  void _restartRealtimeAndPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _unsubscribeRealtime();

    if (_selected == null || _members.isEmpty) return;

    try {
      _realtimeChannel = _locationShare.subscribeLocationUpdates(
        onChange: (loc) {
          if (!mounted) return;
          final memberIds = _members.map((m) => m.userId).toSet();
          if (!memberIds.contains(loc.userId)) return;
          setState(() {
            _locationsByUser = Map<String, MemberLocation>.from(_locationsByUser)
              ..[loc.userId] = loc;
          });
          unawaited(_syncMarkers());
        },
        onDelete: (userId) {
          if (!mounted) return;
          setState(() {
            _locationsByUser = Map<String, MemberLocation>.from(_locationsByUser)
              ..remove(userId);
          });
          unawaited(_syncMarkers());
        },
      );
    } catch (_) {
      // Fallback: solo polling.
    }

    unawaited(_refreshMemberLocations());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_refreshMemberLocations());
    });
  }

  Future<void> _publishOnce() async {
    if (_publishing) return;
    final group = _selected;
    if (group == null) return;
    _publishing = true;
    try {
      final allowed = await _locationShare.canPublishForGroup(group.id);
      if (!allowed) return;

      final granted = await _ensureOsPermission(
        requestIfNeeded: false,
        showFeedback: false,
      );
      if (!granted) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _locationShare.publishPosition(pos);

      if (!mounted) return;
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
      await _syncMarkers();
    } catch (_) {
      // Silencioso: no romper UI si falla un ciclo de publicación.
    } finally {
      _publishing = false;
    }
  }

  Future<void> _refreshMemberLocations() async {
    if (_members.isEmpty) return;
    try {
      final locations = await _fetchLocationsMap(_members);
      if (!mounted) return;
      setState(() => _locationsByUser = locations);
      await _syncMarkers();
    } catch (_) {
      // Silencioso en poll.
    }
  }

  /// Separa pines casi coincidentes (~misma habitación) para que no se vean
  /// como un solo punto.
  Map<String, LatLng> _displayPositions(Map<String, MemberLocation> desired) {
    final entries = desired.entries.toList();
    final out = <String, LatLng>{
      for (final e in entries) e.key: LatLng(e.value.lat, e.value.lon),
    };
    const mergeMeters = 25.0;
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i].value;
        final b = entries[j].value;
        final dist = Geolocator.distanceBetween(a.lat, a.lon, b.lat, b.lon);
        if (dist >= mergeMeters) continue;
        // Desplaza el segundo ~35 m al NE en grados aprox.
        final angle = (j * 2.2) % (2 * math.pi);
        final dLat = (35 / 111320) * math.cos(angle);
        final dLon =
            (35 / (111320 * math.cos(b.lat * math.pi / 180).clamp(0.2, 1.0))) *
                math.sin(angle);
        out[entries[j].key] = LatLng(b.lat + dLat, b.lon + dLon);
      }
    }
    return out;
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
      final desired = Map<String, MemberLocation>.from(_locationsByUser);
      final display = _displayPositions(desired);

      // Quitar marcadores obsoletos.
      final stale = _circlesByUser.keys
          .where((id) => !desired.containsKey(id))
          .toList();
      for (final id in stale) {
        final circle = _circlesByUser.remove(id);
        final label = _labelsByUser.remove(id);
        if (circle != null) {
          try {
            await controller.removeCircle(circle);
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
        final geometry = display[userId]!;
        final isSelf = userId == _myUid;
        final color = isSelf ? '#4DB6D4' : '#C62828';
        final label = nameById[userId] ??
            (isSelf ? AppStrings.mapMarkerYou : AppStrings.mapMarkerMember);

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
          trackCameraPosition: false,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: () {
            unawaited(_onStyleLoaded());
          },
        ),
        Positioned(
          right: 12,
          bottom: 56,
          child: FloatingActionButton.small(
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
