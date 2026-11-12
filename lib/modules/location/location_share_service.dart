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

/// Punto de historial (tabla `location_history`).
class HistoryPoint {
  const HistoryPoint({
    required this.id,
    required this.userId,
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.accuracyM,
    this.displayName,
  });

  final String id;
  final String userId;
  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? accuracyM;
  final String? displayName;

  factory HistoryPoint.fromMap(Map<String, dynamic> map) {
    return HistoryPoint(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String).toUtc(),
      displayName: map['display_name'] as String?,
    );
  }

  String get label {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Integrante';
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

  /// Historial: como máximo 1 fila cada 5 minutos (el live sigue en heartbeat).
  static const historyMinInterval = Duration(minutes: 5);

  /// Si se movió menos que esto vs el último historial, no se guarda duplicado.
  static const historySamePlaceMeters = 5.0;

  /// Estado compartido entre instancias (MapShell puede recrear el service).
  static DateTime? _lastHistoryAt;
  static double? _lastHistoryLat;
  static double? _lastHistoryLon;
  static bool _historyHydrated = false;

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
  /// Historial: best-effort, máx. cada [historyMinInterval] y sin duplicar
  /// el mismo punto estático.
  Future<void> publishPosition(Position pos) async {
    final now = DateTime.now().toUtc();
    final payload = {
      'user_id': _uid,
      'lat': pos.latitude,
      'lon': pos.longitude,
      'accuracy_m': pos.accuracy.isFinite ? pos.accuracy : null,
      'recorded_at': now.toIso8601String(),
      'is_mocked': pos.isMocked,
    };
    await _sb.from('location_updates').upsert(
      payload,
      onConflict: 'user_id',
    );
    await _maybeAppendHistory(pos, now);
  }

  Future<void> _hydrateLastHistoryIfNeeded() async {
    if (_historyHydrated) return;
    _historyHydrated = true;
    try {
      final rows = await _sb
          .from('location_history')
          .select('lat, lon, recorded_at')
          .eq('user_id', _uid)
          .order('recorded_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first);
      _lastHistoryLat = (row['lat'] as num?)?.toDouble();
      _lastHistoryLon = (row['lon'] as num?)?.toDouble();
      final raw = row['recorded_at'] as String?;
      if (raw != null) {
        _lastHistoryAt = DateTime.parse(raw).toUtc();
      }
    } catch (_) {
      // Sin historial APPLY / red: el muestreo arranca en frío.
    }
  }

  Future<void> _maybeAppendHistory(Position pos, DateTime now) async {
    try {
      await _hydrateLastHistoryIfNeeded();

      final lastAt = _lastHistoryAt;
      if (lastAt != null && now.difference(lastAt) < historyMinInterval) {
        return;
      }

      final prevLat = _lastHistoryLat;
      final prevLon = _lastHistoryLon;
      if (prevLat != null && prevLon != null) {
        final movedM = Geolocator.distanceBetween(
          prevLat,
          prevLon,
          pos.latitude,
          pos.longitude,
        );
        if (movedM < historySamePlaceMeters) {
          // Estático: no duplicar. Avanza el reloj para no reintentar en loop.
          _lastHistoryAt = now;
          return;
        }
      }

      await _sb.from('location_history').insert({
        'user_id': _uid,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'accuracy_m': pos.accuracy.isFinite ? pos.accuracy : null,
        'recorded_at': now.toIso8601String(),
      });
      _lastHistoryAt = now;
      _lastHistoryLat = pos.latitude;
      _lastHistoryLon = pos.longitude;
    } catch (_) {
      // Historial aún no APPLY / red: el mapa en vivo sigue OK.
    }
  }

  /// Historial reciente visible del grupo (RPC). Vacío si no APPLY / sin permiso.
  Future<List<HistoryPoint>> fetchGroupHistory({
    required String groupId,
    int hours = 24,
    int limit = 200,
  }) async {
    try {
      final rows = await _sb.rpc(
        'list_group_location_history',
        params: {
          'p_group_id': groupId,
          'p_hours': hours,
          'p_limit': limit,
        },
      );
      if (rows is! List) return const [];
      return rows
          .map(
            (e) => HistoryPoint.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
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
