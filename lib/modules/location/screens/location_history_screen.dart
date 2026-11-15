import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../../map/map_place_focus.dart';
import '../location_share_service.dart';

/// Puntos recientes por grupo.
/// Entrada discreta (mapa/grupo) — no Ajustes (GF-38).
/// Admin: selector de integrante. Miembro: solo propio.
class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({
    super.key,
    this.initialGroup,
    this.initialUserId,
  });

  final FamilyGroup? initialGroup;
  /// Si admin abre desde tap a un integrante.
  final String? initialUserId;

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
  List<GroupMember> _members = const [];
  GroupMember? _focusMember;
  bool _iAmAdmin = false;
  List<HistoryPoint> _points = const [];

  String get _myUid => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initialGroup;
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

      List<GroupMember> members = const [];
      var iAmAdmin = false;
      GroupMember? focus;
      List<HistoryPoint> points = const [];

      if (selected != null) {
        members = await _groups.listMembers(selected.id);
        final me = members.where((m) => m.userId == _myUid).firstOrNull;
        iAmAdmin = me?.isAdmin == true;

        final wantId = (widget.initialUserId ?? '').trim();
        final wantPeer =
            wantId.isNotEmpty &&
            wantId.toLowerCase() != _myUid.trim().toLowerCase();
        if (iAmAdmin && wantId.isNotEmpty) {
          focus = members.where((m) => m.userId == wantId).firstOrNull;
        } else if (wantPeer) {
          // Miembro no admin: nunca abrir historial ajeno (GF-39/40).
          focus = me;
        }
        focus ??= me ?? (members.isNotEmpty ? members.first : null);

        if (focus != null) {
          points = await _locations.fetchMemberHistory(
            groupId: selected.id,
            userId: focus.userId,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _groupsList = groups;
        _selected = selected;
        _members = members;
        _iAmAdmin = iAmAdmin;
        _focusMember = focus;
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

  Future<void> _reloadPoints() async {
    final g = _selected;
    final m = _focusMember;
    if (g == null || m == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final points = await _locations.fetchMemberHistory(
        groupId: g.id,
        userId: m.userId,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _loading = false;
      });
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('list_member_location_history') ||
        s.contains('PGRST202') ||
        s.contains('Could not find the function')) {
      return AppStrings.historyNeedAdminSql;
    }
    return s;
  }

  Future<void> _onSelectGroup(FamilyGroup? g) async {
    if (g == null) return;
    setState(() {
      _selected = g;
      _focusMember = null;
    });
    await _load();
  }

  Future<void> _onSelectMember(GroupMember? m) async {
    if (m == null) return;
    setState(() => _focusMember = m);
    await _reloadPoints();
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
              child: Column(
                children: [
                  Row(
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
                                  // ignore: deprecated_member_use
                                  value: _selected,
                                  items: _groupsList
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(g.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _loading ? null : _onSelectGroup,
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
                  if (_iAmAdmin && _members.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          AppStrings.historyMemberLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<GroupMember>(
                              isExpanded: true,
                              // ignore: deprecated_member_use
                              value: _focusMember,
                              items: _members
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m.userId == _myUid
                                            ? '${m.label} ${AppStrings.memberYouSuffix}'
                                            : m.label,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _loading ? null : _onSelectMember,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
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
                                  style: const TextStyle(
                                    color: AppColors.midBlue,
                                    fontSize: 14,
                                  ),
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
