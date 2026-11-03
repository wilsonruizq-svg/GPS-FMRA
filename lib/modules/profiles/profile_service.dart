import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'profile_validation.dart';

class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.photoUrl,
    this.phone,
  });

  final String id;
  final String? displayName;
  final String? photoUrl;
  final String? phone;

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      displayName: map['display_name'] as String?,
      photoUrl: map['photo_url'] as String?,
      phone: map['phone'] as String?,
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

  /// Bucket previsto para avatares. Si no existe en el proyecto, la UI omite foto.
  static const avatarBucket = 'avatars';

  static const _profileSelect =
      'id, display_name, photo_url, phone';

  Future<Profile?> fetchOwn() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    final row = await _sb
        .from('profiles')
        .select(_profileSelect)
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
        .select(_profileSelect)
        .single();

    // Settings también los crea el trigger; fallback idempotente.
    await _sb.from('user_settings').upsert({
      'user_id': user.id,
    });

    return Profile.fromMap(inserted);
  }

  /// Actualiza el perfil propio vía RLS (`profiles_update_own`).
  Future<Profile> updateOwn({
    required String displayName,
    String? phone,
    String? photoUrl,
    bool clearPhoto = false,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa.');
    }

    final nameError = ProfileValidation.validateDisplayName(displayName);
    if (nameError != null) {
      throw ArgumentError(nameError);
    }

    final normalizedPhone = ProfileValidation.normalizePhone(phone);

    final payload = <String, dynamic>{
      'display_name': displayName.trim(),
      'phone': normalizedPhone,
    };
    if (clearPhoto) {
      payload['photo_url'] = null;
    } else if (photoUrl != null) {
      payload['photo_url'] = photoUrl;
    }

    final row = await _sb
        .from('profiles')
        .update(payload)
        .eq('id', user.id)
        .select(_profileSelect)
        .single();

    return Profile.fromMap(row);
  }

  /// Comprueba si el bucket de avatares responde (Storage listo).
  Future<bool> isAvatarStorageReady() async {
    try {
      await _sb.storage.from(avatarBucket).list(path: '');
      return true;
    } on StorageException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Sube JPEG ya comprimido al bucket `avatars` y devuelve URL pública
  /// con cache-bust. Solo llamar si [isAvatarStorageReady] es true.
  Future<String> uploadOwnAvatar({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa.');
    }

    // Siempre JPEG tras AvatarCompress — path estable + upsert.
    final path = '${user.id}/avatar.jpg';

    await _sb.storage.from(avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
          ),
        );

    final publicUrl = _sb.storage.from(avatarBucket).getPublicUrl(path);
    final bust = DateTime.now().millisecondsSinceEpoch;
    final withBust = '$publicUrl${publicUrl.contains('?') ? '&' : '?'}v=$bust';

    await _sb.from('profiles').update({
      'photo_url': withBust,
    }).eq('id', user.id);

    return withBust;
  }

  /// Quita foto del perfil y, si hay Storage, borra el objeto.
  Future<void> clearOwnAvatar() async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa.');
    }

    await _sb.from('profiles').update({
      'photo_url': null,
    }).eq('id', user.id);

    try {
      await _sb.storage.from(avatarBucket).remove(['${user.id}/avatar.jpg']);
    } catch (_) {
      // Bucket ausente o sin objeto: OK.
    }
  }

  Future<List<Profile>> fetchByIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];

    final rows = await _sb
        .from('profiles')
        .select(_profileSelect)
        .inFilter('id', list);

    return (rows as List)
        .map((e) => Profile.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
