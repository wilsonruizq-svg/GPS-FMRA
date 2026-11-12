import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

class NamedPlace {
  const NamedPlace({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.createdAt,
    this.groupId,
  });

  final String id;
  final String ownerId;
  final String? groupId;
  final String name;
  final double lat;
  final double lon;
  final DateTime createdAt;

  bool get isShared => groupId != null && groupId!.trim().isNotEmpty;

  factory NamedPlace.fromMap(Map<String, dynamic> map) {
    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.parse(v.toString());
    }

    DateTime asTime(Object? v) {
      if (v is DateTime) return v.toUtc();
      return DateTime.parse(v.toString()).toUtc();
    }

    return NamedPlace(
      id: map['id'].toString(),
      ownerId: map['owner_id'].toString(),
      groupId: map['group_id']?.toString(),
      name: (map['name'] as String?)?.trim() ?? 'Lugar',
      lat: asDouble(map['lat']),
      lon: asDouble(map['lon']),
      createdAt: asTime(map['created_at']),
    );
  }
}

class NamedPlacesService {
  NamedPlacesService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  Future<List<NamedPlace>> listVisible({String? groupId}) async {
    final uid = _uid;
    final gid = groupId?.trim();
    final rows = await _sb
        .from('named_places')
        .select('id, owner_id, group_id, name, lat, lon, created_at')
        .order('created_at', ascending: false)
        .limit(120);

    return (rows as List)
        .map((e) => NamedPlace.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((p) {
          if (p.ownerId == uid) return true;
          if (gid == null || gid.isEmpty) return false;
          return p.groupId == gid;
        })
        .toList();
  }

  /// Guarda vía RPC `save_named_place` (security definer). Sin sync de mapa.
  Future<NamedPlace> create({
    required String name,
    required double lat,
    required double lon,
    String? groupId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre del lugar no puede estar vacío.');
    }
    if (trimmed.length > 80) {
      throw ArgumentError('El nombre es demasiado largo (máx. 80).');
    }

    final gid = groupId?.trim();
    final groupArg = (gid != null && gid.isNotEmpty) ? gid : null;

    try {
      final row = await _sb.rpc(
        'save_named_place',
        params: {
          'p_name': trimmed,
          'p_lat': lat,
          'p_lon': lon,
          'p_group_id': groupArg,
        },
      );
      if (row is Map) {
        return NamedPlace.fromMap(Map<String, dynamic>.from(row));
      }
      if (row is List && row.isNotEmpty && row.first is Map) {
        return NamedPlace.fromMap(Map<String, dynamic>.from(row.first as Map));
      }
      throw StateError(
        'Respuesta vacía de save_named_place (${row.runtimeType}).',
      );
    } on PostgrestException catch (e) {
      debugPrint(
        'save_named_place PostgrestException: '
        'code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      if (looksLikeMissingRpc(e)) {
        throw StateError(
          'Falta APPLY SQL: 20261102284200_named_places_rpc.sql '
          '(save_named_place_ok = true). Guía: docs/PLACES_ES.md',
        );
      }
      throw StateError(
        [
          e.message,
          if (e.code != null && e.code!.isNotEmpty) 'code=${e.code}',
          if (e.details != null) 'details=${e.details}',
          if (e.hint != null) 'hint=${e.hint}',
        ].join(' · '),
      );
    } catch (e) {
      debugPrint('save_named_place: $e');
      if (looksLikeMissingRpc(e)) {
        throw StateError(
          'Falta APPLY SQL: 20261102284200_named_places_rpc.sql '
          '(save_named_place_ok = true). Guía: docs/PLACES_ES.md',
        );
      }
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _sb.from('named_places').delete().eq('id', id).eq('owner_id', _uid);
  }

  static bool looksLikeMissingTable(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('named_places') &&
        (s.contains('does not exist') ||
            s.contains('42p01') ||
            s.contains('404') ||
            s.contains('schema cache') ||
            s.contains('could not find') ||
            s.contains('pgrst205'));
  }

  static bool looksLikeMissingRpc(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('save_named_place') &&
        (s.contains('pgrst202') ||
            s.contains('could not find') ||
            s.contains('404') ||
            s.contains('does not exist') ||
            s.contains('schema cache') ||
            s.contains('function'));
  }
}
