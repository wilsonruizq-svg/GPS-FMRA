import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import '../location/consent_service.dart';
import 'invite_token.dart';

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

  FamilyGroup copyWith({String? name, String? status}) {
    return FamilyGroup(
      id: id,
      name: name ?? this.name,
      createdBy: createdBy,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FamilyGroup && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class GroupMember {
  const GroupMember({
    required this.membershipId,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
    this.photoUrl,
    this.gender,
  });

  final String membershipId;
  final String groupId;
  final String userId;
  final String role;
  final String status;
  final String? displayName;
  final String? photoUrl;
  /// `female` | `male` | null (mapa usa heurística por nombre).
  final String? gender;

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

  /// Enlace mínimo (stub): la app puede pegar el código o el enlace.
  String get linkStub => InviteToken.linkStub(plainToken);
}

class AcceptInviteResult {
  const AcceptInviteResult({
    required this.groupId,
    required this.groupName,
    required this.role,
    required this.alreadyMember,
    this.membershipId,
  });

  final String groupId;
  final String groupName;
  final String role;
  final bool alreadyMember;
  final String? membershipId;

  factory AcceptInviteResult.fromJson(Map<String, dynamic> json) {
    return AcceptInviteResult(
      groupId: json['group_id'] as String,
      groupName: json['group_name'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      alreadyMember: json['already_member'] as bool? ?? false,
      membershipId: json['membership_id'] as String?,
    );
  }
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

  /// Máx. grupos activos que el usuario puede crear (GF-32).
  static const maxCreatedGroups = 3;

  /// Cuántos grupos activos creó el usuario (created_by), no los unidos.
  Future<int> countCreatedActiveGroups() async {
    try {
      final raw = await _sb.rpc('count_created_active_groups');
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
    } catch (_) {
      // Fallback si el RPC aún no APPLY.
    }
    final rows = await _sb
        .from('family_groups')
        .select('id')
        .eq('created_by', _uid)
        .eq('status', 'active');
    return (rows as List).length;
  }

  /// Inserta el grupo; el trigger añade al creador como `group_admin`.
  /// GF-32: máx. [maxCreatedGroups] grupos creados (cliente + trigger SQL).
  Future<FamilyGroup> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre del grupo no puede estar vacío.');
    }
    if (trimmed.length > 80) {
      throw ArgumentError('El nombre del grupo es demasiado largo (máx. 80).');
    }

    final created = await countCreatedActiveGroups();
    if (created >= maxCreatedGroups) {
      throw StateError(
        'Ya creaste $maxCreatedGroups grupos. '
        'Elimina uno para poder crear otro.',
      );
    }

    try {
      final row = await _sb
          .from('family_groups')
          .insert({
            'name': trimmed,
            'created_by': _uid,
          })
          .select('id, name, created_by, status')
          .single();
      final group = FamilyGroup.fromMap(row);
      // Sin wizard: activa share para RLS de pines (best-effort).
      try {
        await ConsentService().acceptShareWithGroup(group.id);
      } catch (_) {}
      return group;
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('MAX_CREATED_GROUPS') ||
          raw.contains('Ya creaste 3 grupos')) {
        throw StateError(
          'Ya creaste $maxCreatedGroups grupos. '
          'Elimina uno para poder crear otro.',
        );
      }
      rethrow;
    }
  }

  /// Admin: renombra el grupo (RPC o UPDATE RLS).
  Future<FamilyGroup> renameGroup({
    required String groupId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre del grupo no puede estar vacío.');
    }
    if (trimmed.length > 80) {
      throw ArgumentError('El nombre del grupo es demasiado largo (máx. 80).');
    }
    try {
      final row = await _sb.rpc(
        'rename_family_group',
        params: {'p_group_id': groupId, 'p_name': trimmed},
      );
      if (row is Map) {
        return FamilyGroup.fromMap(Map<String, dynamic>.from(row));
      }
    } catch (_) {
      // Fallback: UPDATE directo (policy family_groups_update_admin).
    }
    final row = await _sb
        .from('family_groups')
        .update({'name': trimmed})
        .eq('id', groupId)
        .select('id, name, created_by, status')
        .single();
    return FamilyGroup.fromMap(row);
  }

  /// Admin: elimina el grupo (cascade membresías / datos ligados).
  Future<void> deleteGroup(String groupId) async {
    try {
      await _sb.rpc('delete_family_group', params: {'p_group_id': groupId});
      return;
    } catch (e) {
      final raw = e.toString().toLowerCase();
      if (raw.contains('could not find the function') ||
          raw.contains('pgrst202') ||
          raw.contains('schema cache')) {
        // Sin RPC: soft-archive (status) para no dejar al usuario sin opción.
        await _sb
            .from('family_groups')
            .update({'status': 'archived'})
            .eq('id', groupId);
        return;
      }
      rethrow;
    }
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    List rows;
    try {
      rows = await _sb
          .from('group_memberships')
          .select(
            'id, group_id, user_id, role, status, '
            'profiles(display_name, photo_url, gender)',
          )
          .eq('group_id', groupId)
          .eq('status', 'active')
          .order('joined_at') as List;
    } catch (_) {
      // Columna gender aún no APPLY → lista sin género (heurística por nombre).
      rows = await _sb
          .from('group_memberships')
          .select(
            'id, group_id, user_id, role, status, '
            'profiles(display_name, photo_url)',
          )
          .eq('group_id', groupId)
          .eq('status', 'active')
          .order('joined_at') as List;
    }

    return rows.map((raw) {
      final e = Map<String, dynamic>.from(raw as Map);
      final profile = e['profiles'];
      String? displayName;
      String? photoUrl;
      String? gender;
      if (profile is Map) {
        displayName = profile['display_name'] as String?;
        final rawUrl = profile['photo_url'] as String?;
        if (rawUrl != null && rawUrl.trim().isNotEmpty) {
          photoUrl = rawUrl.trim();
        }
        final g = profile['gender'] as String?;
        if (g != null && g.trim().isNotEmpty) gender = g.trim();
      }
      return GroupMember(
        membershipId: e['id'] as String,
        groupId: e['group_id'] as String,
        userId: e['user_id'] as String,
        role: (e['role'] as String?) ?? 'member',
        status: (e['status'] as String?) ?? 'active',
        displayName: displayName,
        photoUrl: photoUrl,
        gender: gender,
      );
    }).toList();
  }

  Future<GroupMember?> myMembership(String groupId) async {
    final members = await listMembers(groupId);
    try {
      return members.firstWhere((m) => m.userId == _uid);
    } catch (_) {
      return null;
    }
  }

  int countGroupAdmins(List<GroupMember> members) =>
      members.where((m) => m.role == 'group_admin').length;

  /// Admin: promover miembro a `group_admin` (máx. 2).
  Future<void> promoteGroupAdmin({
    required String groupId,
    required String userId,
  }) async {
    await _sb.rpc(
      'promote_group_admin',
      params: {
        'p_group_id': groupId,
        'p_user_id': userId,
      },
    );
  }

  /// Admin: quitar `group_admin` → member (no el último).
  Future<void> demoteGroupAdmin({
    required String groupId,
    required String userId,
  }) async {
    await _sb.rpc(
      'demote_group_admin',
      params: {
        'p_group_id': groupId,
        'p_user_id': userId,
      },
    );
  }

  /// Genera token en claro (solo UI), guarda SHA-256. Un uso, 7 días.
  /// Requiere rol admin del grupo (RLS `invitations_insert_admin`).
  Future<InviteStub> createInvite(String groupId) async {
    final plain = _randomToken(24);
    final hash = InviteToken.hashToken(plain);
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

  /// @Deprecated Use [createInvite].
  Future<InviteStub> createInviteStub(String groupId) => createInvite(groupId);

  /// Acepta invitación vía RPC (security definer). Rol resultante: `member`.
  Future<AcceptInviteResult> acceptInvitation(String tokenOrLink) async {
    final token = InviteToken.normalize(tokenOrLink);
    if (!InviteToken.isPlausible(token)) {
      throw ArgumentError(
        'El código de invitación no es válido. Pega el token o el enlace.',
      );
    }

    try {
      final raw = await _sb.rpc(
        'accept_invitation',
        params: {'p_token': token},
      );
      if (raw is Map) {
        final result =
            AcceptInviteResult.fromJson(Map<String, dynamic>.from(raw));
        // GF-67: share activo en el grupo unido (RLS pines), sin wizard.
        try {
          final gid = result.groupId.trim();
          if (gid.isNotEmpty) {
            await ConsentService().acceptShareWithGroup(gid);
          }
        } catch (_) {}
        return result;
      }
      throw StateError('Respuesta inesperada al aceptar la invitación.');
    } on PostgrestException catch (e) {
      throw StateError(_mapAcceptError(e));
    }
  }

  static String _mapAcceptError(PostgrestException e) {
    final msg = e.message;
    final details = '${e.details ?? ''} ${e.hint ?? ''} $msg';
    if (details.contains('AUTH_REQUIRED')) {
      return 'Debes iniciar sesión para aceptar una invitación.';
    }
    if (details.contains('TOKEN_INVALID')) {
      return 'El código de invitación no es válido.';
    }
    if (details.contains('INVITE_NOT_FOUND')) {
      return 'No existe una invitación con ese código.';
    }
    if (details.contains('INVITE_REVOKED')) {
      return 'Esta invitación fue revocada.';
    }
    if (details.contains('INVITE_EXPIRED')) {
      return 'Esta invitación ya venció. Pide un código nuevo al admin.';
    }
    if (details.contains('INVITE_USED')) {
      return 'Esta invitación ya fue usada (un solo uso).';
    }
    if (details.contains('GROUP_MISSING')) {
      return 'El grupo de la invitación ya no existe.';
    }
    if (msg.contains('Could not find the function') ||
        msg.contains('function public.accept_invitation') ||
        msg.contains('PGRST202')) {
      return 'Falta aplicar la migración accept_invitation en Supabase. '
          'Ver supabase/APPLY_ES.md (archivo 20261102200000_accept_invitation_rpc.sql).';
    }
    return msg.isNotEmpty ? msg : 'No se pudo aceptar la invitación.';
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
