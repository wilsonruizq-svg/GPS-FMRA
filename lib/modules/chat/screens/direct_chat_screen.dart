import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../chat_alert_service.dart';
import '../dm_service.dart';

/// Chat 1:1 con un compañero del grupo.
class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.peerUserId,
    required this.peerName,
    this.peerPhotoUrl,
  });

  final String peerUserId;
  final String peerName;
  final String? peerPhotoUrl;

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _dm = DmService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<DirectMessage> _messages = const [];
  RealtimeChannel? _channel;
  final Set<String> _seenIds = {};

  String get _myUid =>
      (Supabase.instance.client.auth.currentUser?.id ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    ChatAlertService.instance.mutePeer(widget.peerUserId);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    ChatAlertService.instance.mutePeer(null);
    unawaited(_dm.unsubscribe(_channel));
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _dm.listThread(peerUserId: widget.peerUserId);
      final enriched = <DirectMessage>[];
      for (final m in list) {
        enriched.add(await _dm.enrich(m));
      }
      if (!mounted) return;
      _seenIds
        ..clear()
        ..addAll(enriched.map((m) => m.id));
      setState(() {
        _messages = enriched;
        _loading = false;
      });
      _subscribe();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DmService.looksLikeMissingTable(e)
            ? AppStrings.dmMissingSql
            : e.toString();
      });
    }
  }

  void _subscribe() {
    unawaited(_dm.unsubscribe(_channel));
    _channel = _dm.subscribeMine(
      onInsert: (raw) {
        unawaited(_onRealtime(raw));
      },
    );
  }

  Future<void> _onRealtime(DirectMessage raw) async {
    final peer = widget.peerUserId.trim().toLowerCase();
    final a = raw.senderId.trim().toLowerCase();
    final b = raw.recipientId.trim().toLowerCase();
    final mine = _myUid;
    final involvesPeer =
        (a == mine && b == peer) || (a == peer && b == mine);
    if (!involvesPeer) return;
    if (_seenIds.contains(raw.id)) return;
    final enriched = await _dm.enrich(raw);
    if (!mounted || _seenIds.contains(enriched.id)) return;
    setState(() {
      _seenIds.add(enriched.id);
      _messages = [..._messages, enriched];
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await _dm.send(
        recipientId: widget.peerUserId,
        body: text,
      );
      if (!mounted) return;
      _controller.clear();
      final enriched = await _dm.enrich(sent);
      if (!_seenIds.contains(enriched.id)) {
        setState(() {
          _seenIds.add(enriched.id);
          _messages = [..._messages, enriched];
        });
        _scrollToEnd();
      }
      _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      final msg = DmService.looksLikeMissingTable(e)
          ? AppStrings.dmMissingSql
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _clock(DateTime utc) {
    final local = utc.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.dmTitleFor(widget.peerName)),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(context)),
          SafeArea(
            top: false,
            child: _Composer(
              controller: _controller,
              focusNode: _focus,
              sending: _sending || _loading || _error != null,
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_bootstrap()),
                child: const Text(AppStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppStrings.dmEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine =
            m.senderId.trim().toLowerCase() == _myUid && _myUid.isNotEmpty;
        return _Bubble(
          message: m,
          isMine: mine,
          timeLabel: _clock(m.createdAt),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: AppStrings.dmHint,
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              tooltip: AppStrings.chatSend,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.deepBlue,
                foregroundColor: Colors.white,
              ),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.timeLabel,
  });

  final DirectMessage message;
  final bool isMine;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? AppColors.deepBlue : Colors.white;
    final fg = isMine ? Colors.white : AppColors.deepBlue;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
                border: isMine
                    ? null
                    : Border.all(
                        color: AppColors.midBlue.withValues(alpha: 0.2),
                      ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.body,
                      style: TextStyle(color: fg, fontSize: 15, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeLabel,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.75),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
