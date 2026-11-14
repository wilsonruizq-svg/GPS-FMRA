import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'sos_audio_recorder.dart';

/// Acceso al audio de **un** evento SOS (emergencia), no feed grupal.
class SosAudioAccess {
  SosAudioAccess({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  static String pathFor({required String userId, required String sosId}) =>
      '$userId/$sosId.m4a';

  /// URL firmada para reproducir el mic del emisor en riesgo.
  Future<Uri?> signedPlayUri({
    required String sosId,
    required String senderUserId,
  }) async {
    final path = pathFor(userId: senderUserId, sosId: sosId);
    try {
      final url = await _sb.storage
          .from(SosAudioRecorder.storageBucket)
          .createSignedUrl(path, 3600);
      return Uri.tryParse(url);
    } catch (_) {
      return null;
    }
  }
}
