import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/l10n/app_strings.dart';
import 'modules/chat/chat_alert_service.dart';
import 'modules/groups/exit_pin_service.dart';
import 'modules/groups/screens/groups_screen.dart';
import 'modules/groups/widgets/exit_pin_dialog.dart';
import 'modules/map/screens/map_shell_screen.dart';
import 'modules/settings/screens/settings_screen.dart';

/// Navegación principal post-login: mapa, grupos, ajustes.
/// El botón Atrás del sistema en la raíz pide el PIN de salida si aplica.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _exitPin = ExitPinService();
  bool _exitGateBusy = false;
  final _groupsKey = GlobalKey<GroupsScreenState>();

  static const _titles = [
    AppStrings.mapTitle,
    AppStrings.groupsTitle,
    AppStrings.settingsTitle,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(ChatAlertService.instance.start());
  }

  @override
  void dispose() {
    unawaited(ChatAlertService.instance.stop());
    super.dispose();
  }

  void _onTabSelected(int i) {
    setState(() => _index = i);
    if (i == 0) {
      unawaited(ChatAlertService.instance.ensureRunning());
    }
    if (i == 1) {
      unawaited(_groupsKey.currentState?.reload() ?? Future<void>.value());
    }
  }

  Future<void> _onGroupsRefreshFab() async {
    final state = _groupsKey.currentState;
    if (state == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grupos: pantalla no lista. Reabre la pestaña.')),
      );
      return;
    }
    try {
      await state.reload();
      if (!mounted) return;
      final n = state.groupCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Grupos cargados: 0 (si el Mapa sí ve familia, reporta).'
                : 'Grupos cargados: $n',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      // Fuerza rebuild del shell (FAB / body).
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error Grupos: $e')),
      );
    }
  }

  Future<void> _onRootBack() async {
    if (_exitGateBusy) return;
    _exitGateBusy = true;
    try {
      final required = await _exitPin.isRequired();
      if (!mounted) return;
      if (!required) {
        await SystemNavigator.pop();
        return;
      }
      final ok = await showExitPinChallenge(
        context: context,
        purpose: ExitPinPurpose.leaveApp,
        service: _exitPin,
      );
      if (!mounted) return;
      if (ok) {
        await SystemNavigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      _exitGateBusy = false;
    }
  }

  Widget? _groupsFab() {
    if (_index != 1) return null;
    final gs = _groupsKey.currentState;
    final empty = gs?.isEmpty ?? false;
    final loading = gs?.isLoading ?? false;
    if (empty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join_invite',
            onPressed: () {
              // Trigger via navigating - GroupsScreen handles join when empty UI shown
              unawaited(_onGroupsRefreshFab());
            },
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.retry),
          ),
        ],
      );
    }
    return FloatingActionButton(
      heroTag: 'groups_refresh',
      tooltip: AppStrings.retry,
      onPressed: loading ? null : _onGroupsRefreshFab,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onRootBack();
      },
      child: Scaffold(
        appBar: _index == 0
            ? null
            : AppBar(title: Text(_titles[_index])),
        // Un solo Scaffold: body = IndexedStack (como el Mapa).
        body: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: [
            const MapShellScreen(),
            GroupsScreen(key: _groupsKey),
            const SettingsScreen(),
          ],
        ),
        floatingActionButton: _groupsFab(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onTabSelected,
          height: 72,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: AppStrings.navMap,
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: AppStrings.navGroups,
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: AppStrings.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}
