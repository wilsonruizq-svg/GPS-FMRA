import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../places/named_places_service.dart';
import '../groups_service.dart';
import 'accept_invite_screen.dart';
import 'group_detail_screen.dart';

/// Lista de grupos = exactamente 94d85b4 (ListTile → GroupDetail).
/// Fuera, debajo: «Ubicaciones guardadas» + buscador abajo.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, this.onOpenPlaceOnMap});

  /// Tap en el título de un lugar → AppShell cambia a Mapa y centra.
  final void Function(NamedPlace place)? onOpenPlaceOnMap;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _service = GroupsService();
  final _places = NamedPlacesService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _placesLoading = false;
  String? _error;
  List<FamilyGroup> _groups = const [];
  List<NamedPlace> _sharedPlaces = const [];
  List<PlaceCategory> _categories = const [];
  /// null = todas; '' = sin categoría; id = carpeta.
  String? _categoryFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      unawaited(_loadSharedPlaces(groups));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSharedPlaces(List<FamilyGroup> groups) async {
    if (!mounted) return;
    setState(() => _placesLoading = true);
    final byId = <String, NamedPlace>{};
    final catsById = <String, PlaceCategory>{};
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
        final cats = await _places.listCategories(g.id);
        for (final c in cats) {
          catsById[c.id] = c;
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
    final cats = catsById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _sharedPlaces = merged;
      _categories = cats;
      _placesLoading = false;
    });
  }

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

  Future<void> _waitAfterDialogClosed() async {
    await _waitFrames(3);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await _waitFrames(1);
  }

  Future<void> _createCategoryQuickAdd() async {
    if (_groups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.mapSavePlaceNeedGroup)),
      );
      return;
    }
    var groupId = _groups.first.id;
    if (_groups.length > 1) {
      final picked = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => SimpleDialog(
          title: const Text(AppStrings.groupsCategoryCreateTitle),
          children: [
            for (final g in _groups)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(ctx, rootNavigator: true).pop(g.id),
                child: Text(g.name),
              ),
          ],
        ),
      );
      await _waitAfterDialogClosed();
      if (picked == null || !mounted) return;
      groupId = picked;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
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
    await _waitAfterDialogClosed();
    controller.dispose();
    if (trimmed.isEmpty || !mounted) return;
    try {
      final created = await _places.createCategory(
        groupId: groupId,
        name: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _categories = [..._categories, created]
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _categoryFilter = created.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.groupsCategoryCreated(created.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  List<NamedPlace> get _filteredPlaces {
    Iterable<NamedPlace> base = _sharedPlaces;
    final filter = _categoryFilter;
    if (filter != null) {
      if (filter.isEmpty) {
        base = base.where(
          (p) => p.categoryId == null || p.categoryId!.trim().isEmpty,
        );
      } else {
        base = base.where((p) => p.categoryId == filter);
      }
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return base.toList();
    return base.where((p) {
      final hay = [
        p.name,
        p.description ?? '',
        '${p.lat}',
        '${p.lon}',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
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
        SnackBar(
          content: Text('${AppStrings.groupsCreatedPrefix} ${group.name}'),
        ),
      );
      await _refresh();
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
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
    final result =
        await Navigator.of(context, rootNavigator: true).push<AcceptInviteResult>(
      MaterialPageRoute(
        builder: (_) => const AcceptInviteScreen(),
      ),
    );
    if (result == null) return;
    await _refresh();
    if (!mounted) return;
    final match = _groups.where((g) => g.id == result.groupId);
    if (match.isEmpty) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(group: match.first),
      ),
    );
    await _refresh();
  }

  Future<void> _openGroupDetail(FamilyGroup group) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(group: group),
      ),
    );
    await _refresh();
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

  String _placeCategoryLabel(NamedPlace place) {
    if (!place.isShared) return AppStrings.groupsPlacesSoloTitle;
    final cid = place.categoryId?.trim();
    if (cid == null || cid.isEmpty) {
      return AppStrings.groupsPlacesUncategorized;
    }
    for (final c in _categories) {
      if (c.id == cid) return c.name;
    }
    return AppStrings.groupsPlacesUncategorized;
  }

  Future<void> _openPlacePhotoFullscreen(NamedPlace place) async {
    final url = place.hasPhoto ? _places.publicPhotoUrl(place.photoPath) : null;
    if (url == null || !mounted) return;
    final screenH = MediaQuery.sizeOf(context).height;
    // Al menos la altura del mapa ampliado (~viewport completo menos nav).
    final minH = (screenH * 0.72).clamp(320.0, screenH);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            height: minH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: AppStrings.close,
                    onPressed: () =>
                        Navigator.of(ctx, rootNavigator: true).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    place.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placePhotoLeading(NamedPlace place) {
    final url =
        place.hasPhoto ? _places.publicPhotoUrl(place.photoPath) : null;
    if (url != null) {
      return GestureDetector(
        onTap: () => unawaited(_openPlacePhotoFullscreen(place)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _placeNoPhotoBadge(),
          ),
        ),
      );
    }
    return _placeNoPhotoBadge();
  }

  Widget _placeNoPhotoBadge() {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Icon(
        Icons.photo_camera_outlined,
        size: 22,
        color: AppColors.midBlue,
      ),
    );
  }

  Widget _categoryFilterChips() {
    Widget selected(
      String label, {
      required bool isSelected,
      VoidCallback? onTap,
    }) {
      return FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap?.call(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          selected(
            AppStrings.groupsPlacesFilterAll,
            isSelected: _categoryFilter == null,
            onTap: () => setState(() => _categoryFilter = null),
          ),
          const SizedBox(width: 6),
          selected(
            AppStrings.groupsPlacesUncategorized,
            isSelected: _categoryFilter == '',
            onTap: () => setState(() => _categoryFilter = ''),
          ),
          for (final c in _categories) ...[
            const SizedBox(width: 6),
            selected(
              c.name,
              isSelected: _categoryFilter == c.id,
              onTap: () => setState(() => _categoryFilter = c.id),
            ),
          ],
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text(AppStrings.mapSavePlaceCategoryNew),
            onPressed: () => unawaited(_createCategoryQuickAdd()),
          ),
        ],
      ),
    );
  }

  /// Solo debajo de los nombres de grupo (fuera del detalle).
  Widget _placesSection() {
    final places = _filteredPlaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.groupsPlacesTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.deepBlue,
            ),
          ),
          const SizedBox(height: 8),
          _categoryFilterChips(),
          const SizedBox(height: 8),
          if (_placesLoading && places.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (places.isEmpty)
            Text(
              _query.trim().isEmpty && _categoryFilter == null
                  ? AppStrings.groupsPlacesEmpty
                  : AppStrings.groupsPlacesSearchEmpty,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.midBlue,
                  ),
            )
          else
            for (final p in places)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: _placePhotoLeading(p),
                  title: InkWell(
                    onTap: widget.onOpenPlaceOnMap == null
                        ? null
                        : () => widget.onOpenPlaceOnMap!(p),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepBlue,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.signalCyan,
                        ),
                      ),
                    ),
                  ),
                  subtitle: Text(
                    [
                      if ((p.description ?? '').trim().isNotEmpty)
                        p.description!.trim(),
                      _placeCategoryLabel(p),
                      '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: AppStrings.groupsPlacesDelete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_deletePlace(p)),
                  ),
                ),
              ),
        ],
      ),
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
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: AppColors.surface,
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

  Widget _groupsListBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
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
      );
    }
    if (_groups.isEmpty) {
      return ListView(
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
          const SizedBox(height: 24),
          _placesSection(),
        ],
      );
    }

    // Filas de grupo = 94d85b4 ListTile exacto; lugares SOLO debajo.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.12),
              child: Icon(
                Icons.family_restroom,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              _groups[i].name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            subtitle: const Text(AppStrings.groupsTapMembers),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_openGroupDetail(_groups[i])),
          ),
        ],
        const Divider(height: 16),
        _placesSection(),
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
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _groupsListBody(),
            ),
          ),
          if (!_loading && _error == null) _searchBar(),
        ],
      ),
    );
  }
}
