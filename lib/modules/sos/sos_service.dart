import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// Evento SOS de un integrante del grupo.
class SosEvent {
  const SosEvent({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.lat,
    this.lon,
    this.note,
    this.displayName,
  });

  final String id;
  final String groupId;
  final String userId;
  final String status;
  final DateTime createdAt;
  final double? lat;
  final double? lon;
  final String? note;
  final String? displayName;

  bool get isActive => status == 'active';

  factory SosEvent.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? name;
    if (profile is Map) {
      name = profile['display_name'] as String?;
    }
    return SosEvent(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      userId: map['user_id'] as String,
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      lat: (map['lat'] as num?)?.toDouble(),
      lon: (map['lon'] as num?)?.toDouble(),
      note: map['note'] as String?,
      displayName: name,
    );
  }

  String get label {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Integrante';
  }
}

/// Crea y observa alertas SOS vía Supabase + push FCM (Edge Function).
class SosService {
  SosService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  static const _select =
      'id, group_id, user_id, lat, lon, note, status, created_at, profiles(display_name)';

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  /// Alertas activas del grupo (más recientes primero).
  Future<List<SosEvent>> listActiveForGroup(String groupId) async {
    final rows = await _sb
        .from('sos_events')
        .select(_select)
        .eq('group_id', groupId)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(20);

    return (rows as List)
        .map((e) => SosEvent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Registra SOS. [lat]/[lon] opcionales (si hay GPS).
  /// Tras el insert intenta invocar Edge Function `notify-sos` (FCM).
  Future<SosEvent> raise({
    required String groupId,
    double? lat,
    double? lon,
    String? note,
  }) async {
    final row = await _sb
        .from('sos_events')
        .insert({
          'group_id': groupId,
          'user_id': _uid,
          'lat': lat,
          'lon': lon,
          'note': note,
          'status': 'active',
        })
        .select(_select)
        .single();

    final event = SosEvent.fromMap(row);
    // Best-effort: push a compañeros. Si la función no está desplegada, no falla.
    try {
      await _sb.functions.invoke(
        'notify-sos',
        body: {
          'sos_id': event.id,
          'group_id': event.groupId,
          'user_id': event.userId,
          'display_name': event.displayName,
        },
      );
    } catch (_) {
      // In-app banner / Realtime cubren el caso sin FCM.
    }
    return event;
  }

  /// Cancela o resuelve una alerta propia (o admin vía RLS).
  Future<void> cancel(String eventId) async {
    await _sb.from('sos_events').update({
      'status': 'cancelled',
      'resolved_at': DateTime.now().toUtc().toIso8601String(),
      'resolved_by': _uid,
    }).eq('id', eventId);
  }

  /// Canal Realtime de INSERT/UPDATE del grupo. Caller debe [unsubscribe].
  RealtimeChannel subscribeGroup({
    required String groupId,
    required void Function() onChange,
  }) {
    final channel = _sb.channel('sos_events:$groupId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sos_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel? channel) async {
    if (channel == null) return;
    await _sb.removeChannel(channel);
  }
}
