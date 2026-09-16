import 'package:flutter/material.dart';

class HairlineDivider extends StatelessWidget {
  const HairlineDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.verticalPadding = 0,
  });

  final double indent;
  final double endIndent;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Divider(
        height: 1,
        thickness: 0.5,
        indent: indent,
        endIndent: endIndent,
        color: color,
      ),
    );
  }
}

class AccentMetadata extends StatelessWidget {
  const AccentMetadata({
    super.key,
    required this.text,
    this.icon,
    this.color,
    this.maxLines = 1,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = color ?? colors.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 12,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: 6),
          Icon(icon, size: 13, color: accent.withValues(alpha: 0.88)),
        ],
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant.withValues(alpha: 0.86),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class TintedTag extends StatelessWidget {
  const TintedTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = color ?? colors.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.20), width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 12 : 13, color: accent),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.25,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
