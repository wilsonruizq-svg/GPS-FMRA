import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Icono de nav con overlay numérico (NavigationBar recorta [Badge] Material).
class NavGroupsUnreadIcon extends StatelessWidget {
  const NavGroupsUnreadIcon({
    super.key,
    required this.icon,
    required this.count,
    this.selected = false,
  });

  final IconData icon;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      size: 24,
      color: selected
          ? AppColors.deepBlue
          : AppColors.onDeep.withValues(alpha: 0.82),
    );
    if (count <= 0) return iconWidget;
    final label = count > 99 ? '99+' : '$count';
    return SizedBox(
      width: 30,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          iconWidget,
          Positioned(
            top: -8,
            right: -12,
            child: Material(
              elevation: 3,
              shadowColor: Colors.black45,
              color: AppColors.accentRed,
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill para fila de grupo (trailing).
class ChatUnreadCountPill extends StatelessWidget {
  const ChatUnreadCountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      margin: const EdgeInsets.only(right: 8),
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentRed,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentRed.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}