import 'package:flutter/material.dart';

import 'core/l10n/app_strings.dart';
import 'modules/groups/screens/groups_placeholder_screen.dart';
import 'modules/map/screens/map_shell_screen.dart';
import 'modules/settings/screens/settings_screen.dart';

/// Navegación principal post-login: mapa, grupos, ajustes.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = [
    AppStrings.mapTitle,
    AppStrings.groupsTitle,
    AppStrings.settingsTitle,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: const [
          MapShellScreen(),
          GroupsPlaceholderScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
    );
  }
}
