import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../location/consent_service.dart';
import '../groups_service.dart';
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

  bool _loading = true;
  String? _error;
  List<GroupMember> _members = const [];
  LocationConsent? _myConsent;
  InviteStub? _lastInvite;

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
      if (!mounted) return;
      setState(() {
        _members = members;
        _myConsent = mine;
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

  Future<void> _createInvite() async {
    try {
      final invite = await _groups.createInviteStub(widget.group.id);
      if (!mounted) return;
      setState(() => _lastInvite = invite);
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text(AppStrings.inviteTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(AppStrings.inviteBody),
                const SizedBox(height: 12),
                SelectableText(
                  invite.plainToken,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
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
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.plainToken));
                  Navigator.pop(ctx);
                },
                child: const Text(AppStrings.inviteCopyToken),
              ),
              FilledButton(
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

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: AppStrings.inviteAction,
            onPressed: _createInvite,
            icon: const Icon(Icons.qr_code_2),
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
                          AppStrings.membersHeading,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (_lastInvite != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${AppStrings.inviteLastToken} ${_lastInvite!.plainToken}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const Divider(height: 1),
                      ..._members.map(
                        (m) => Column(
                          children: [
                            MemberCard(
                              name: m.label,
                              isSelf: m.userId == uid,
                              shareStatusLabel: _shareLabelFor(m),
                              lastUpdateLabel:
                                  AppStrings.memberLastUpdateUnknown,
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
