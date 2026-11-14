import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'sos_audio_recorder.dart';
import 'sos_service.dart';

/// Fila de historial: SOS de emergencia con audio subido.
class SosEmergencyAudioItem {
  const SosEmergencyAudioItem({
    required this.sosId,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.storagePath,
  });

  final String sosId;
  final String userId;
  final String displayName;
  final String status;
  final DateTime createdAt;
  final String storagePath;

  bool get isActive => status == 'active';

  factory SosEmergencyAudioItem.fromMap(Map<String, dynamic> map) {
    final sosId = '${map['sos_id']}'.trim();
    final userId = '${map['user_id']}'.trim();
    if (sosId.isEmpty || userId.isEmpty) {
      throw FormatException('sos emergency audio row inválida');
    }
    return SosEmergencyAudioItem(
      sosId: sosId,
      userId: userId,
      displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
          ? (map['display_name'] as String).trim()
          : 'Integrante',
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      storagePath: (map['storage_path'] as String?)?.trim().isNotEmpty == true
          ? (map['storage_path'] as String).trim()
          : '$userId/$sosId.m4a',
    );
  }
}

/// Acceso al audio de eventos SOS (emergencia / rescate), no chat.
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

  /// Historial del grupo: solo SOS con archivo en Storage.
  Future<List<SosEmergencyAudioItem>> listGroupEmergencyAudio({
    required String groupId,
    int limit = 50,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return const [];
    try {
      final rows = await _sb.rpc(
        'list_group_sos_emergency_audio',
        params: {
          'p_group_id': gid,
          'p_limit': limit,
        },
      );
      if (rows is! List) return const [];
      return rows
          .map(
            (e) => SosEmergencyAudioItem.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (e) {
      if (!SosService.isMissingApiObject(e)) rethrow;
      debugPrint(
        'SosAudioAccess: list_group_sos_emergency_audio ausente; fallback Storage.',
      );
      return _listGroupEmergencyAudioViaEvents(
        groupId: gid,
        limit: limit,
      );
    }
  }

  /// Misma semántica que el RPC, sin `list_group_sos_emergency_audio` (solo
  /// requiere `sos_events` + bucket `sos-audio` como el play en vivo).
  Future<List<SosEmergencyAudioItem>> _listGroupEmergencyAudioViaEvents({
    required String groupId,
    int limit = 50,
  }) async {
    final events = await SosService().listForGroup(groupId, limit: limit);
    if (events.isEmpty) return const [];

    final namesByUser = <String, Set<String>>{};
    for (final e in events) {
      namesByUser.putIfAbsent(e.userId, () => {});
    }
    for (final userId in namesByUser.keys) {
      try {
        final files = await _sb.storage
            .from(SosAudioRecorder.storageBucket)
            .list(
              path: userId,
              searchOptions: const SearchOptions(limit: 100),
            );
        namesByUser[userId] = files.map((f) => f.name).toSet();
      } catch (err) {
        debugPrint('SosAudioAccess list($userId): $err');
        namesByUser[userId] = {};
      }
    }

    final out = <SosEmergencyAudioItem>[];
    for (final e in events) {
      final fileName = '${e.id}.m4a';
      if (namesByUser[e.userId]?.contains(fileName) != true) continue;
      out.add(
        SosEmergencyAudioItem(
          sosId: e.id,
          userId: e.userId,
          displayName: e.label,
          status: e.status,
          createdAt: e.createdAt,
          storagePath: pathFor(userId: e.userId, sosId: e.id),
        ),
      );
    }
    return out;
  }
}
