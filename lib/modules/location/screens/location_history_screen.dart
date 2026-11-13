import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../../map/map_place_focus.dart';
import '../location_share_service.dart';

/// Lista mínima de historial GPS del grupo (consent-first vía RLS/RPC).
class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({super.key});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final _groups = GroupsService();
  final _locations = LocationShareService();

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groupsList = const [];
  FamilyGroup? _selected;
  List<HistoryPoint> _points = const [];

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
      final selected = _selected != null
          ? groups.cast<FamilyGroup?>().firstWhere(
                (g) => g?.id == _selected!.id,
                orElse: () => groups.isNotEmpty ? groups.first : null,
              )
          : (groups.isNotEmpty ? groups.first : null);
      List<HistoryPoint> points = const [];
      if (selected != null) {
        points = await _locations.fetchGroupHistory(groupId: selected.id);
      }
      if (!mounted) return;
      setState(() {
        _groupsList = groups;
        _selected = selected;
        _points = points;
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

  Future<void> _onSelect(FamilyGroup? g) async {
    if (g == null) return;
    setState(() {
      _selected = g;
      _loading = true;
    });
    try {
      final points = await _locations.fetchGroupHistory(groupId: g.id);
      if (!mounted) return;
      setState(() {
        _points = points;
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

  String _fmt(DateTime utc) {
    final local = utc.toLocal();
    final d =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  void _openPointOnMap(HistoryPoint p) {
    MapPlaceFocus.request(
      MapPlaceFocusRequest(
        lat: p.lat,
        lon: p.lon,
        placeId: 'history:${p.id}',
        name: p.label,
      ),
    );
    // Historial está encima de AppShell: volver y dejar que AppShell → Mapa.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.historyTitle)),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
                            style: Theme.of(context).textTheme.bodyMedium,
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
                              onChanged: _onSelect,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              AppStrings.historyConsentNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.midBlue,
                  ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    : _points.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                AppStrings.historyEmpty,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _points.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = _points[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.deepBlue
                                      .withValues(alpha: 0.1),
                                  child: const Icon(
                                    Icons.place_outlined,
                                    color: AppColors.deepBlue,
                                  ),
                                ),
                                title: Text(
                                  p.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.deepBlue,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_fmt(p.recordedAt)}  ·  '
                                  '${p.lat.toStringAsFixed(5)}, '
                                  '${p.lon.toStringAsFixed(5)}',
                                ),
                                onTap: () => _openPointOnMap(p),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
