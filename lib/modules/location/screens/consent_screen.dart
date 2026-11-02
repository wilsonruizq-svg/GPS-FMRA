import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app_shell.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../consent_service.dart';

/// Explica el consentimiento de ubicación y permite aceptar o pausar (sin tracking silencioso).
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _consent = ConsentService();
  final _groups = GroupsService();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _globallyPaused = false;
  List<FamilyGroup> _myGroups = const [];
  Map<String, LocationConsent> _consentsByGroup = {};

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
      final consents = await _consent.listOwnGroupConsents();
      final paused = await _consent.isGloballyPaused();
      if (!mounted) return;
      setState(() {
        _myGroups = groups;
        _consentsByGroup = {
          for (final c in consents)
            if (c.groupId != null) c.groupId!: c,
        };
        _globallyPaused = paused;
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

  Future<void> _requestLocationInContext() async {
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted || status.isLimited) return;
    await Permission.locationWhenInUse.request();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _requestLocationInContext();
      final ids = _myGroups.map((g) => g.id).toList();
      if (ids.isEmpty) {
        // Sin grupos aún: solo quita pausa global; el consentimiento por grupo
        // se pedirá al crear o unirse a un grupo.
        await _consent.setGloballyPaused(false);
      } else {
        await _consent.acceptForAllMyGroups(ids);
      }
      if (!mounted) return;
      _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _consent.pauseAllOwnConsents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.consentPausedSnack)),
      );
      if (widget.isOnboarding) {
        _finish();
      } else {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    if (widget.isOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.consentTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                Icon(
                  Icons.my_location,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.consentHeadline,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.consentBody,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.consentNoSilent,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (_globallyPaused) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      AppStrings.consentCurrentlyPaused,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.accentRed,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (_myGroups.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.consentGroupsHeading,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ..._myGroups.map((g) {
                    final c = _consentsByGroup[g.id];
                    final status = c == null
                        ? AppStrings.consentStatusNone
                        : c.isActive
                            ? AppStrings.consentStatusActive
                            : c.isPaused
                                ? AppStrings.consentStatusPaused
                                : AppStrings.consentStatusRevoked;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(g.name),
                      subtitle: Text(status),
                      leading: Icon(
                        c?.isActive == true
                            ? Icons.check_circle
                            : Icons.pause_circle_outline,
                        color: c?.isActive == true
                            ? AppColors.midBlue
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  }),
                ] else ...[
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.consentNoGroupsYet,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppStrings.consentAccept),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _pause,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: AppColors.accentRed,
                    side: const BorderSide(color: AppColors.accentRed),
                  ),
                  child: const Text(AppStrings.consentPause),
                ),
                if (widget.isOnboarding) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _finish,
                    child: const Text(AppStrings.consentSkipForNow),
                  ),
                ],
              ],
            ),
    );
  }
}
