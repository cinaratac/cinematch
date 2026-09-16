import 'package:flutter/material.dart';

Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmText,
  IconData? icon,
  Color? iconColor,
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  final color = destructive
      ? Colors.red
      : (iconColor ?? Theme.of(context).primaryColor);

  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: _AppPopupSurface(
        title: title,
        icon: icon,
        iconColor: color,
        actions: [
          _AppPopupButton(
            label: 'Vazgeç',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          _AppPopupButton(
            label: confirmText,
            color: color,
            filled: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Theme.of(ctx).brightness == Brightness.dark
                ? Colors.white70
                : Colors.black87,
          ),
        ),
      ),
    ),
  );
}

class _AppPopupSurface extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;

  const _AppPopupSurface({
    required this.title,
    required this.child,
    this.actions = const [],
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;
    final accent = iconColor ?? Theme.of(context).primaryColor;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      Expanded(child: actions[i]),
                      if (i != actions.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppPopupButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final Color? color;

  const _AppPopupButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor =
        color ?? (isDark ? Colors.white : Theme.of(context).primaryColor);

    if (filled) {
      return SizedBox(
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: effectiveColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: effectiveColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
