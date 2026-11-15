import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/widgets/chat_unread_badge.dart';

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
    this.onLongPress,
    this.onMessage,
    this.onOpenExternalMap,
    this.onFigurineTap,
    this.trailingExtra,
    this.dmUnreadCount = 0,
  });

  final String name;
  final String shareStatusLabel;
  final String? photoUrl;
  final bool isSelf;

  /// Color del pin GPS en el mapa; si null, no se muestra figurita.
  final Color? mapPinColor;
  final bool female;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMessage;

  /// Icono discreto (Google Maps externo) cuando hay lat/lng en vivo.
  final VoidCallback? onOpenExternalMap;

  /// Tap en la figurita de color (misma acción que el muñeco del mapa).
  final VoidCallback? onFigurineTap;

  /// P. ej. promover/quitar admin (detalle de grupo).
  final Widget? trailingExtra;
  final int dmUnreadCount;

  bool get _hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.midBlue.withValues(alpha: 0.15),
                foregroundImage: _hasPhoto
                    ? NetworkImage(photoUrl!.trim())
                    : null,
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
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.deepBlue,
                                ),
                          ),
                          if (isSelf)
                            TextSpan(
                              text: ' ${AppStrings.memberYouSuffix}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.midBlue),
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
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.midBlue),
                    ),
                  ],
                ),
              ),
              if (mapPinColor != null) ...[
                GestureDetector(
                  onTap: onFigurineTap,
                  behavior: HitTestBehavior.opaque,
                  child: Tooltip(
                    message: AppStrings.memberMapPinTooltip,
                    child: Icon(
                      female ? Icons.woman : Icons.man,
                      color: mapPinColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              if (onOpenExternalMap != null)
                IconButton(
                  tooltip: AppStrings.memberExternalMapIconTooltip,
                  onPressed: onOpenExternalMap,
                  icon: const Icon(Icons.map_outlined),
                  color: scheme.onSurfaceVariant,
                ),
              if (trailingExtra != null) trailingExtra!,
              if (onMessage != null && !isSelf)
                IconButton(
                  tooltip: AppStrings.dmAction,
                  onPressed: onMessage,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: ChatIconUnreadBadge(
                    count: dmUnreadCount,
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.deepBlue,
                    ),
                  ),
                )
              else if (trailingExtra == null && onOpenExternalMap == null)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
