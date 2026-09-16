import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps a fixed form/menu layout inside the available viewport without
/// introducing a vertical scroll position.
class ViewportFittedContent extends StatelessWidget {
  const ViewportFittedContent({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxWidth = 440,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, innerConstraints) {
              final contentWidth = math.min(
                maxWidth,
                innerConstraints.maxWidth,
              );

              return Align(
                alignment: alignment,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: alignment,
                  child: SizedBox(width: contentWidth, child: child),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
