import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/groups_service.dart';
import '../consent_service.dart';

/// Ajustes mínimos: interruptor para pausar/reanudar compartir ubicación.
/// Sin wizard bloqueante (GF-30/consent-first removido del login).
class ShareLocationSettingsScreen extends StatefulWidget {
  const ShareLocationSettingsScreen({super.key});

  @override
  State<ShareLocationSettingsScreen> createState() =>
      _ShareLocationSettingsScreenState();
}

class _ShareLocationSettingsScreenState
    extends State<ShareLocationSettingsScreen> {
  final _consent = ConsentService();
  final _groups = GroupsService();

  bool _loading = true;
  bool _busy = false;
  bool _sharing = true;
  String? _error;

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
      final paused = await _consent.isGloballyPaused();
      if (!mounted) return;
      setState(() {
        _sharing = !paused;
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

  Future<void> _onToggle(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
      _sharing = value;
    });
    try {
      if (value) {
        final groups = await _groups.listMyGroups();
        await _consent.acceptForAllMyGroups(groups.map((g) => g.id).toList());
        await _consent.setGloballyPaused(false);
      } else {
        await _consent.pauseAllOwnConsents();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? AppStrings.shareLocationEnabledSnack
                : AppStrings.consentPausedSnack,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sharing = !value;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsPrivacy)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Text(
                  AppStrings.shareLocationSettingsBody,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.midBlue,
                      ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppStrings.shareLocationToggle),
                  subtitle: Text(
                    _sharing
                        ? AppStrings.shareLocationToggleOn
                        : AppStrings.shareLocationToggleOff,
                  ),
                  value: _sharing,
                  onChanged: _busy ? null : _onToggle,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
