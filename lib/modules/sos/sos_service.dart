import 'dart:async';

import 'package:flutter/foundation.dart';
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

  SosEvent copyWith({String? displayName}) {
    return SosEvent(
      id: id,
      groupId: groupId,
      userId: userId,
      status: status,
      createdAt: createdAt,
      lat: lat,
      lon: lon,
      note: note,
      displayName: displayName ?? this.displayName,
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

  static const _selectPlain =
      'id, group_id, user_id, lat, lon, note, status, created_at';
  static const _selectWithProfile =
      'id, group_id, user_id, lat, lon, note, status, created_at, profiles(display_name)';

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  /// True si el error indica tabla/RPC ausente en el API (404 / schema cache).
  static bool isMissingApiObject(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('could not find the table') ||
        raw.contains('could not find the function') ||
        raw.contains('schema cache') ||
        raw.contains('pgrst205') ||
        raw.contains('pgrst202') ||
        (raw.contains('404') && raw.contains('sos')) ||
        (raw.contains('relation') &&
            raw.contains('sos_events') &&
            raw.contains('does not exist'));
  }

  /// Alertas activas del grupo (más recientes primero).
  Future<List<SosEvent>> listActiveForGroup(String groupId) async {
    List rows;
    try {
      rows = await _sb
          .from('sos_events')
          .select(_selectWithProfile)
          .eq('group_id', groupId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(20) as List;
    } catch (_) {
      rows = await _sb
          .from('sos_events')
          .select(_selectPlain)
          .eq('group_id', groupId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(20) as List;
    }

    return rows
        .map((e) => SosEvent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Registra SOS. Prefiere RPC `raise_sos`; fallback INSERT directo.
  Future<SosEvent> raise({
    required String groupId,
    double? lat,
    double? lon,
    String? note,
  }) async {
    SosEvent event;
    try {
      event = await _raiseViaRpc(
        groupId: groupId,
        lat: lat,
        lon: lon,
        note: note,
      );
    } catch (e) {
      if (isMissingApiObject(e)) {
        // Tabla/RPC no visibles en API → el caller muestra SQL de fix.
        rethrow;
      }
      debugPrint('SosService.raise RPC falló, intento INSERT: $e');
      event = await _raiseViaInsert(
        groupId: groupId,
        lat: lat,
        lon: lon,
        note: note,
      );
    }

    // Nombre propio para el banner local.
    final myName = _sb.auth.currentUser?.userMetadata?['display_name'] as String?;
    if ((event.displayName == null || event.displayName!.isEmpty) &&
        myName != null &&
        myName.trim().isNotEmpty) {
      event = event.copyWith(displayName: myName.trim());
    }

    unawaited(_notifyPeersBestEffort(event));
    return event;
  }

  Future<SosEvent> _raiseViaRpc({
    required String groupId,
    double? lat,
    double? lon,
    String? note,
  }) async {
    final row = await _sb.rpc(
      'raise_sos',
      params: {
        'p_group_id': groupId,
        'p_lat': lat,
        'p_lon': lon,
        'p_note': note,
      },
    );
    if (row is Map) {
      return SosEvent.fromMap(Map<String, dynamic>.from(row));
    }
    if (row is List && row.isNotEmpty && row.first is Map) {
      return SosEvent.fromMap(Map<String, dynamic>.from(row.first as Map));
    }
    throw StateError('raise_sos no devolvió fila.');
  }

  Future<SosEvent> _raiseViaInsert({
    required String groupId,
    double? lat,
    double? lon,
    String? note,
  }) async {
    // Sin embed profiles: evita fallos de FK/embed tras INSERT.
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
        .select(_selectPlain)
        .single();

    return SosEvent.fromMap(row);
  }

  Future<void> _notifyPeersBestEffort(SosEvent event) async {
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
    } catch (e) {
      debugPrint('SosService.notifyPeersBestEffort: $e');
    }
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
    final channel = _sb.channel(
      'sos_events_${groupId}_${DateTime.now().millisecondsSinceEpoch}',
    );
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
