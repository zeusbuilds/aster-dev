import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

/// Decorative mark for a selected item whose owning row handles interaction.
class AsterSelectionIndicator extends StatelessWidget {
  const AsterSelectionIndicator({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = context.metrics.selectionIndicatorSize;
    final duration = context.motionPolicy.duration(
      context.motion.selectionTransitionDuration,
    );
    final primary = context.colorScheme.primary;

    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: context.motion.fastEase,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? primary : context.colorScheme.surface,
          border: Border.all(
            color: selected
                ? primary
                : context.colorScheme.surfaceContainerHigh,
            width: context.strokes.selectionIndicator,
          ),
        ),
        child: AnimatedOpacity(
          duration: duration,
          curve: context.motion.fastEase,
          opacity: selected
              ? context.stateLayers.visible
              : context.stateLayers.hidden,
          child: Icon(
            Icons.check_rounded,
            color: context.colorScheme.onPrimary,
            size: context.icons.xxs,
          ),
        ),
      ),
    );
  }
}
