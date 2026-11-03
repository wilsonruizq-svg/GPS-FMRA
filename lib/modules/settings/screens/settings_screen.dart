import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_service.dart';
import '../../auth/screens/login_shell_screen.dart';
import '../../groups/exit_pin_service.dart';
import '../../groups/widgets/exit_pin_dialog.dart';
import '../../location/screens/consent_screen.dart';
import '../../profiles/profile_service.dart';
import '../../profiles/screens/edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profiles = ProfileService();
  final _auth = AuthService();
  final _exitPin = ExitPinService();

  Profile? _profile;
  bool _loading = true;
  bool _signingOut = false;

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

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<Profile>(
      MaterialPageRoute<Profile>(
        builder: (_) => const EditProfileScreen(),
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() => _profile = updated);
    } else {
      await _load();
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      final required = await _exitPin.isRequired();
      if (!mounted) return;
      if (required) {
        final ok = await showExitPinChallenge(
          context: context,
          purpose: ExitPinPurpose.logout,
          service: _exitPin,
        );
        if (!mounted) return;
        if (!ok) return;
      }

      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginShellScreen(supabaseReady: true),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  String get _displayName {
    if (_loading) return AppStrings.splashLoading;
    return _profile?.label ?? AppStrings.settingsProfileMissing;
  }

  String get _email => _auth.currentUser?.email ?? '—';

  bool get _hasPhoto =>
      _profile?.photoUrl != null && _profile!.photoUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _buildProfileCard(theme),
        const SizedBox(height: 28),
        _sectionLabel(AppStrings.settingsSectionPrivacy),
        const SizedBox(height: 8),
        _settingsCard(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: AppColors.deepBlue.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppColors.deepBlue,
                ),
              ),
              title: const Text(AppStrings.settingsPrivacy),
              subtitle: const Text(AppStrings.settingsPrivacySubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConsentScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(AppStrings.settingsSectionSession),
        const SizedBox(height: 8),
        _settingsCard(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor:
                    theme.colorScheme.error.withValues(alpha: 0.12),
                child: Icon(
                  Icons.logout,
                  color: theme.colorScheme.error,
                ),
              ),
              title: Text(
                AppStrings.settingsSignOut,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: _signingOut
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.error,
                      ),
                    )
                  : null,
              onTap: _signingOut ? null : _signOut,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(AppStrings.settingsSectionAbout),
        const SizedBox(height: 8),
        _settingsCard(
          children: [
            const ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Color(0x1A0B2A4A),
                child: Icon(Icons.info_outline, color: AppColors.deepBlue),
              ),
              title: Text(AppStrings.settingsAbout),
              subtitle: Text(AppStrings.settingsVersion),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.midBlue,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.deepBlue.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildProfileCard(ThemeData theme) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.deepBlue.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openEditProfile,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE8F1F8),
                Color(0xFFF5F8FB),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.deepBlue.withValues(alpha: 0.12),
                  backgroundImage:
                      _hasPhoto ? NetworkImage(_profile!.photoUrl!) : null,
                  child: _hasPhoto
                      ? null
                      : Text(
                          _initials(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepBlue,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.settingsSectionAccount,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.midBlue,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _email,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.midBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.settingsProfileTap,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.signalCyan.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  color: AppColors.deepBlue.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials() {
    final name = (_profile?.displayName ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
