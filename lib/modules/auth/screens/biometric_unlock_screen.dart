import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_shell.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../biometric_unlock_service.dart';
import 'login_shell_screen.dart';

/// Pantalla de huella cuando ya hay sesión válida.
class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({super.key, this.supabaseReady = true});

  final bool supabaseReady;

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  final _bio = BiometricUnlockService();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _bio.authenticate(
      reason: AppStrings.biometricReason,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = AppStrings.biometricFailed;
    });
  }

  Future<void> _usePassword() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _bio.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginShellScreen(supabaseReady: widget.supabaseReady),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              const Icon(
                Icons.fingerprint,
                size: 88,
                color: AppColors.onDeep,
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.biometricTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.onDeep,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.biometricBody,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.signalCyan,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFFCDD2)),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(color: AppColors.onDeep),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _tryUnlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.signalCyan,
                    foregroundColor: AppColors.deepBlue,
                  ),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text(AppStrings.biometricRetry),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _usePassword,
                  child: Text(
                    AppStrings.biometricUsePassword,
                    style: TextStyle(
                      color: AppColors.onDeep.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
