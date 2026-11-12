import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

class PlaceCategory {
  const PlaceCategory({
    required this.id,
    required this.groupId,
    required this.name,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String name;
  final String createdBy;
  final DateTime createdAt;

  factory PlaceCategory.fromMap(Map<String, dynamic> map) {
    return PlaceCategory(
      id: map['id'].toString(),
      groupId: map['group_id'].toString(),
      name: (map['name'] as String?)?.trim() ?? 'Categoría',
      createdBy: map['created_by'].toString(),
      createdAt: DateTime.parse(map['created_at'].toString()).toUtc(),
    );
  }
}

class NamedPlace {
  const NamedPlace({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.createdAt,
    this.groupId,
    this.description,
    this.photoPath,
    this.categoryId,
  });

  final String id;
  final String ownerId;
  final String? groupId;
  final String? categoryId;
  final String name;
  final String? description;
  final String? photoPath;
  final double lat;
  final double lon;
  final DateTime createdAt;

  bool get isShared => groupId != null && groupId!.trim().isNotEmpty;
  bool get hasPhoto => photoPath != null && photoPath!.trim().isNotEmpty;

  factory NamedPlace.fromMap(Map<String, dynamic> map) {
    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.parse(v.toString());
    }

    return NamedPlace(
      id: map['id'].toString(),
      ownerId: map['owner_id'].toString(),
      groupId: map['group_id']?.toString(),
      categoryId: map['category_id']?.toString(),
      name: (map['name'] as String?)?.trim() ?? 'Lugar',
      description: (map['description'] as String?)?.trim(),
      photoPath: (map['photo_path'] as String?)?.trim(),
      lat: asDouble(map['lat']),
      lon: asDouble(map['lon']),
      createdAt: DateTime.parse(map['created_at'].toString()).toUtc(),
    );
  }
}

class NamedPlacesService {
  NamedPlacesService({SupabaseClient? client}) : _client = client;

  static const photoBucket = 'place-photos';
  static const _placeSelect =
      'id, owner_id, group_id, category_id, name, description, photo_path, '
      'lat, lon, created_at';

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  String? publicPhotoUrl(String? path, {bool cacheBust = false}) {
    final p = path?.trim();
    if (p == null || p.isEmpty) return null;
    final url = _sb.storage.from(photoBucket).getPublicUrl(p);
    if (!cacheBust) return url;
    final bust = DateTime.now().millisecondsSinceEpoch;
    return '$url${url.contains('?') ? '&' : '?'}v=$bust';
  }

