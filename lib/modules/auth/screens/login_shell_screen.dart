import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../location/screens/consent_screen.dart';
import '../../profiles/profile_service.dart';
import '../auth_error_message.dart';
import '../auth_service.dart';
import '../gmail_auth_email.dart';

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
  bool _forgotMode = false;
  bool _resetPasswordMode = false;
  bool _obscurePassword = true;
  String? _error;
  String? _info;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.passwordRecovery) {
        setState(() {
          _resetPasswordMode = true;
          _forgotMode = false;
          _registerMode = false;
          _error = null;
          _info = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _clearModes() {
    _registerMode = false;
    _forgotMode = false;
    _resetPasswordMode = false;
  }

  Future<void> _submit() async {
    final rawEmail = _emailController.text;
    final email = GmailAuthEmail.normalize(rawEmail);
    final password = _passwordController.text;
    final displayName = _nameController.text.trim();

    if (_resetPasswordMode) {
      if (password.length < 6) {
        setState(() {
          _error = AppStrings.loginValidationError;
          _info = null;
        });
        return;
      }
      await _completePasswordReset(password);
      return;
    }

    if (_forgotMode) {
      final gmailError = GmailAuthEmail.validateForNewAccount(rawEmail);
      if (gmailError != null) {
        setState(() {
          _error = gmailError;
          _info = null;
        });
        return;
      }
      await _sendPasswordReset(email);
      return;
    }

    if (_registerMode) {
      final gmailError = GmailAuthEmail.validateForNewAccount(rawEmail);
      if (gmailError != null) {
        setState(() {
          _error = gmailError;
          _info = null;
        });
        return;
      }
    }

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
            _error = null;
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
      setState(() {
        _info = null;
        _error = authErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _error = authErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
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
      await _auth.requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() {
        _info = AppStrings.loginForgotSent;
        _forgotMode = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completePasswordReset(String password) async {
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
      await _auth.updatePassword(password);
      if (!mounted) return;
      await _profiles.ensureOwnProfile();
      if (!mounted) return;
      _goConsent();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
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

  String get _headline {
    if (_resetPasswordMode) return AppStrings.loginResetTitle;
    if (_forgotMode) return AppStrings.loginForgotTitle;
    if (_registerMode) return AppStrings.registerButton;
    return AppStrings.loginTitle;
  }

  String get _subtitle {
    if (_resetPasswordMode) return AppStrings.loginResetSubtitle;
    if (_forgotMode) return AppStrings.loginForgotSubtitle;
    if (_registerMode) return AppStrings.loginRegisterGmailNote;
    return AppStrings.loginSubtitle;
  }

  String get _primaryButtonLabel {
    if (_resetPasswordMode) return AppStrings.loginResetSave;
    if (_forgotMode) return AppStrings.loginForgotSend;
    if (_registerMode) return AppStrings.registerButton;
    return AppStrings.loginButton;
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
              _headline,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _subtitle,
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
              enabled: !_busy && !_resetPasswordMode,
              readOnly: _resetPasswordMode,
              decoration: InputDecoration(
                labelText: AppStrings.emailLabel,
                helperText: _forgotMode ? AppStrings.loginForgotEmailHelper : null,
                helperMaxLines: 2,
              ),
            ),
            if (!_forgotMode) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: _resetPasswordMode
                    ? const [AutofillHints.newPassword]
                    : _registerMode
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _resetPasswordMode
                      ? AppStrings.loginResetTitle
                      : AppStrings.passwordLabel,
                  suffixIcon: IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    tooltip: _obscurePassword
                        ? AppStrings.passwordShow
                        : AppStrings.passwordHide,
                  ),
                ),
              ),
            ],
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
                  : Text(_primaryButtonLabel),
            ),
            const SizedBox(height: 12),
            if (_resetPasswordMode || _forgotMode)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _clearModes();
                          _error = null;
                          _info = null;
                          _passwordController.clear();
                        }),
                child: const Text(AppStrings.loginForgotBack),
              )
            else ...[
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
              if (!_registerMode)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _forgotMode = true;
                            _registerMode = false;
                            _error = null;
                            _info = null;
                            _passwordController.clear();
                          }),
                  child: const Text(AppStrings.loginForgotHint),
                ),
            ],
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