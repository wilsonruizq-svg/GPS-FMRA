import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Tarjeta mínima de integrante: nombre, estado de compartir, última actualización.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.name,
    required this.shareStatusLabel,
    this.lastUpdateLabel,
    this.isSelf = false,
    this.onTap,
  });

  final String name;
  final String shareStatusLabel;
  final String? lastUpdateLabel;
  final bool isSelf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.midBlue.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (isSelf)
                            TextSpan(
                              text: ' ${AppStrings.memberYouSuffix}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shareStatusLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.midBlue,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastUpdateLabel ?? AppStrings.memberLastUpdateUnknown,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
