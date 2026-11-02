import 'package:flutter/material.dart';
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
  /// Bogotá — centro inicial hasta que haya ubicaciones de miembros.
  static const _fallbackCamera = CameraPosition(
    target: LatLng(4.7110, -74.0721),
    zoom: 11,
  );

  final _groups = GroupsService();
  final _consent = ConsentService();

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groupsList = const [];
  FamilyGroup? _selected;
  List<GroupMember> _members = const [];
  LocationConsent? _myConsent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _groups.listMyGroups();
      FamilyGroup? selected = _selected;
      if (selected == null || !groups.any((g) => g.id == selected!.id)) {
        selected = groups.isNotEmpty ? groups.first : null;
      }
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

  Widget _buildMapPane(BuildContext context) {
    final styleUrl = Env.mapStyleUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        MapLibreMap(
          styleString: styleUrl,
          initialCameraPosition: _fallbackCamera,
          compassEnabled: true,
          // Ubicación del dispositivo: el permiso se pide en consentimiento.
          myLocationEnabled: _myConsent?.isActive == true,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          trackCameraPosition: false,
          onStyleLoadedCallback: () {
            // Stub de pines: GPS-18 añadirá GeoJSON / anotaciones vía controller.
          },
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
