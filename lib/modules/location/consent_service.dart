import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

class LocationConsent {
  const LocationConsent({
    required this.id,
    required this.sharerId,
    required this.scope,
    required this.status,
    this.groupId,
    this.viewerId,
  });

  final String id;
  final String sharerId;
  final String scope;
  final String status;
  final String? groupId;
  final String? viewerId;

  factory LocationConsent.fromMap(Map<String, dynamic> map) {
    return LocationConsent(
      id: map['id'] as String,
      sharerId: map['sharer_id'] as String,
      scope: map['scope'] as String,
      status: map['status'] as String,
      groupId: map['group_id'] as String?,
      viewerId: map['viewer_id'] as String?,
    );
  }

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
}

class ConsentService {
  ConsentService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  Future<bool> isGloballyPaused() async {
    final row = await _sb
        .from('user_settings')
        .select('share_location_globally_paused')
        .eq('user_id', _uid)
        .maybeSingle();
    if (row == null) return false;
    return row['share_location_globally_paused'] as bool? ?? false;
  }

  Future<void> setGloballyPaused(bool paused) async {
    await _sb.from('user_settings').upsert({
      'user_id': _uid,
      'share_location_globally_paused': paused,
    });
  }

  Future<List<LocationConsent>> listOwnGroupConsents() async {
    final rows = await _sb
        .from('location_consents')
        .select('id, sharer_id, scope, status, group_id, viewer_id')
        .eq('sharer_id', _uid)
        .eq('scope', 'group');

    return (rows as List)
        .map(
          (e) => LocationConsent.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Consentimientos de alcance grupo visibles para el miembro (RLS de grupo).
  Future<List<LocationConsent>> listGroupConsents(String groupId) async {
    final rows = await _sb
        .from('location_consents')
        .select('id, sharer_id, scope, status, group_id, viewer_id')
        .eq('group_id', groupId)
        .eq('scope', 'group');

    return (rows as List)
        .map(
          (e) => LocationConsent.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Activa consentimiento de alcance grupo (upsert por índice único).
  Future<void> acceptShareWithGroup(String groupId) async {
    final existing = await _sb
        .from('location_consents')
        .select('id')
        .eq('sharer_id', _uid)
        .eq('scope', 'group')
        .eq('group_id', groupId)
        .maybeSingle();

    if (existing != null) {
      await _sb.from('location_consents').update({
        'status': 'active',
        'valid_from': DateTime.now().toUtc().toIso8601String(),
        'valid_until': null,
      }).eq('id', existing['id'] as String);
    } else {
      await _sb.from('location_consents').insert({
        'sharer_id': _uid,
        'scope': 'group',
        'group_id': groupId,
        'status': 'active',
      });
    }

    await setGloballyPaused(false);
  }

  Future<void> pauseShareWithGroup(String groupId) async {
    await _sb
        .from('location_consents')
        .update({'status': 'paused'}).eq('sharer_id', _uid).eq(
          'group_id',
          groupId,
        );
  }

  Future<void> pauseAllOwnConsents() async {
    await _sb
        .from('location_consents')
        .update({'status': 'paused'}).eq('sharer_id', _uid).eq(
          'status',
          'active',
        );
    await setGloballyPaused(true);
  }

  /// Aceptar: activa consentimiento en todos los grupos activos del usuario.
  Future<int> acceptForAllMyGroups(List<String> groupIds) async {
    for (final id in groupIds) {
      await acceptShareWithGroup(id);
    }
    await setGloballyPaused(false);
    return groupIds.length;
  }
}
