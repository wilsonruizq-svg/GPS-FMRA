import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

class FamilyGroup {
  const FamilyGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.status,
  });

  final String id;
  final String name;
  final String createdBy;
  final String status;

  factory FamilyGroup.fromMap(Map<String, dynamic> map) {
    return FamilyGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      createdBy: map['created_by'] as String,
      status: map['status'] as String? ?? 'active',
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.membershipId,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
  });

  final String membershipId;
  final String groupId;
  final String userId;
  final String role;
  final String status;
  final String? displayName;

  String get label =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : 'Miembro';

  bool get isAdmin => role == 'group_admin' || role == 'org_admin';
}

class InviteStub {
  const InviteStub({
    required this.invitationId,
    required this.plainToken,
    required this.expiresAt,
  });

  final String invitationId;
  final String plainToken;
  final DateTime expiresAt;

  /// Enlace mínimo (stub): la aceptación real irá por Edge Function.
  String get linkStub => 'gpsfmra://invite/$plainToken';
}

class GroupsService {
  GroupsService({this._client});

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  String get _uid {
    final id = _sb.auth.currentUser?.id;
    if (id == null) throw StateError('No hay sesión activa.');
    return id;
  }

  Future<List<FamilyGroup>> listMyGroups() async {
    final memberships = await _sb
        .from('group_memberships')
        .select('group_id')
        .eq('user_id', _uid)
        .eq('status', 'active');

    final groupIds = (memberships as List)
        .map((e) => (e as Map)['group_id'] as String)
        .toSet()
        .toList();

    if (groupIds.isEmpty) return const [];

    final rows = await _sb
        .from('family_groups')
        .select('id, name, created_by, status')
        .inFilter('id', groupIds)
        .eq('status', 'active')
        .order('created_at');

    return (rows as List)
        .map((e) => FamilyGroup.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Inserta el grupo; el trigger añade al creador como `group_admin`.
  Future<FamilyGroup> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre del grupo no puede estar vacío.');
    }

    final row = await _sb
        .from('family_groups')
        .insert({
          'name': trimmed,
          'created_by': _uid,
        })
        .select('id, name, created_by, status')
        .single();

    return FamilyGroup.fromMap(row);
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final rows = await _sb
        .from('group_memberships')
        .select(
          'id, group_id, user_id, role, status, profiles(display_name)',
        )
        .eq('group_id', groupId)
        .eq('status', 'active')
        .order('joined_at');

    return (rows as List).map((raw) {
      final e = Map<String, dynamic>.from(raw as Map);
      final profile = e['profiles'];
      String? displayName;
      if (profile is Map) {
        displayName = profile['display_name'] as String?;
      }
      return GroupMember(
        membershipId: e['id'] as String,
        groupId: e['group_id'] as String,
        userId: e['user_id'] as String,
        role: (e['role'] as String?) ?? 'member',
        status: (e['status'] as String?) ?? 'active',
        displayName: displayName,
      );
    }).toList();
  }

  /// Stub de invitación: genera token en claro (solo UI), guarda SHA-256.
  Future<InviteStub> createInviteStub(String groupId) async {
    final plain = _randomToken(24);
    final hash = sha256.convert(utf8.encode(plain)).toString();
    final expires = DateTime.now().toUtc().add(const Duration(days: 7));

    final row = await _sb
        .from('invitations')
        .insert({
          'group_id': groupId,
          'invited_by': _uid,
          'token_hash': hash,
          'expires_at': expires.toIso8601String(),
          'status': 'pending',
          'max_uses': 1,
        })
        .select('id')
        .single();

    return InviteStub(
      invitationId: row['id'] as String,
      plainToken: plain,
      expiresAt: expires,
    );
  }

  static String _randomToken(int length) {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rnd.nextInt(alphabet.length)],
    ).join();
  }
}