  Future<List<NamedPlace>> listVisible({String? groupId}) async {
    final uid = _uid;
    final gid = groupId?.trim();
    final rows = await _sb
        .from('named_places')
        .select(_placeSelect)
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

  Future<List<NamedPlace>> listForGroup(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('named_places')
          .select(_placeSelect)
          .eq('group_id', gid)
          .order('created_at', ascending: false)
          .limit(120);

      return (rows as List)
          .map((e) => NamedPlace.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // Fallback si faltan columnas nuevas (description/photo/category).
      debugPrint('listForGroup fallback: $e');
      final rows = await _sb
          .from('named_places')
          .select('id, owner_id, group_id, name, lat, lon, created_at')
          .eq('group_id', gid)
          .order('created_at', ascending: false)
          .limit(120);
      return (rows as List)
          .map((e) => NamedPlace.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  }

  Future<List<PlaceCategory>> listCategories(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('place_categories')
          .select('id, group_id, name, created_by, created_at')
          .eq('group_id', gid)
          .order('name', ascending: true);

      return (rows as List)
          .map(
            (e) => PlaceCategory.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('listCategories: $e');
      return const [];
    }
  }

  Future<PlaceCategory> createCategory({
    required String groupId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre de la categoría no puede estar vacío.');
    }
    try {
      final row = await _sb.rpc(
        'create_place_category',
        params: {
          'p_group_id': groupId.trim(),
          'p_name': trimmed,
        },
      );
      if (row is Map) {
        return PlaceCategory.fromMap(Map<String, dynamic>.from(row));
      }
      throw StateError('Respuesta vacía de create_place_category.');
    } on PostgrestException catch (e) {
      if (looksLikeMissingPhotoColumns(e) || looksLikeMissingRpc(e)) {
        throw StateError(
          'Falta APPLY SQL: 20261102284300_named_places_photos.sql '
          '(named_places_photos_ok = true). Guía: docs/PLACES_ES.md',
        );
      }
      throw StateError(e.message);
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    await _sb.from('place_categories').delete().eq('id', categoryId);
  }

  Future<NamedPlace> create({
    required String name,
    required double lat,
    required double lon,
    String? groupId,
    String? description,
    String? photoPath,
    String? categoryId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre del lugar no puede estar vacío.');
    }
    if (trimmed.length > 80) {
      throw ArgumentError('El nombre es demasiado largo (máx. 80).');
    }
    final desc = description?.trim();
    if (desc != null && desc.length > 280) {
      throw ArgumentError('La descripción es demasiado larga (máx. 280).');
    }

    final gid = groupId?.trim();
    final groupArg = (gid != null && gid.isNotEmpty) ? gid : null;
    final photo = photoPath?.trim();
    final cat = categoryId?.trim();

    try {
      final row = await _sb.rpc(
        'save_named_place',
        params: {
          'p_name': trimmed,
          'p_lat': lat,
          'p_lon': lon,
          'p_group_id': groupArg,
          'p_description': (desc != null && desc.isNotEmpty) ? desc : null,
          'p_photo_path': (photo != null && photo.isNotEmpty) ? photo : null,
          'p_category_id': (cat != null && cat.isNotEmpty) ? cat : null,
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
        'code=${e.code} message=${e.message} details=${e.details}',
      );
      if (looksLikeMissingRpc(e) || looksLikeMissingPhotoColumns(e)) {
        throw StateError(
          'Falta APPLY SQL: 20261102284300_named_places_photos.sql '
          '(named_places_photos_ok = true). Guía: docs/PLACES_ES.md',
        );
      }
      throw StateError(
        [
          e.message,
          if (e.code != null && e.code!.isNotEmpty) 'code=${e.code}',
          if (e.details != null) 'details=${e.details}',
        ].join(' · '),
      );
    } catch (e) {
      if (looksLikeMissingRpc(e) || looksLikeMissingPhotoColumns(e)) {
        throw StateError(
          'Falta APPLY SQL: 20261102284300_named_places_photos.sql '
          '(named_places_photos_ok = true). Guía: docs/PLACES_ES.md',
        );
      }
      rethrow;
    }
  }

  Future<NamedPlace> createWithOptionalPhoto({
    required String name,
    required double lat,
    required double lon,
    String? groupId,
    String? description,
    String? categoryId,
    Uint8List? photoJpeg,
  }) async {
    final created = await create(
      name: name,
      lat: lat,
      lon: lon,
      groupId: groupId,
      description: description,
      categoryId: categoryId,
    );
    if (photoJpeg == null || photoJpeg.isEmpty) return created;
    try {
      return await attachPhoto(placeId: created.id, jpegBytes: photoJpeg);
    } catch (e) {
      debugPrint('place photo upload after create: $e');
      return created;
    }
  }

  Future<NamedPlace> attachPhoto({
    required String placeId,
    required Uint8List jpegBytes,
  }) async {
    final uid = _uid;
    final path = '$uid/$placeId.jpg';
    await _sb.storage.from(photoBucket).uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final rows = await _sb
        .from('named_places')
        .update({'photo_path': path})
        .eq('id', placeId)
        .eq('owner_id', uid)
        .select(_placeSelect)
        .limit(1);
    if (rows.isNotEmpty) {
      return NamedPlace.fromMap(Map<String, dynamic>.from(rows.first as Map));
    }
    return NamedPlace(
      id: placeId,
      ownerId: uid,
      name: '',
      lat: 0,
      lon: 0,
      createdAt: DateTime.now().toUtc(),
      photoPath: path,
    );
  }

  Future<void> delete(String id) async {
    final uid = _uid;
    try {
      final rows = await _sb
          .from('named_places')
          .select('photo_path, owner_id')
          .eq('id', id)
          .limit(1);
      if (rows.isNotEmpty) {
        final map = Map<String, dynamic>.from(rows.first as Map);
        final path = (map['photo_path'] as String?)?.trim();
        final owner = map['owner_id']?.toString();
        if (path != null && path.isNotEmpty && owner == uid) {
          await _sb.storage.from(photoBucket).remove([path]);
        }
      }
    } catch (_) {}

    await _sb.from('named_places').delete().eq('id', id);
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
    return (s.contains('save_named_place') ||
            s.contains('create_place_category') ||
            s.contains('place_categories')) &&
        (s.contains('pgrst202') ||
            s.contains('could not find') ||
            s.contains('404') ||
            s.contains('does not exist') ||
            s.contains('schema cache') ||
            s.contains('function'));
  }

  static bool looksLikeMissingPhotoColumns(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('photo_path') ||
        s.contains('description') ||
        s.contains('category_id') ||
        s.contains('place_categories') ||
        s.contains('p_description') ||
        s.contains('p_photo_path') ||
        s.contains('p_category_id') ||
        s.contains('place-photos');
  }
}
