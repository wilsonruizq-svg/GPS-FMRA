import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../location/screens/consent_screen.dart';
import '../../profiles/profile_service.dart';
import '../auth_service.dart';

/// Login / registro email-password contra Supabase (si está configurado).
class LoginShellScreen extends StatefulWidget {
  const LoginShellScreen({super.key, this.supabaseReady = false});

  final bool supabaseReady;

  @override
  State<LoginShellScreen> createState() => _LoginShellScreenState();
}

class _LoginShellScreenState extends State<LoginShellScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _auth = AuthService();
  final _profiles = ProfileService();

  bool _busy = false;
  bool _registerMode = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _nameController.text.trim();

    if (email.isEmpty || password.length < 6) {
      setState(() {
        _error = AppStrings.loginValidationError;
        _info = null;
      });
      return;
    }

    if (!widget.supabaseReady) {
      setState(() {
        _error = AppStrings.loginMissingConfig;
        _info = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      if (_registerMode) {
        final res = await _auth.signUp(
          email: email,
          password: password,
          displayName: displayName.isEmpty ? null : displayName,
        );
        if (!mounted) return;

        if (res.session == null) {
          setState(() {
            _info = AppStrings.loginConfirmEmail;
            _registerMode = false;
          });
          return;
        }

        await _profiles.ensureOwnProfile(
          displayName: displayName.isEmpty ? null : displayName,
        );
        if (!mounted) return;
        _goConsent();
      } else {
        await _auth.signIn(email: email, password: password);
        if (!mounted) return;
        await _profiles.ensureOwnProfile();
        if (!mounted) return;
        _goConsent();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      final hint = Env.anonKeyLooksNonJwt
          ? AppStrings.loginJwtHint
          : AppStrings.loginGenericError;
      setState(() => _error = hint);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goConsent() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const ConsentScreen(isOnboarding: true),
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
              _registerMode
                  ? AppStrings.registerButton
                  : AppStrings.loginTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.loginSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (!widget.supabaseReady) ...[
              const SizedBox(height: 16),
              Text(
                AppStrings.loginMissingConfig,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (widget.supabaseReady && Env.anonKeyLooksNonJwt) ...[
              const SizedBox(height: 16),
              Text(
                AppStrings.loginJwtHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
              ),
            ],
            const SizedBox(height: 28),
            if (_registerMode) ...[
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: AppStrings.displayNameLabel,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: AppStrings.emailLabel,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: AppStrings.passwordLabel,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 16),
              Text(
                _info!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _registerMode
                          ? AppStrings.registerButton
                          : AppStrings.loginButton,
                    ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _registerMode = !_registerMode;
                        _error = null;
                        _info = null;
                      }),
              child: Text(
                _registerMode
                    ? AppStrings.loginHint
                    : AppStrings.registerHint,
              ),
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
