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
    return NamedPlace(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      groupId: map['group_id'] as String?,
      name: (map['name'] as String?)?.trim() ?? 'Lugar',
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
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

  /// Lugares visibles por RLS; en mapa: propios + del grupo actual.
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

    final payload = <String, dynamic>{
      'owner_id': _uid,
      'name': trimmed,
      'lat': lat,
      'lon': lon,
    };
    final gid = groupId?.trim();
    if (gid != null && gid.isNotEmpty) {
      payload['group_id'] = gid;
    }

    final row = await _sb
        .from('named_places')
        .insert(payload)
        .select('id, owner_id, group_id, name, lat, lon, created_at')
        .single();

    return NamedPlace.fromMap(row);
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
}
