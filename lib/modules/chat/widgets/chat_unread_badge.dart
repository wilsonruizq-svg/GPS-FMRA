import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum ChatUnreadBadgeAnchor {
  /// Burbuja en fila de integrante (número bajo/derecha del icono).
  memberChat,

  /// Toolbar del mapa (esquina superior del icono).
  mapToolbar,
}

/// Contador rojo sobre un icono de chat (evita [Badge] Material recortado).
class ChatIconUnreadBadge extends StatelessWidget {
  const ChatIconUnreadBadge({
    super.key,
    required this.child,
    required this.count,
    this.anchor = ChatUnreadBadgeAnchor.memberChat,
  });

  final Widget child;
  final int count;
  final ChatUnreadBadgeAnchor anchor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final label = count > 99 ? '99+' : '$count';
    final (top, bottom, right) = switch (anchor) {
      ChatUnreadBadgeAnchor.memberChat => (null, -4.0, -6.0),
      ChatUnreadBadgeAnchor.mapToolbar => (-6.0, null, -10.0),
    };
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          child,
          Positioned(
            top: top,
            bottom: bottom,
            right: right,
            child: _UnreadDot(label: label, compact: true),
          ),
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black38,
      color: AppColors.accentRed,
      borderRadius: BorderRadius.circular(compact ? 9 : 11),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 5,
          vertical: compact ? 1 : 2,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: compact ? 16 : 18),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

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
