import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../location/screens/consent_placeholder_screen.dart';
import 'login_shell_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.supabaseReady = false});

  final bool supabaseReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), _routeNext);
  }

  void _routeNext() {
    if (!mounted) return;

    final signedIn = widget.supabaseReady &&
        Supabase.instance.client.auth.currentSession != null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => signedIn
            ? const ConsentPlaceholderScreen(isOnboarding: false)
            : LoginShellScreen(supabaseReady: widget.supabaseReady),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 72, color: AppColors.onDeep),
            const SizedBox(height: 16),
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.onDeep,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.tagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.signalCyan,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onDeep,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.splashLoading,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onDeep.withValues(alpha: 0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
