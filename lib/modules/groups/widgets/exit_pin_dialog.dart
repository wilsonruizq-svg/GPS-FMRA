import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../exit_pin_service.dart';

enum ExitPinPurpose { logout, leaveApp, setPin, changePin }

/// Diálogo para pedir o configurar el PIN de salida del grupo.
Future<bool> showExitPinChallenge({
  required BuildContext context,
  required ExitPinPurpose purpose,
  ExitPinService? service,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExitPinChallengeDialog(
      purpose: purpose,
      service: service ?? ExitPinService(),
    ),
  );
  return result == true;
}

/// Diálogo admin para establecer / cambiar PIN (devuelve el PIN en claro
/// solo para enviarlo a la RPC; no se persiste en el cliente).
Future<String?> showExitPinComposeDialog({
  required BuildContext context,
  required ExitPinPurpose purpose,
}) async {
  assert(
    purpose == ExitPinPurpose.setPin || purpose == ExitPinPurpose.changePin,
  );
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExitPinComposeDialog(purpose: purpose),
  );
}

class _ExitPinChallengeDialog extends StatefulWidget {
  const _ExitPinChallengeDialog({
    required this.purpose,
    required this.service,
  });

  final ExitPinPurpose purpose;
  final ExitPinService service;

  @override
  State<_ExitPinChallengeDialog> createState() =>
      _ExitPinChallengeDialogState();
}

class _ExitPinChallengeDialogState extends State<_ExitPinChallengeDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.purpose) {
      case ExitPinPurpose.logout:
        return AppStrings.exitPinRequiredLogout;
      case ExitPinPurpose.leaveApp:
        return AppStrings.exitPinRequiredExit;
      case ExitPinPurpose.setPin:
      case ExitPinPurpose.changePin:
        return AppStrings.exitPinTitle;
    }
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (!ExitPinService.isValidPinFormat(pin)) {
      setState(() => _error = AppStrings.exitPinFormatError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.service.verify(pin);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _error = AppStrings.exitPinWrong;
        _busy = false;
      });
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
    return AlertDialog(
      title: Text(_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(AppStrings.exitPinChallengeBody),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focus,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            enabled: !_busy,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: AppStrings.exitPinLabel,
              hintText: AppStrings.exitPinHint,
            ),
            onSubmitted: (_) {
              if (!_busy) _submit();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(AppStrings.exitPinConfirmAction),
        ),
      ],
    );
  }
}

class _ExitPinComposeDialog extends StatefulWidget {
  const _ExitPinComposeDialog({required this.purpose});

  final ExitPinPurpose purpose;

  @override
  State<_ExitPinComposeDialog> createState() => _ExitPinComposeDialogState();
}

class _ExitPinComposeDialogState extends State<_ExitPinComposeDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _pin.text.trim();
    final b = _confirm.text.trim();
    if (!ExitPinService.isValidPinFormat(a)) {
      setState(() => _error = AppStrings.exitPinFormatError);
      return;
    }
    if (a != b) {
      setState(() => _error = AppStrings.exitPinMismatch);
      return;
    }
    Navigator.of(context).pop(a);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.purpose == ExitPinPurpose.changePin
        ? AppStrings.exitPinChangeAction
        : AppStrings.exitPinSetAction;

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(AppStrings.exitPinSetBody),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: AppStrings.exitPinLabel,
              hintText: AppStrings.exitPinHint,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: AppStrings.exitPinConfirmLabel,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(AppStrings.exitPinSaveAction),
        ),
      ],
    );
  }
}
