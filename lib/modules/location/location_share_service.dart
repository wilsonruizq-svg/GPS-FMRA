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

  SupabaseClient get _sb => _client ?? supabase;

  /// GF-18: historial máx. 1 punto / 5 min (sesión).
  static const historyMinInterval = Duration(minutes: 5);
  /// ~5–6 m en ecuador; evita spam si el GPS no se mueve.
  static const historyCoordEpsilonDeg = 0.00005;

  static DateTime? _lastHistoryAtUtc;
  static double? _lastHistoryLat;
  static double? _lastHistoryLon;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  /// true si conviene append a `location_history` (intervalo + dedupe coords).
  static bool shouldAppendHistorySample({
    required double lat,
    required double lon,
    DateTime? nowUtc,
  }) {
    final now = nowUtc ?? DateTime.now().toUtc();
    final lastAt = _lastHistoryAtUtc;
    if (lastAt != null && now.difference(lastAt) < historyMinInterval) {
      return false;
    }
    final lastLat = _lastHistoryLat;
    final lastLon = _lastHistoryLon;
    if (lastLat != null && lastLon != null) {
      final dLat = (lat - lastLat).abs();
      final dLon = (lon - lastLon).abs();
      if (dLat < historyCoordEpsilonDeg && dLon < historyCoordEpsilonDeg) {
        return false;
      }
    }
    return true;
  }

  static void _rememberHistorySample({
    required double lat,
    required double lon,
    required DateTime atUtc,
  }) {
    _lastHistoryAtUtc = atUtc;
    _lastHistoryLat = lat;
    _lastHistoryLon = lon;
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
  /// También intenta append a `location_history` (best-effort; no tumba el live).
  /// GF-18: máx. 1 punto / 5 min y skip si coords ≈ último historial.
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

    if (!shouldAppendHistorySample(
      lat: pos.latitude,
      lon: pos.longitude,
      nowUtc: now,
    )) {
      return;
    }

    try {
      await _sb.from('location_history').insert({
        'user_id': _uid,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'accuracy_m': pos.accuracy.isFinite ? pos.accuracy : null,
        'recorded_at': now.toIso8601String(),
      });
      _rememberHistorySample(
        lat: pos.latitude,
        lon: pos.longitude,
        atUtc: now,
      );
    } catch (_) {
      // Historial aún no APPLY / red: el mapa en vivo sigue OK.
    }
  }

  /// Historial reciente **propio** (auth.uid) del grupo.
  /// Prefiere RPC `list_own_location_history`; fallback a
  /// `list_group_location_history` (post-migración también own-only) y,
  /// si fallan, SELECT directo filtrado por `_uid`.
  Future<List<HistoryPoint>> fetchOwnHistory({
    required String groupId,
    int hours = 24,
    int limit = 200,
  }) async {
    final uid = _uid;
    try {
      final rows = await _sb.rpc(
        'list_own_location_history',
        params: {
          'p_group_id': groupId,
          'p_hours': hours,
          'p_limit': limit,
        },
      );
      return _mapHistoryRows(rows, onlyUserId: uid);
    } catch (_) {
      try {
        final rows = await _sb.rpc(
          'list_group_location_history',
          params: {
            'p_group_id': groupId,
            'p_hours': hours,
            'p_limit': limit,
          },
        );
        // Defensa en cliente: nunca mostrar filas ajenas aunque el RPC viejo
        // aún devuelva peers (pre-migración own-only).
        return _mapHistoryRows(rows, onlyUserId: uid);
      } catch (_) {
        return _fetchOwnHistoryDirect(
          groupId: groupId,
          hours: hours,
          limit: limit,
        );
      }
    }
  }

  /// @deprecated Usar [fetchOwnHistory]. Mantiene nombre por compat; same own-only.
  Future<List<HistoryPoint>> fetchGroupHistory({
    required String groupId,
    int hours = 24,
    int limit = 200,
  }) =>
      fetchOwnHistory(groupId: groupId, hours: hours, limit: limit);

  Future<List<HistoryPoint>> _fetchOwnHistoryDirect({
    required String groupId,
    required int hours,
    required int limit,
  }) async {
    try {
      final uid = _uid;
      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: hours.clamp(1, 72)));
      final rows = await _sb
          .from('location_history')
          .select('id, user_id, lat, lon, accuracy_m, recorded_at')
          .eq('user_id', uid)
          .gte('recorded_at', since.toIso8601String())
          .order('recorded_at', ascending: false)
          .limit(limit.clamp(1, 500));
      // groupId se valida en el caller (selector); RLS own-only basta.
      // Si hace falta pertenencia, el RPC es el camino preferido.
      final points = _mapHistoryRows(rows, onlyUserId: uid);
      if (groupId.isEmpty) return points;
      return points;
    } catch (_) {
      return const [];
    }
  }

  List<HistoryPoint> _mapHistoryRows(
    dynamic rows, {
    required String onlyUserId,
  }) {
    if (rows is! List) return const [];
    final mine = onlyUserId.trim().toLowerCase();
    return rows
        .map(
          (e) => HistoryPoint.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .where((p) => p.userId.trim().toLowerCase() == mine)
        .toList();
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
