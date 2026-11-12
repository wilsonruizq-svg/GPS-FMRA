import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// Mensaje de texto del grupo familiar.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.senderName,
    this.senderPhotoUrl,
  });

  final String id;
  final String groupId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final String? senderName;
  final String? senderPhotoUrl;

  String get senderLabel {
    final n = senderName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Integrante';
  }

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
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
    return GroupMessage(
      id: '${map['id']}'.trim(),
      groupId: '${map['group_id']}'.trim(),
      senderId: '${map['sender_id']}'.trim(),
      body: (map['body'] as String? ?? '').trim(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      senderName: name,
      senderPhotoUrl: photo,
    );
  }

  GroupMessage copyWith({
    String? senderName,
    String? senderPhotoUrl,
  }) {
    return GroupMessage(
      id: id,
      groupId: groupId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
    );
  }
}

/// Lectura / envío / Realtime de `group_messages`.
class ChatService {
  ChatService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _sb => _client ?? supabase;

  static const _select =
      'id, group_id, sender_id, body, created_at, '
      'profiles(display_name, photo_url)';

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  /// Historial reciente (más antiguos primero para ListView).
  Future<List<GroupMessage>> listRecent({
    required String groupId,
    int limit = 100,
  }) async {
    final rows = await _sb
        .from('group_messages')
        .select(_select)
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(limit);

    final list = (rows as List)
        .map((e) => GroupMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return list.reversed.toList();
  }

  Future<GroupMessage> send({
    required String groupId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El mensaje no puede estar vacío.');
    }
    if (trimmed.length > 2000) {
      throw ArgumentError('El mensaje es demasiado largo (máx. 2000).');
    }

    final row = await _sb
        .from('group_messages')
        .insert({
          'group_id': groupId,
          'sender_id': _uid,
          'body': trimmed,
        })
        .select(_select)
        .single();

    return GroupMessage.fromMap(Map<String, dynamic>.from(row));
  }

  /// Completa nombre/foto si el INSERT Realtime no trae embed.
  Future<GroupMessage> enrich(GroupMessage message) async {
    if ((message.senderName?.trim().isNotEmpty ?? false) &&
        (message.senderPhotoUrl?.trim().isNotEmpty ?? false)) {
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
      debugPrint('ChatService.enrich: $e');
      return message;
    }
  }

  RealtimeChannel subscribeGroup({
    required String groupId,
    required void Function(GroupMessage message) onInsert,
  }) {
    final channel = _sb.channel(
      'group_messages_${groupId}_${DateTime.now().millisecondsSinceEpoch}',
    );
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) {
            try {
              final map = Map<String, dynamic>.from(payload.newRecord);
              onInsert(GroupMessage.fromMap(map));
            } catch (e) {
              debugPrint('ChatService.subscribe insert parse: $e');
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

  /// Detecta error típico cuando falta la migración SQL.
  static bool looksLikeMissingTable(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('group_messages') &&
        (s.contains('does not exist') ||
            s.contains('42p01') ||
            s.contains('404') ||
            s.contains('schema cache') ||
            s.contains('could not find'));
  }
}
