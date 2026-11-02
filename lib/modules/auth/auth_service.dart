import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// Auth mínima Fase 1 (email/password).
class AuthService {
  AuthService({this._client});

  final SupabaseClient? _client;

  SupabaseClient get _sb => _client ?? supabase;

  Session? get currentSession => _sb.auth.currentSession;
  User? get currentUser => _sb.auth.currentUser;
  bool get isSignedIn => currentSession != null;

  Stream<AuthState> get onAuthStateChange => _sb.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _sb.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _sb.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
  }

  Future<void> signOut() => _sb.auth.signOut();
}
