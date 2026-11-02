import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../location/screens/consent_placeholder_screen.dart';

/// Shell de login (sin Supabase aún). Entra al flujo de consentimiento → mapa.
class LoginShellScreen extends StatefulWidget {
  const LoginShellScreen({super.key});

  @override
  State<LoginShellScreen> createState() => _LoginShellScreenState();
}

class _LoginShellScreenState extends State<LoginShellScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const ConsentPlaceholderScreen(isOnboarding: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.loginTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.loginSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: AppStrings.emailLabel,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: AppStrings.passwordLabel,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _continue,
              child: const Text(AppStrings.loginButton),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _continue,
              child: const Text(AppStrings.registerHint),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.loginShellNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
