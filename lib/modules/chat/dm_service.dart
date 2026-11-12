import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// Mensaje 1:1.
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.senderName,
    this.senderPhotoUrl,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final String? senderName;
  final String? senderPhotoUrl;

  String get senderLabel {
    final n = senderName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Integrante';
  }

  factory DirectMessage.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? name;
    String? photo;
    if (profile is Map) {
      name = profile['display_name'] as String?;
      final rawPhoto = profile['photo_url'] as String?;
      if (rawPhoto != null && rawPhoto.trim().isNotEmpty) {
        photo = rawPhoto.trim();
      }
    }
    final createdRaw = map['created_at'];
    DateTime createdAt;
    if (createdRaw is String && createdRaw.isNotEmpty) {
      createdAt = DateTime.parse(createdRaw).toUtc();
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw.toUtc();
    } else {
      createdAt = DateTime.now().toUtc();
    }
    return DirectMessage(
      id: '${map['id'] ?? ''}'.trim(),
      senderId: '${map['sender_id'] ?? ''}'.trim(),
      recipientId: '${map['recipient_id'] ?? ''}'.trim(),
      body: (map['body'] as String? ?? '').trim(),
      createdAt: createdAt,
      senderName: name,
      senderPhotoUrl: photo,
    );
  }

  DirectMessage copyWith({String? senderName, String? senderPhotoUrl}) {
    return DirectMessage(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      body: body,
      createdAt: createdAt,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
    );
  }
}

class DmService {
  DmService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  // Sin embed: sender y recipient apuntan ambos a profiles (ambiguo en PostgREST).
  static const _select = 'id, sender_id, recipient_id, body, created_at';

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  Future<List<DirectMessage>> listThread({
    required String peerUserId,
    int limit = 100,
  }) async {
    final peer = peerUserId.trim();
    final me = _uid;
    final rows = await _sb
        .from('direct_messages')
        .select(_select)
        .or(
          'and(sender_id.eq.$me,recipient_id.eq.$peer),'
          'and(sender_id.eq.$peer,recipient_id.eq.$me)',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    final list = (rows as List)
        .map((e) => DirectMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return list.reversed.toList();
  }

  /// Últimos DM donde participo (para alertas / seed).
  Future<List<DirectMessage>> listMyRecent({int limit = 40}) async {
    final me = _uid;
    final rows = await _sb
        .from('direct_messages')
        .select(_select)
        .or('sender_id.eq.$me,recipient_id.eq.$me')
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => DirectMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DirectMessage> send({
    required String recipientId,
    required String body,
  }) async {
    final trimmed = body.trim();
    final peer = recipientId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El mensaje no puede estar vacío.');
    }
    if (trimmed.length > 2000) {
      throw ArgumentError('El mensaje es demasiado largo (máx. 2000).');
    }
    if (peer.isEmpty || peer == _uid) {
      throw ArgumentError('Destinatario inválido.');
    }

    final row = await _sb
        .from('direct_messages')
        .insert({
          'sender_id': _uid,
          'recipient_id': peer,
          'body': trimmed,
        })
        .select(_select)
        .single();

    return DirectMessage.fromMap(Map<String, dynamic>.from(row));
  }

  Future<DirectMessage> enrich(DirectMessage message) async {
    if ((message.senderName?.trim().isNotEmpty ?? false)) {
      return message;
    }
    try {
      final row = await _sb
          .from('profiles')
          .select('display_name, photo_url')
          .eq('id', message.senderId)
          .maybeSingle();
      if (row == null) return message;
      final name = row['display_name'] as String?;
      final photo = row['photo_url'] as String?;
      return message.copyWith(
        senderName: name,
        senderPhotoUrl:
            (photo != null && photo.trim().isNotEmpty) ? photo.trim() : null,
      );
    } catch (e) {
      debugPrint('DmService.enrich: $e');
      return message;
    }
  }

  RealtimeChannel subscribeMine({
    required void Function(DirectMessage message) onInsert,
  }) {
    final channel = _sb.channel(
      'direct_messages_mine_${DateTime.now().millisecondsSinceEpoch}',
    );
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'direct_messages',
          callback: (payload) {
            try {
              onInsert(
                DirectMessage.fromMap(
                  Map<String, dynamic>.from(payload.newRecord),
                ),
              );
            } catch (e) {
              debugPrint('DmService.subscribe parse: $e');
            }
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel? channel) async {
    if (channel == null) return;
    await _sb.removeChannel(channel);
  }

  static bool looksLikeMissingTable(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('direct_messages') &&
        (s.contains('does not exist') ||
            s.contains('42p01') ||
            s.contains('404') ||
            s.contains('schema cache') ||
            s.contains('could not find') ||
            s.contains('pgrst205'));
  }
}
