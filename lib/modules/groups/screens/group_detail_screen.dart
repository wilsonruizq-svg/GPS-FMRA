import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../chat/screens/direct_chat_screen.dart';
import '../../chat/screens/group_chat_screen.dart';
import '../../location/consent_service.dart';
import '../exit_pin_service.dart';
import '../groups_service.dart';
import '../widgets/exit_pin_dialog.dart';
import '../widgets/member_card.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.group});

  final FamilyGroup group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _groups = GroupsService();
  final _consent = ConsentService();
  final _exitPin = ExitPinService();

  bool _loading = true;
  String? _error;
  List<GroupMember> _members = const [];
  LocationConsent? _myConsent;
  InviteStub? _lastInvite;
  bool _iAmAdmin = false;
  bool _exitPinSet = false;
  bool _exitPinBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _groups.listMembers(widget.group.id);
      final consents = await _consent.listOwnGroupConsents();
      final mine = consents.cast<LocationConsent?>().firstWhere(
            (c) => c?.groupId == widget.group.id,
            orElse: () => null,
          );
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final me = members.cast<GroupMember?>().firstWhere(
            (m) => m?.userId == uid,
            orElse: () => null,
          );
      var pinSet = false;
      try {
        pinSet = await _exitPin.groupHasPin(widget.group.id);
      } catch (_) {
        pinSet = false;
      }
      if (!mounted) return;
      final amAdmin = me?.isAdmin ?? false;
      debugPrint(
        'GroupDetail: uid=$uid me=${me?.userId} role=${me?.role} '
        'admin=$amAdmin exitPinSet=$pinSet members=${members.length}',
      );
      setState(() {
        _members = members;
        _myConsent = mine;
        _iAmAdmin = amAdmin;
        _exitPinSet = pinSet;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _shareLabelFor(GroupMember m) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (m.userId == uid) {
      if (_myConsent == null) return AppStrings.memberShareNone;
      if (_myConsent!.isActive) return AppStrings.memberShareActive;
      if (_myConsent!.isPaused) return AppStrings.memberSharePaused;
      return AppStrings.memberShareRevoked;
    }
    return AppStrings.memberShareUnknown;
  }

  Future<void> _copyInvite(InviteStub invite, {required bool asLink}) async {
    await Clipboard.setData(
      ClipboardData(text: asLink ? invite.linkStub : invite.plainToken),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          asLink ? AppStrings.inviteLinkCopied : AppStrings.inviteCopied,
        ),
      ),
    );
  }

  Future<void> _createInvite() async {
    if (!_iAmAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.inviteAdminOnly)),
      );
      return;
    }
    try {
      final invite = await _groups.createInvite(widget.group.id);
      if (!mounted) return;
      setState(() => _lastInvite = invite);
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text(AppStrings.inviteTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(AppStrings.inviteBody),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      invite.plainToken,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.inviteFamilySteps,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    invite.linkStub,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${AppStrings.inviteExpires} ${invite.expiresAt.toLocal()}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await _copyInvite(invite, asLink: false);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text(AppStrings.inviteCopyToken),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _copyInvite(invite, asLink: true);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.link),
                    label: const Text(AppStrings.inviteCopyLink),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.close),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _setOrChangeExitPin({required bool changing}) async {
    if (!_iAmAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.exitPinAdminOnly)),
      );
      return;
    }
    final pin = await showExitPinComposeDialog(
      context: context,
      purpose:
          changing ? ExitPinPurpose.changePin : ExitPinPurpose.setPin,
    );
    if (pin == null || !mounted) return;
    setState(() => _exitPinBusy = true);
    try {
      await _exitPin.setPin(groupId: widget.group.id, pin: pin);
      if (!mounted) return;
      setState(() {
        _exitPinSet = true;
        _exitPinBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.exitPinSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exitPinBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _clearExitPin() async {
    if (!_iAmAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.exitPinClearAction),
        content: const Text(AppStrings.exitPinClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.exitPinClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _exitPinBusy = true);
    try {
      await _exitPin.clearPin(widget.group.id);
      if (!mounted) return;
      setState(() {
        _exitPinSet = false;
        _exitPinBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.exitPinCleared)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exitPinBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  /// PIN para salir del programa / cerrar sesión (Atrás). Siempre visible.
  Widget _exitPinSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _exitPinSet ? Icons.lock : Icons.lock_open_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.exitPinTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.exitPinSetBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                _exitPinSet
                    ? AppStrings.exitPinStatusOn
                    : AppStrings.exitPinStatusOff,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              if (!_iAmAdmin)
                Text(
                  AppStrings.exitPinAdminOnly,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              else if (_exitPinBusy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _setOrChangeExitPin(
                        changing: _exitPinSet,
                      ),
                      icon: Icon(
                        _exitPinSet ? Icons.lock_reset : Icons.lock_outline,
                        size: 18,
                      ),
                      label: Text(
                        _exitPinSet
                            ? AppStrings.exitPinChangeAction
                            : AppStrings.exitPinSetAction,
                      ),
                    ),
                    if (_exitPinSet)
                      OutlinedButton.icon(
                        onPressed: _clearExitPin,
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: const Text(AppStrings.exitPinClearAction),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inviteBanner(BuildContext context) {
    final invite = _lastInvite;
    if (invite == null) {
      if (!_iAmAdmin) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          AppStrings.groupsInviteHowTo,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.inviteLastHeading,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                invite.plainToken,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.inviteFamilySteps,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _copyInvite(invite, asLink: false),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text(AppStrings.inviteCopyToken),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyInvite(invite, asLink: true),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text(AppStrings.inviteCopyLink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: AppStrings.chatAction,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GroupChatScreen(group: widget.group),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          if (_iAmAdmin)
            IconButton(
              tooltip: AppStrings.inviteAction,
              onPressed: _createInvite,
              icon: const Icon(Icons.person_add_alt_1),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          _iAmAdmin
                              ? AppStrings.groupsYouAreAdmin
                              : AppStrings.groupsYouAreMember,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                      // PIN salir del programa — arriba, siempre visible.
                      _exitPinSection(context),
                      _inviteBanner(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          AppStrings.membersHeading,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const Divider(height: 1),
                      ..._members.map(
                        (m) => Column(
                          children: [
                            MemberCard(
                              name: m.label,
                              photoUrl: m.photoUrl,
                              isSelf: m.userId == uid,
                              shareStatusLabel: _shareLabelFor(m),
                              onMessage: m.userId == uid
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => DirectChatScreen(
                                            peerUserId: m.userId,
                                            peerName: m.label,
                                            peerPhotoUrl: m.photoUrl,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                      if (_members.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            AppStrings.membersEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
