import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Fila compacta de integrante: foto, nombre, estado; figurita GPS + DM.
///
/// Orden: nombre/estado | [figurita color] | [chat].
/// La figurita usa el mismo color que el pin del mapa cuando [mapPinColor]
/// no es null (integrante compartiendo ubicación).
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.name,
    required this.shareStatusLabel,
    this.photoUrl,
    this.isSelf = false,
    this.mapPinColor,
    this.female = false,
    this.onTap,
    this.onMessage,
    this.trailingExtra,
  });

  final String name;
  final String shareStatusLabel;
  final String? photoUrl;
  final bool isSelf;
  /// Color del pin GPS en el mapa; si null, no se muestra figurita.
  final Color? mapPinColor;
  final bool female;
  final VoidCallback? onTap;
  final VoidCallback? onMessage;
  /// P. ej. promover/quitar admin (detalle de grupo).
  final Widget? trailingExtra;

  bool get _hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.midBlue.withValues(alpha: 0.15),
                foregroundImage:
                    _hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                onForegroundImageError: _hasPhoto
                    ? (Object error, StackTrace? stackTrace) {}
                    : null,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shareStatusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.midBlue,
                          ),
                    ),
                  ],
                ),
              ),
              if (mapPinColor != null) ...[
                Tooltip(
                  message: AppStrings.memberMapPinTooltip,
                  child: Icon(
                    female ? Icons.woman : Icons.man,
                    color: mapPinColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              if (trailingExtra != null) trailingExtra!,
              if (onMessage != null && !isSelf)
                IconButton(
                  tooltip: AppStrings.dmAction,
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: AppColors.deepBlue,
                )
              else if (trailingExtra == null)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
