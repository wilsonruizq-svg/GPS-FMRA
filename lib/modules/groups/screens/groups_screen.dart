import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../places/named_places_service.dart';
import '../groups_service.dart';
import 'accept_invite_screen.dart';
import 'group_detail_screen.dart';

/// Lista de grupos familiares. Debajo de cada grupo: categorías/carpetas
/// de ubicaciones (restaurantes, negocios…) con foto — no en el detalle.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _service = GroupsService();
  final _places = NamedPlacesService();
  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groups = const [];
  final Map<String, List<PlaceCategory>> _catsByGroup = {};
  final Map<String, List<NamedPlace>> _placesByGroup = {};
  final Map<String, bool> _sectionLoading = {};
  final Set<String> _openCats = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _service.listMyGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
      for (final g in groups) {
        unawaited(_loadSection(g.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSection(String groupId) async {
    setState(() => _sectionLoading[groupId] = true);
    try {
      final cats = await _places.listCategories(groupId);
      final places = await _places.listForGroup(groupId);
      if (!mounted) return;
      setState(() {
        _catsByGroup[groupId] = cats;
        _placesByGroup[groupId] = places;
        _sectionLoading[groupId] = false;
      });
    } catch (e) {
      debugPrint('group places section: $e');
      if (!mounted) return;
      setState(() {
        _catsByGroup[groupId] ??= const [];
        _placesByGroup[groupId] ??= const [];
        _sectionLoading[groupId] = false;
      });
    }
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
      await _loadSection(group.id);
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

    if (name == null || name.isEmpty) return;

    try {
      final group = await _service.createGroup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.groupsCreatedPrefix} ${group.name}')),
      );
      await _refresh();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupDetailScreen(group: group),
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
      MaterialPageRoute(
        builder: (_) => const AcceptInviteScreen(),
      ),
    );
    if (result == null) return;
    await _refresh();
    if (!mounted) return;
    final match = _groups.where((g) => g.id == result.groupId);
    if (match.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(group: match.first),
      ),
    );
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
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
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

  /// Bloque DEBAJO del grupo familiar (misma pestaña lista, no detalle).
  Widget _locationsBelowGroup(FamilyGroup group) {
    final loading = _sectionLoading[group.id] == true;
    final cats = _catsByGroup[group.id] ?? const <PlaceCategory>[];
    final places = _placesByGroup[group.id] ?? const <NamedPlace>[];
    final uncategorized =
        places.where((p) => p.categoryId == null || p.categoryId!.isEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.groupsPlacesTitle,
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
              child: Center(child: CircularProgressIndicator()),
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
              ExpansionTile(
                key: PageStorageKey('cat_${cat.id}'),
                initiallyExpanded: _openCats.contains(cat.id),
                onExpansionChanged: (open) {
                  setState(() {
                    if (open) {
                      _openCats.add(cat.id);
                    } else {
                      _openCats.remove(cat.id);
                    }
                  });
                },
                leading: const Icon(Icons.folder_outlined),
                title: Text(cat.name),
                subtitle: Text(
                  AppStrings.groupsCategoryPlaceCount(
                    places.where((p) => p.categoryId == cat.id).length,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => unawaited(_deleteCategory(group, cat)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text(AppStrings.groupsCategoryDelete),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      children: [
                        for (final p in places.where(
                          (p) => p.categoryId == cat.id,
                        ))
                          _placeCard(group, p),
                        if (places.where((p) => p.categoryId == cat.id).isEmpty)
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
        ],
      ),
    );
  }

  Widget _buildGroupBlock(FamilyGroup group) {
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
        // Ubicaciones / categorías: DEBAJO en esta misma pantalla.
        _locationsBelowGroup(group),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showCreateJoinFab = !_loading && _error == null && _groups.isEmpty;

    return Scaffold(
      floatingActionButton: showCreateJoinFab
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'join_invite',
                  onPressed: _joinWithCode,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text(AppStrings.groupsJoinAction),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'create_group',
                  onPressed: _createGroup,
                  icon: const Icon(Icons.add),
                  label: const Text(AppStrings.groupsCreateAction),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text(AppStrings.retry),
                      ),
                    ],
                  )
                : _groups.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(28, 48, 28, 140),
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
                          const SizedBox(height: 8),
                          Text(
                            AppStrings.groupsEmptyCreateHint,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _joinWithCode,
                            icon: const Icon(Icons.vpn_key_outlined),
                            label: const Text(AppStrings.groupsJoinAction),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppStrings.groupsEmptyJoinHint,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (var i = 0; i < _groups.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _buildGroupBlock(_groups[i]),
                          ],
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              AppStrings.groupsAlreadyMemberHint,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
