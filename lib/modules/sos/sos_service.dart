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
    String? name = map['display_name'] as String?;
    if ((name == null || name.trim().isEmpty) && profile is Map) {
      name = profile['display_name'] as String?;
    }
    // IDs siempre String normalizado (PostgREST a veces entrega uuid dinámico).
    final id = '${map['id']}'.trim();
    final groupId = '${map['group_id']}'.trim();
    final userId = '${map['user_id']}'.trim();
    if (id.isEmpty || id == 'null') {
      throw FormatException('sos_events.id inválido');
    }
    return SosEvent(
      id: id,
      groupId: groupId,
      userId: userId,
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

/// Progreso de acuses Aceptar para un SOS (vista del emisor).
class SosAckProgress {
  const SosAckProgress({
    required this.sosId,
    required this.members,
  });

  final String sosId;
  final List<SosAckMember> members;

  /// Compañeros que deben aceptar (todos excepto el emisor).
  List<SosAckMember> get expectedPeers =>
      members.where((m) => !m.isSender).toList();

  List<SosAckMember> get pendingPeers =>
      expectedPeers.where((m) => !m.acked).toList();

  List<SosAckMember> get ackedPeers =>
      expectedPeers.where((m) => m.acked).toList();

  int get expectedCount => expectedPeers.length;
  int get ackedCount => ackedPeers.length;
  bool get allPeersAcked =>
      expectedCount == 0 || ackedCount >= expectedCount;
}

class SosAckMember {
  const SosAckMember({
    required this.userId,
    required this.displayName,
    required this.isSender,
    required this.acked,
    this.ackedAt,
  });

  final String userId;
  final String displayName;
  final bool isSender;
  final bool acked;
  final DateTime? ackedAt;
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
        (raw.contains('404') &&
            (raw.contains('sos') ||
                raw.contains('ack_sos') ||
                raw.contains('sos_acks'))) ||
        (raw.contains('relation') &&
            (raw.contains('sos_events') || raw.contains('sos_acks')) &&
            raw.contains('does not exist'));
  }

  /// Red / TLS / DNS (no confundir con “falta SQL”).
  static bool isConnectivityError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection reset') ||
        raw.contains('connection refused') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('handshake') ||
        raw.contains('certificate') ||
        raw.contains('ssl') ||
        raw.contains('tls') ||
        raw.contains('clientexception') ||
        raw.contains('xmlhttprequest');
  }

  /// Alertas activas del grupo (más recientes primero).
  /// Siempre intenta resolver `display_name` del emisor (embed o query profiles).
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

    final events = rows
        .map((e) => SosEvent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return _enrichDisplayNames(events);
  }

  /// Completa display_name faltante con `profiles` (batch).
  Future<List<SosEvent>> _enrichDisplayNames(List<SosEvent> events) async {
    final missingIds = events
        .where(
          (e) => e.displayName == null || e.displayName!.trim().isEmpty,
        )
        .map((e) => e.userId)
        .toSet()
        .toList();
    if (missingIds.isEmpty) return events;

    try {
      final rows = await _sb
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', missingIds);
      final names = <String, String>{};
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String?;
        final name = (map['display_name'] as String?)?.trim();
        if (id != null && name != null && name.isNotEmpty) {
          names[id] = name;
        }
      }
      if (names.isEmpty) return events;
      return [
        for (final e in events)
          (e.displayName == null || e.displayName!.trim().isEmpty) &&
                  names.containsKey(e.userId)
              ? e.copyWith(displayName: names[e.userId])
              : e,
      ];
    } catch (e) {
      debugPrint('SosService._enrichDisplayNames: $e');
      return events;
    }
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

    // Nombre del emisor para banner / push.
    if (event.displayName == null || event.displayName!.trim().isEmpty) {
      final enriched = await _enrichDisplayNames([event]);
      event = enriched.first;
    }
    if (event.displayName == null || event.displayName!.trim().isEmpty) {
      final meta =
          _sb.auth.currentUser?.userMetadata?['display_name'] as String?;
      if (meta != null && meta.trim().isNotEmpty) {
        event = event.copyWith(displayName: meta.trim());
      }
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

  /// Compañero pulsa Aceptar → registra ack; si todos aceptaron, resuelve el SOS.
  /// Prefiere RPC `ack_sos`; si el schema cache no lo ve, fallback INSERT en
  /// `sos_acks` + `try_resolve_sos_if_all_acked` (misma semántica RLS).
  Future<bool> acknowledge(String sosId) async {
    final id = sosId.trim();
    if (id.isEmpty) {
      throw ArgumentError('sosId vacío');
    }
    try {
      final raw = await _sb.rpc('ack_sos', params: {'p_sos_id': id});
      if (raw is Map) {
        return raw['all_acked'] == true;
      }
      return false;
    } catch (e) {
      if (!isMissingApiObject(e)) rethrow;
      return _acknowledgeViaInsert(id);
    }
  }

  Future<bool> _acknowledgeViaInsert(String sosId) async {
    await _sb.from('sos_acks').upsert(
      {
        'sos_id': sosId,
        'user_id': _uid,
      },
      onConflict: 'sos_id,user_id',
    );
    try {
      final raw = await _sb.rpc(
        'try_resolve_sos_if_all_acked',
        params: {'p_sos_id': sosId},
      );
      return raw == true;
    } catch (_) {
      // Ack quedó guardado; el resolve puede llegar en el siguiente poll.
      return false;
    }
  }

  /// Si no hay otros miembros, resuelve de inmediato (todos = vacío).
  Future<void> tryResolveIfAllAcked(String sosId) async {
    try {
      await _sb.rpc(
        'try_resolve_sos_if_all_acked',
        params: {'p_sos_id': sosId},
      );
    } catch (e) {
      debugPrint('SosService.tryResolveIfAllAcked: $e');
    }
  }

  /// Emisor: quién aceptó / quién falta.
  Future<SosAckProgress> listAckProgress(String sosId) async {
    final rows = await _sb.rpc(
      'list_sos_ack_progress',
      params: {'p_sos_id': sosId},
    );
    final members = <SosAckMember>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final ackedAtRaw = map['acked_at'] as String?;
        members.add(
          SosAckMember(
            userId: '${map['user_id']}'.trim(),
            displayName:
                ((map['display_name'] as String?)?.trim().isNotEmpty == true)
                    ? (map['display_name'] as String).trim()
                    : 'Integrante',
            isSender: map['is_sender'] == true,
            acked: map['acked'] == true,
            ackedAt: ackedAtRaw != null
                ? DateTime.tryParse(ackedAtRaw)?.toUtc()
                : null,
          ),
        );
      }
    }
    return SosAckProgress(sosId: sosId, members: members);
  }

  /// Ids de SOS (de [sosIds]) que el usuario actual ya aceptó.
  Future<Set<String>> listMyAckedSosIds(Iterable<String> sosIds) async {
    final ids = sosIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _sb
          .from('sos_acks')
          .select('sos_id')
          .eq('user_id', _uid)
          .inFilter('sos_id', ids);
      final out = <String>{};
      for (final row in (rows as List)) {
        final id = '${(row as Map)['sos_id']}'.trim().toLowerCase();
        if (id.isNotEmpty && id != 'null') out.add(id);
      }
      return out;
    } catch (e) {
      debugPrint('SosService.listMyAckedSosIds: $e');
      return {};
    }
  }

  /// Canal Realtime de INSERT/UPDATE del grupo (+ acks). Caller debe [unsubscribe].
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
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_acks',
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
