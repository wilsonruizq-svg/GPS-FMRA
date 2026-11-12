import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../places/named_places_service.dart';
import '../groups_service.dart';
import 'accept_invite_screen.dart';
import 'group_detail_screen.dart';

/// Lista de grupos + ubicaciones. Misma idea que el Mapa: Column/Expanded
/// (sin Stack/Scaffold anidado → evita body altura 0).
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  GroupsScreenState createState() => GroupsScreenState();
}

class GroupsScreenState extends State<GroupsScreen>
    with AutomaticKeepAliveClientMixin {
  final _service = GroupsService();
  final _places = NamedPlacesService();

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groups = const [];
  List<NamedPlace> _soloPlaces = const [];
  final Map<String, List<PlaceCategory>> _catsByGroup = {};
  final Map<String, List<NamedPlace>> _placesByGroup = {};
  final Map<String, bool> _sectionLoading = {};

  /// Para FAB del AppShell.
  bool get isLoading => _loading;
  int get groupCount => _groups.length;
  bool get isEmpty => !_loading && _error == null && _groups.isEmpty;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
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
      var solo = const <NamedPlace>[];
      try {
        solo = await _places.listSoloMine();
      } catch (e) {
        debugPrint('listSoloMine: $e');
      }
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _soloPlaces = solo;
        _loading = false;
      });
      for (final g in groups) {
        unawaited(_loadSection(g.id));
      }
    } catch (e, st) {
      debugPrint('GroupsScreen._refresh ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSection(String groupId) async {
    if (!mounted) return;
    setState(() => _sectionLoading[groupId] = true);
    var cats = const <PlaceCategory>[];
    var places = const <NamedPlace>[];
    try {
      places = await _places.listForGroup(groupId);
    } catch (e) {
      debugPrint('listForGroup($groupId): $e');
    }
    try {
      cats = await _places.listCategories(groupId);
    } catch (e) {
      debugPrint('listCategories($groupId): $e');
    }
    if (!mounted) return;
    setState(() {
      _placesByGroup[groupId] = places;
      _catsByGroup[groupId] = cats;
      _sectionLoading[groupId] = false;
    });
  }

  Future<void> _createCategory(FamilyGroup group) async {
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
      await _loadSection(group.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _deletePlace(FamilyGroup group, NamedPlace place) async {
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
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _deleteCategory(FamilyGroup group, PlaceCategory cat) async {
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
      await _loadSection(group.id);
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

  Widget _placeCard(FamilyGroup group, NamedPlace place) {
    final url = _places.publicPhotoUrl(place.photoPath);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const SizedBox(
                    height: 72,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            )
          else
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const SizedBox(
                height: 56,
                child: Center(child: Icon(Icons.place_outlined)),
              ),
            ),
          ListTile(
            dense: true,
            title: Text(
              place.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              (place.description == null || place.description!.isEmpty)
                  ? '${place.lat.toStringAsFixed(5)}, ${place.lon.toStringAsFixed(5)}'
                  : place.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: AppStrings.groupsPlacesDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_deletePlace(group, place)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationsBelowGroup(FamilyGroup group, {required bool showSolo}) {
    final loading = _sectionLoading[group.id] == true;
    final cats = _catsByGroup[group.id] ?? const <PlaceCategory>[];
    final places = _placesByGroup[group.id] ?? const <NamedPlace>[];
    final uncategorized = places
        .where((p) => p.categoryId == null || p.categoryId!.trim().isEmpty)
        .toList();
    final categorized = places
        .where((p) => p.categoryId != null && p.categoryId!.trim().isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.groupsPlacesSharedTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_createCategory(group)),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text(AppStrings.groupsCategoryCreateAction),
              ),
            ],
          ),
          if (loading && cats.isEmpty && places.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (cats.isEmpty && places.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                AppStrings.groupsPlacesEmpty,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(cat.name),
                  subtitle: Text(
                    AppStrings.groupsCategoryPlaceCount(
                      categorized.where((p) => p.categoryId == cat.id).length,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () =>
                            unawaited(_deleteCategory(group, cat)),
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
                            _placeCard(group, p),
                          if (categorized
                              .where((p) => p.categoryId == cat.id)
                              .isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                AppStrings.groupsCategoryEmpty,
                                style: Theme.of(context).textTheme.bodySmall,
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
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              for (final p in uncategorized) _placeCard(group, p),
            ],
          ],
          if (showSolo) ...[
            const SizedBox(height: 16),
            Text(
              AppStrings.groupsPlacesSoloTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.groupsPlacesSoloHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            if (_soloPlaces.isEmpty)
              Text(
                'Ninguno aún.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final p in _soloPlaces) _placeCard(group, p),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupBlock(FamilyGroup group, {required bool showSolo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(
              Icons.family_restroom,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            group.name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
          ),
          subtitle: const Text(AppStrings.groupsTapMembers),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupDetailScreen(group: group),
              ),
            );
            await _refresh();
          },
        ),
        _locationsBelowGroup(group, showSolo: showSolo),
      ],
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
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _buildGroupBlock(_groups[i], showSolo: i == 0),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            AppStrings.groupsAlreadyMemberHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Igual que MapShellScreen: Column llena el body del AppShell.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Franja siempre visible → confirma que el body tiene altura.
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _loading
                  ? 'Cargando grupos…'
                  : _error != null
                      ? 'Error al cargar grupos'
                      : 'Mis grupos (${_groups.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _buildScrollBody(),
          ),
        ),
      ],
    );
  }
}
