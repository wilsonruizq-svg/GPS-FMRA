import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Burbuja numérica alineada con AppColors (cyan en nav, rojo si hay muchos).
class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({
    super.key,
    required this.count,
    required this.child,
    this.compact = false,
  });

  final int count;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final label = count > 99 ? '99+' : '$count';
    final urgent = count >= 10;
    return Badge(
      isLabelVisible: true,
      label: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor:
          urgent ? AppColors.accentRed : AppColors.signalCyan,
      textColor: urgent ? Colors.white : AppColors.deepBlue,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 5)
          : const EdgeInsets.symmetric(horizontal: 6),
      offset: compact ? const Offset(6, -4) : const Offset(8, -4),
      child: child,
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
    final urgent = count >= 10;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgent
            ? AppColors.accentRed
            : AppColors.signalCyan.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: urgent ? Colors.white : AppColors.deepBlue,
        ),
      ),
    );
  }
}