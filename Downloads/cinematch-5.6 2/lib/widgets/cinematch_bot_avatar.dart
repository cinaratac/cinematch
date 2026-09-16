import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';

class CinematchBotAvatar extends StatelessWidget {
  const CinematchBotAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHighest,
          border: Border.all(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.38),
            width: 0.5,
          ),
        ),
        child: ClipOval(
          child: Padding(
            padding: EdgeInsets.all(size * 0.06),
            child: IgnorePointer(child: GreenEyesCharacter(size: size * 0.88)),
          ),
        ),
      ),
    );
  }
}
