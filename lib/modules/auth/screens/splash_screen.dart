import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'login_shell_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), _goLogin);
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginShellScreen()),
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
