import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../places/named_places_service.dart';
import '../groups_service.dart';
import 'accept_invite_screen.dart';
import 'group_detail_screen.dart';

/// Pestaña Grupos:
/// - Filas de grupo → tap abre GroupDetail (miembros + invitaciones), como 94d85b4.
/// - Debajo: lista compartida de UBICACIONES + buscador fijo abajo.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  GroupsScreenState createState() => GroupsScreenState();
}

class GroupsScreenState extends State<GroupsScreen> {
  final _service = GroupsService();
  final _places = NamedPlacesService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _placesLoading = false;
  String? _error;
  List<FamilyGroup> _groups = const [];
  List<NamedPlace> _sharedPlaces = const [];
  List<PlaceCategory> _sharedCats = const [];
  String _query = '';

  bool get isLoading => _loading;
  int get groupCount => _groups.length;
  bool get isEmpty => !_loading && _error == null && _groups.isEmpty;
  String? get firstGroupName =>
      _groups.isEmpty ? null : _groups.first.name;

  FamilyGroup? get _primaryGroup =>
      _groups.isEmpty ? null : _groups.first;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> reload() => _refresh();

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _service.listMyGroups();
      debugPrint('GroupsScreen: listMyGroups → ${groups.length}');
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
      await _loadSharedPlaces(groups);
    } catch (e, st) {
      debugPrint('GroupsScreen._refresh ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Une lugares de todos los grupos + Solo yo (sin SQL nuevo).
  Future<void> _loadSharedPlaces(List<FamilyGroup> groups) async {
    if (!mounted) return;
    setState(() => _placesLoading = true);
    final byId = <String, NamedPlace>{};
    final cats = <PlaceCategory>[];
    final seenCat = <String>{};

    for (final g in groups) {
      try {
        final places = await _places.listForGroup(g.id);
        for (final p in places) {
          byId[p.id] = p;
        }
      } catch (e) {
        debugPrint('listForGroup(${g.id}): $e');
      }
      try {
        final list = await _places.listCategories(g.id);
        for (final c in list) {
          if (seenCat.add(c.id)) cats.add(c);
        }
      } catch (e) {
        debugPrint('listCategories(${g.id}): $e');
      }
    }
    try {
      final solo = await _places.listSoloMine();
      for (final p in solo) {
        byId[p.id] = p;
      }
    } catch (e) {
      debugPrint('listSoloMine: $e');
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _sharedPlaces = merged;
      _sharedCats = cats;
      _placesLoading = false;
    });
  }

  Future<void> _openGroupDetail(FamilyGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(group: group),
      ),
    );
    await _refresh();
  }

  Future<void> _createCategory() async {
    final group = _primaryGroup;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea o únete a un grupo primero.')),
      );
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
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
          maxLength: 60,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(AppStrings.groupsCategoryCreateAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await _places.createCategory(groupId: group.id, name: name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.groupsCategoryCreated(name))),
      );
      await _loadSharedPlaces(_groups);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _deletePlace(NamedPlace place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.groupsPlacesDelete),
        content: Text(
          '${AppStrings.groupsPlacesDeleteConfirm}\n\n«${place.name}»',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.groupsPlacesDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _places.delete(place.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.groupsPlacesDeleted)),
      );
      await _loadSharedPlaces(_groups);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _deleteCategory(PlaceCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.groupsCategoryDelete),
        content: Text(AppStrings.groupsCategoryDeleteConfirm(cat.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.groupsCategoryDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _places.deleteCategory(cat.id);
      if (!mounted) return;
      await _loadSharedPlaces(_groups);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(AppStrings.groupsCreateTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: AppStrings.groupsNameLabel,
              hintText: AppStrings.groupsNameHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(AppStrings.groupsCreateAction),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final group = await _service.createGroup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.groupsCreatedPrefix} ${group.name}'),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _joinWithCode() async {
    final result = await Navigator.of(context).push<AcceptInviteResult>(
      MaterialPageRoute(builder: (_) => const AcceptInviteScreen()),
    );
    if (result == null) return;
    await _refresh();
  }

  List<NamedPlace> get _filteredPlaces {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sharedPlaces;
    return _sharedPlaces.where((p) {
      final name = p.name.toLowerCase();
      final desc = (p.description ?? '').toLowerCase();
      final coords =
          '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';
      return name.contains(q) || desc.contains(q) || coords.contains(q);
    }).toList();
  }

  String? _categoryName(NamedPlace place) {
    final id = place.categoryId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final c in _sharedCats) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  Widget _placeCard(NamedPlace place) {
    final url = _places.publicPhotoUrl(place.photoPath);
    final cat = _categoryName(place);
    final detail = (place.description == null || place.description!.isEmpty)
        ? '${place.lat.toStringAsFixed(5)}, ${place.lon.toStringAsFixed(5)}'
        : place.description!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE8EEF4),
                  child: SizedBox(
                    height: 72,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            )
          else
            const ColoredBox(
              color: Color(0xFFE8EEF4),
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Icon(Icons.place_outlined, color: AppColors.midBlue),
                ),
              ),
            ),
          ListTile(
            dense: true,
            title: Text(
              place.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.deepBlue,
              ),
            ),
            subtitle: Text(
              cat == null ? detail : '$cat · $detail',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.midBlue),
            ),
            trailing: IconButton(
              tooltip: AppStrings.groupsPlacesDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
              onPressed: () => unawaited(_deletePlace(place)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sharedPlacesSection() {
    final places = _filteredPlaces;
    final cats = _sharedCats;
    final categorized = places
        .where((p) => p.categoryId != null && p.categoryId!.trim().isNotEmpty)
        .toList();
    final uncategorized = places
        .where((p) => p.categoryId == null || p.categoryId!.trim().isEmpty)
        .toList();

    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    AppStrings.groupsPlacesTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.deepBlue,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _createCategory,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text(AppStrings.groupsCategoryCreateAction),
                ),
              ],
            ),
            const Text(
              'Compartidas para todos tus grupos (y Solo yo).',
              style: TextStyle(fontSize: 12, color: AppColors.midBlue),
            ),
            const SizedBox(height: 8),
            if (_placesLoading && _sharedPlaces.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (places.isEmpty && cats.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  _query.trim().isEmpty
                      ? AppStrings.groupsPlacesEmpty
                      : AppStrings.groupsPlacesSearchEmpty,
                  style: const TextStyle(color: AppColors.midBlue),
                ),
              )
            else ...[
              for (final cat in cats)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: ValueKey('cat_${cat.id}'),
                    initiallyExpanded: true,
                    leading: const Icon(
                      Icons.folder_outlined,
                      color: AppColors.deepBlue,
                    ),
                    title: Text(
                      cat.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.deepBlue,
                      ),
                    ),
                    subtitle: Text(
                      AppStrings.groupsCategoryPlaceCount(
                        categorized
                            .where((p) => p.categoryId == cat.id)
                            .length,
                      ),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => unawaited(_deleteCategory(cat)),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text(AppStrings.groupsCategoryDelete),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Column(
                          children: [
                            for (final p in categorized.where(
                              (p) => p.categoryId == cat.id,
                            ))
                              _placeCard(p),
                            if (categorized
                                .where((p) => p.categoryId == cat.id)
                                .isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  AppStrings.groupsCategoryEmpty,
                                  style: TextStyle(color: AppColors.midBlue),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (uncategorized.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  AppStrings.groupsPlacesUncategorized,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.deepBlue,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                for (final p in uncategorized) _placeCard(p),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Como 94d85b4: tap abre GroupDetail (miembros + invitaciones de vinculación).
  Widget _buildGroupBlock(FamilyGroup group) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: InkWell(
        onTap: () => unawaited(_openGroupDetail(group)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.deepBlue.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.family_restroom,
                  color: AppColors.deepBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.deepBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.groupsTapMembers,
                      style: const TextStyle(
                        color: AppColors.midBlue,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.deepBlue,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('Cargando grupos…')),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _refresh,
            child: const Text(AppStrings.retry),
          ),
        ],
      );
    }
    if (_groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 120),
        children: [
          Icon(
            Icons.groups_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.groupsEmpty,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _createGroup,
            icon: const Icon(Icons.add),
            label: const Text(AppStrings.groupsCreateAction),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _joinWithCode,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text(AppStrings.groupsJoinAction),
          ),
          const SizedBox(height: 24),
          _sharedPlacesSection(),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      children: [
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildGroupBlock(_groups[i]),
        ],
        const SizedBox(height: 12),
        // Lista compartida debajo de los nombres de grupo.
        _sharedPlacesSection(),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            AppStrings.groupsAlreadyMemberHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.midBlue,
                ),
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: AppStrings.groupsPlacesSearchHint,
              prefixIcon: const Icon(Icons.search, color: AppColors.deepBlue),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AppStrings.cancel,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = firstGroupName;
    final header = _loading
        ? 'Cargando grupos…'
        : _error != null
            ? 'Error al cargar grupos'
            : (first == null
                ? 'Mis grupos (${_groups.length})'
                : 'Mis grupos (${_groups.length}) · $first');

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                header,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.deepBlue,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.deepBlue,
              onRefresh: _refresh,
              child: _buildScrollBody(),
            ),
          ),
          // Buscador fijo abajo: filtra la lista compartida de ubicaciones.
          if (!_loading && _error == null) _searchBar(),
        ],
      ),
    );
  }
}
