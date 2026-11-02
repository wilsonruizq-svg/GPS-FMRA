import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../auth/auth_service.dart';
import '../../auth/screens/login_shell_screen.dart';
import '../../location/screens/consent_screen.dart';
import '../../profiles/profile_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profiles = ProfileService();
  final _auth = AuthService();

  Profile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _profiles.ensureOwnProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const LoginShellScreen(supabaseReady: true),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? '—';

    return ListView(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: const Icon(Icons.person_outline, size: 28),
          title: const Text(AppStrings.settingsProfile),
          subtitle: Text(
            _loading
                ? AppStrings.splashLoading
                : (_profile?.label ?? AppStrings.settingsProfileMissing),
          ),
          isThreeLine: true,
          trailing: Text(
            email,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: _load,
        ),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: const Icon(Icons.privacy_tip_outlined, size: 28),
          title: const Text(AppStrings.settingsPrivacy),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ConsentScreen(),
              ),
            );
          },
        ),
        const Divider(),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Icon(
            Icons.logout,
            size: 28,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            AppStrings.settingsSignOut,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: _signOut,
        ),
        const Divider(),
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Icon(Icons.info_outline, size: 28),
          title: Text(AppStrings.settingsAbout),
          subtitle: Text(AppStrings.settingsVersion),
        ),
      ],
    );
  }
}
