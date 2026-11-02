import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../location/screens/consent_placeholder_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text(AppStrings.settingsProfile),
          subtitle: const Text('Pendiente — Supabase Auth'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text(AppStrings.settingsPrivacy),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ConsentPlaceholderScreen(),
              ),
            );
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text(AppStrings.settingsAbout),
          subtitle: const Text(AppStrings.settingsVersion),
        ),
      ],
    );
  }
}
