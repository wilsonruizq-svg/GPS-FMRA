import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Contenedor del mapa; Google Maps se integrará después (placeholder).
class MapShellScreen extends StatelessWidget {
  const MapShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  AppStrings.mapGroupSelector,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.mapNoGroup,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.midBlue.withValues(alpha: 0.15),
                  AppColors.signalCyan.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 64,
                      color: AppColors.deepBlue.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.mapPlaceholderTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.mapPlaceholderBody,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (!Env.hasMapsConfig) ...[
                      const SizedBox(height: 16),
                      Text(
                        'GOOGLE_MAPS_API_KEY no configurada',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
