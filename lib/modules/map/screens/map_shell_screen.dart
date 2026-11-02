import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../../groups/widgets/member_card.dart';
import '../../location/consent_service.dart';

/// Shell del mapa: GoogleMap si hay clave; si no, placeholder + lista de integrantes.
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
    if (Env.hasMapsConfig) {
      return GoogleMap(
        initialCameraPosition: _fallbackCamera,
        mapType: MapType.normal,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
        compassEnabled: true,
        // Ubicación del dispositivo: el permiso se pide en la pantalla de
        // consentimiento; si aún no hay permiso, el SDK lo ignora.
        myLocationEnabled: _myConsent?.isActive == true,
      );
    }

    return ColoredBox(
      color: AppColors.midBlue.withValues(alpha: 0.08),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 220;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.midBlue.withValues(alpha: 0.15),
                  AppColors.signalCyan.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                overscroll: false,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: compact ? 12 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (compact ? 24 : 40),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: compact ? 40 : 56,
                        color: AppColors.deepBlue.withValues(alpha: 0.7),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      Text(
                        AppStrings.mapPlaceholderTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppStrings.mapPlaceholderBody,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.mapMissingKeyHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
