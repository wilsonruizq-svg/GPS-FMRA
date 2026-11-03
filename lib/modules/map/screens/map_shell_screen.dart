import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../../groups/widgets/member_card.dart';
import '../../location/consent_service.dart';

/// Shell del mapa: MapLibre (estilo libre / MapTiler) + lista de integrantes.
/// Los pines de familiares quedan stub (coords en tiempo real: GPS-18).
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

  final _groups = GroupsService();
  final _consent = ConsentService();

  MapLibreMapController? _mapController;
  bool _styleReady = false;
  bool _didAutoCenter = false;
  bool _locating = false;
  bool _osLocationGranted = false;

  /// Cámara inicial resuelta (GPS o fallback). Null = aún obteniendo ubicación.
  CameraPosition? _initialCamera;
  bool _cameraResolved = false;

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groupsList = const [];
  FamilyGroup? _selected;
  List<GroupMember> _members = const [];
  LocationConsent? _myConsent;

  @override
  void initState() {
    super.initState();
    // Permiso + GPS en paralelo al cargar grupos; el mapa espera la cámara.
    _resolveInitialCamera();
    _load();
  }

  @override
  void dispose() {
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
          // lastKnown es inmediato; currentPosition refuerza si hace falta.
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
      // Reselect by id from the fresh list so DropdownButton value ∈ items.
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
      if (selected != null) {
        members = await _groups.listMembers(selected.id);
        final consents = await _consent.listOwnGroupConsents();
        mine = consents.cast<LocationConsent?>().firstWhere(
              (c) => c?.groupId == selected!.id,
              orElse: () => null,
            );
      }
      if (!mounted) return;
      setState(() {
        _groupsList = groups;
        _selected = selected;
        _members = members;
        _myConsent = mine;
        _loading = false;
      });
      _maybeAutoCenter();
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
      final consents = await _consent.listOwnGroupConsents();
      final mine = consents.cast<LocationConsent?>().firstWhere(
            (c) => c?.groupId == group.id,
            orElse: () => null,
          );
      if (!mounted) return;
      setState(() {
        _members = members;
        _myConsent = mine;
      });
      _maybeAutoCenter();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  String _shareFor(GroupMember m) {
    // Stub: solo sabemos el consentimiento propio con detalle.
    if (_myConsent != null &&
        _myConsent!.isActive &&
        m.userId == _myConsent!.sharerId) {
      return AppStrings.memberShareActive;
    }
    return AppStrings.memberShareUnknown;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoaded() {
    _styleReady = true;
    // Stub de pines: GPS-18 añadirá GeoJSON / anotaciones vía controller.
    _maybeAutoCenter();
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
          // Punto azul: con consentimiento activo o permiso OS concedido.
          myLocationEnabled: showMyLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          trackCameraPosition: false,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
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
                                shareStatusLabel: _shareFor(m),
                                lastUpdateLabel:
                                    AppStrings.memberLastUpdateUnknown,
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }
}
