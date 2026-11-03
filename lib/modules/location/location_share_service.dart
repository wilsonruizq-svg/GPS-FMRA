import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'consent_service.dart';

/// Última ubicación conocida de un miembro (fila en `location_updates`).
class MemberLocation {
  const MemberLocation({
    required this.userId,
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.accuracyM,
  });

  final String userId;
  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? accuracyM;

  factory MemberLocation.fromMap(Map<String, dynamic> map) {
    return MemberLocation(
      userId: map['user_id'] as String,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String).toUtc(),
    );
  }
}

/// Publica GPS propio (con consentimiento) y lee ubicaciones visibles vía RLS/RPC.
class LocationShareService {
  LocationShareService({
    this._client,
    ConsentService? consent,
  }) : _consent = consent ?? ConsentService();

  final SupabaseClient? _client;
  final ConsentService _consent;

  SupabaseClient get _sb => _client ?? supabase;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  /// True si el usuario puede publicar: consentimiento activo del grupo y
  /// sin pausa global.
  Future<bool> canPublishForGroup(String groupId) async {
    final paused = await _consent.isGloballyPaused();
    if (paused) return false;
    final consents = await _consent.listOwnGroupConsents();
    return consents.any((c) => c.groupId == groupId && c.isActive);
  }

  /// Upsert de la ubicación actual. Solo debe llamarse con consentimiento activo.
  Future<void> publishPosition(Position pos) async {
    final now = DateTime.now().toUtc();
    await _sb.from('location_updates').upsert({
      'user_id': _uid,
      'lat': pos.latitude,
      'lon': pos.longitude,
      'accuracy_m': pos.accuracy.isFinite ? pos.accuracy : null,
      'recorded_at': now.toIso8601String(),
      'is_mocked': pos.isMocked,
    }, onConflict: 'user_id');
  }

  /// Ubicaciones visibles del grupo (RPC `list_group_locations`).
  /// Fallback a SELECT directo filtrado por [memberIds] si el RPC aún no
  /// está aplicado en el proyecto.
  Future<List<MemberLocation>> fetchGroupLocations({
    required String groupId,
    required List<String> memberIds,
  }) async {
    try {
      final rows = await _sb.rpc(
        'list_group_locations',
        params: {'p_group_id': groupId},
      );
      return _mapRows(rows);
    } catch (_) {
      return fetchVisibleLocations(memberIds);
    }
  }

  /// Carga ubicaciones de los [userIds] visibles. RLS + `can_view_location`
  /// ocultan a quienes no tienen consentimiento activo.
  Future<List<MemberLocation>> fetchVisibleLocations(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const [];

    final rows = await _sb
        .from('location_updates')
        .select('user_id, lat, lon, accuracy_m, recorded_at')
        .inFilter('user_id', userIds);

    return _mapRows(rows);
  }

  List<MemberLocation> _mapRows(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .map(
          (e) => MemberLocation.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Suscripción Realtime a `location_updates` (RLS aplica a los eventos).
  /// Devuelve el canal; el caller debe `unsubscribe` / `removeChannel`.
  RealtimeChannel subscribeLocationUpdates({
    required void Function(MemberLocation location) onChange,
    required void Function(String userId) onDelete,
  }) {
    final channel = _sb.channel(
      'location_updates_${_uid}_${DateTime.now().millisecondsSinceEpoch}',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'location_updates',
      callback: (payload) {
        final loc = _fromPayload(payload.newRecord);
        if (loc != null) onChange(loc);
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'location_updates',
      callback: (payload) {
        final loc = _fromPayload(payload.newRecord);
        if (loc != null) onChange(loc);
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'location_updates',
      callback: (payload) {
        final id = payload.oldRecord['user_id'] as String?;
        if (id != null) onDelete(id);
      },
    );

    channel.subscribe();
    return channel;
  }

  MemberLocation? _fromPayload(Map<String, dynamic> record) {
    if (record.isEmpty || record['user_id'] == null) return null;
    try {
      return MemberLocation.fromMap(record);
    } catch (_) {
      return null;
    }
  }
}
