import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../app_shell.dart';

class ConsentPlaceholderScreen extends StatelessWidget {
  const ConsentPlaceholderScreen({super.key, this.isOnboarding = false});

  /// Si es true, al continuar reemplaza por [AppShell]; si no, solo hace pop.
  final bool isOnboarding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.consentTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.my_location,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.consentBody,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                if (isOnboarding) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const AppShell()),
                  );
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              child: const Text(AppStrings.consentContinue),
            ),
          ],
        ),
      ),
    );
  }
}
