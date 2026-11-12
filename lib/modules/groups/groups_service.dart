import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
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
      id: map['id'].toString(),
      name: (map['name'] ?? '').toString(),
      createdBy: (map['created_by'] ?? '').toString(),
      status: (map['status'] as String?) ?? 'active',
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
        .map((e) => (e as Map)['group_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
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
        .where((g) => g.id.isNotEmpty && g.name.isNotEmpty)
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
        return AcceptInviteResult.fromJson(Map<String, dynamic>.from(raw));
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
