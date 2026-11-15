import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/biometric_unlock_service.dart';
import '../../auth/screens/login_shell_screen.dart';
import '../license_service.dart';

/// Sin licencia vigente: bloqueo sin AppShell / mapa / chat (GF-72).
class LicenseBlockedScreen extends StatelessWidget {
  const LicenseBlockedScreen({
    super.key,
    this.access,
    this.supabaseReady = true,
  });

  final LicenseAccess? access;
  final bool supabaseReady;

  String get _title {
    if (access?.needsEmailConfirm == true) {
      return AppStrings.licenseEmailTitle;
    }
    if (access?.reason == 'unavailable') {
      return AppStrings.licenseUnavailableTitle;
    }
    return AppStrings.licenseExpiredTitle;
  }

  String get _body {
    if (access?.needsEmailConfirm == true) {
      return AppStrings.licenseEmailBody;
    }
    if (access?.reason == 'unavailable') {
      return AppStrings.licenseUnavailableBody;
    }
    return AppStrings.licenseExpiredBody;
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    try {
      await BiometricUnlockService().clear();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginShellScreen(supabaseReady: supabaseReady),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                access?.needsEmailConfirm == true
                    ? Icons.mark_email_unread_outlined
                    : Icons.lock_outline,
                size: 72,
                color: AppColors.onDeep,
              ),
              const SizedBox(height: 24),
              Text(
                _title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.onDeep,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                _body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.signalCyan,
                      height: 1.35,
                    ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _signOut(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.signalCyan,
                  foregroundColor: AppColors.deepBlue,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text(AppStrings.licenseSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
