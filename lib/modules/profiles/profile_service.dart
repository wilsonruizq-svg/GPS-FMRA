import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String? displayName;
  final String? photoUrl;

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      displayName: map['display_name'] as String?,
      photoUrl: map['photo_url'] as String?,
    );
  }

  String get label =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : 'Sin nombre';
}

/// Lectura/escritura de `profiles` (creado por trigger en signup).
class ProfileService {
  ProfileService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  Future<Profile?> fetchOwn() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    final row = await _sb
        .from('profiles')
        .select('id, display_name, photo_url')
        .eq('id', uid)
        .maybeSingle();

    if (row == null) return null;
    return Profile.fromMap(row);
  }

  /// Si el trigger aún no creó la fila, la inserta (RLS: solo propia).
  Future<Profile> ensureOwnProfile({String? displayName}) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa.');
    }

    final existing = await fetchOwn();
    if (existing != null) return existing;

    final name = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : (user.userMetadata?['display_name'] as String?) ??
            (user.email?.split('@').first ?? 'Usuario');

    final inserted = await _sb
        .from('profiles')
        .insert({
          'id': user.id,
          'display_name': name,
        })
        .select('id, display_name, photo_url')
        .single();

    // Settings también los crea el trigger; fallback idempotente.
    await _sb.from('user_settings').upsert({
      'user_id': user.id,
    });

    return Profile.fromMap(inserted);
  }

  Future<List<Profile>> fetchByIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];

    final rows = await _sb
        .from('profiles')
        .select('id, display_name, photo_url')
        .inFilter('id', list);

    return (rows as List)
        .map((e) => Profile.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
