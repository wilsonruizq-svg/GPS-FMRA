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
    // Al volver al Mapa, asegurar listener de alertas de chat.
    if (i == 0) {
      unawaited(ChatAlertService.instance.ensureRunning());
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onRootBack();
      },
      child: Scaffold(
        // Mapa: sin AppBar (franja propia + ampliar). Grupos/Ajustes con título.
        appBar: _index == 0
            ? null
            : AppBar(title: Text(_titles[_index])),
        body: IndexedStack(
          index: _index,
          children: const [
            MapShellScreen(),
            GroupsScreen(),
            SettingsScreen(),
          ],
        ),
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
