import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../groups_service.dart';

/// Pantalla para unirse a un grupo con código / deep link stub.
class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _service = GroupsService();
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.acceptInvitation(_controller.text);
      if (!mounted) return;
      final msg = result.alreadyMember
          ? '${AppStrings.inviteAlreadyMember} ${result.groupName}'
          : '${AppStrings.inviteJoinedPrefix} ${result.groupName} '
              '(${AppStrings.inviteRoleMember})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.inviteAcceptTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            AppStrings.inviteAcceptHeadline,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.inviteAcceptBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: const InputDecoration(
              labelText: AppStrings.inviteCodeLabel,
              hintText: AppStrings.inviteCodeHint,
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.group_add),
            label: Text(
              _busy
                  ? AppStrings.inviteAccepting
                  : AppStrings.inviteAcceptAction,
            ),
          ),
        ],
      ),
    );
  }
}
