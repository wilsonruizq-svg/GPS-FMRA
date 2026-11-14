import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../sos_audio_access.dart';

/// Historial de audios de **emergencias SOS** del grupo (no chat / no feed social).
class SosEmergencyAudioHistoryScreen extends StatefulWidget {
  const SosEmergencyAudioHistoryScreen({super.key, this.initialGroup});

  /// Si viene de detalle de grupo, fija ese grupo.
  final FamilyGroup? initialGroup;

  @override
  State<SosEmergencyAudioHistoryScreen> createState() =>
      _SosEmergencyAudioHistoryScreenState();
}

class _SosEmergencyAudioHistoryScreenState
    extends State<SosEmergencyAudioHistoryScreen> {
  final _groups = GroupsService();
  final _access = SosAudioAccess();
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSub;

  bool _loading = true;
  String? _error;
  List<FamilyGroup> _groupsList = const [];
  FamilyGroup? _selected;
  List<SosEmergencyAudioItem> _items = const [];
  bool _playBusy = false;
  String? _playingSosId;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialGroup;
    _playerSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!mounted) return;
        setState(() => _playingSosId = null);
      }
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(_playerSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
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
      List<SosEmergencyAudioItem> items = const [];
      if (selected != null) {
        items = await _access.listGroupEmergencyAudio(groupId: selected.id);
      }
      if (!mounted) return;
      setState(() {
        _groupsList = groups;
        _selected = selected;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _onSelect(FamilyGroup? g) async {
    if (g == null) return;
    setState(() {
      _selected = g;
      _loading = true;
      _error = null;
    });
    try {
      await _player.stop();
      final items = await _access.listGroupEmergencyAudio(groupId: g.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _playingSosId = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('list_group_sos_emergency_audio') ||
        s.contains('PGRST202') ||
        s.contains('404') ||
        s.contains('Could not find the function')) {
      return AppStrings.sosAudioHistoryNeedSql;
    }
    return s;
  }

  String _fmt(DateTime utc) {
    final local = utc.toLocal();
    final d =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d · $t';
  }

  Future<void> _togglePlay(SosEmergencyAudioItem item) async {
    if (_playBusy) return;
    if (_playingSosId == item.sosId) {
      await _player.stop();
      if (!mounted) return;
      setState(() => _playingSosId = null);
      return;
    }
    setState(() => _playBusy = true);
    try {
      final uri = await _access.signedPlayUri(
        sosId: item.sosId,
        senderUserId: item.userId,
      );
      if (!mounted) return;
      if (uri == null) {
        setState(() => _playBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.sosAudioPlayError)),
        );
        return;
      }
      await _player.stop();
      await _player.setUrl(uri.toString());
      setState(() {
        _playingSosId = item.sosId;
        _playBusy = false;
      });
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playBusy = false;
        _playingSosId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.sosAudioPlayError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockGroup = widget.initialGroup != null;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.sosAudioHistoryTitle)),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.sosAudioHistorySubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.midBlue,
                        ),
                  ),
                  if (!lockGroup) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<FamilyGroup>(
                      // ignore: deprecated_member_use
                      value: _selected,
                      decoration: const InputDecoration(
                        labelText: AppStrings.historyGroupLabel,
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: _groupsList
                          .map(
                            (g) => DropdownMenuItem(
                              value: g,
                              child: Text(g.name),
                            ),
                          )
                          .toList(),
                      onChanged: _loading ? null : _onSelect,
                    ),
                  ] else if (_selected != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _selected!.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text(AppStrings.retry),
                          ),
                        ],
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                AppStrings.sosAudioHistoryEmpty,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.midBlue),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = _items[i];
                                final playing = _playingSosId == item.sosId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.accentRed
                                        .withValues(alpha: 0.12),
                                    child: Icon(
                                      playing
                                          ? Icons.stop_circle_outlined
                                          : Icons.hearing,
                                      color: AppColors.accentRed,
                                    ),
                                  ),
                                  title: Text(item.displayName),
                                  subtitle: Text(
                                    '${_fmt(item.createdAt)} · '
                                    '${item.isActive ? AppStrings.sosAudioStatusActive : AppStrings.sosAudioStatusResolved}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: playing
                                        ? AppStrings.sosAudioStop
                                        : AppStrings.sosAudioPlayEmergency,
                                    onPressed: _playBusy
                                        ? null
                                        : () => unawaited(_togglePlay(item)),
                                    icon: Icon(
                                      playing
                                          ? Icons.stop
                                          : Icons.play_arrow_rounded,
                                      color: AppColors.deepBlue,
                                    ),
                                  ),
                                  onTap: _playBusy
                                      ? null
                                      : () => unawaited(_togglePlay(item)),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
