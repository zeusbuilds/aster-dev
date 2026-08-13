import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Widget that applies a squircle (rounded superellipse) shape to its child.
///
/// Provides a modern rounded rectangle shape with customizable border radius,
/// colors, gradients, shadows, and borders. Commonly used for cards and
/// containers.
class Squircle extends StatelessWidget {
  final Widget child;
  final double? borderRadius;
  final Color? borderColor;
  final double? borderWidth;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow> shadows;
  final EdgeInsets? padding;
  final BorderRadius? border;

  const Squircle({
    super.key,
    required this.child,
    this.borderRadius,
    this.borderColor,
    this.borderWidth,
    this.color,
    this.gradient,
    this.shadows = const [],
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = context.radii;
    final spacing = context.spacing;
    final effectiveBorderColor = borderColor ?? colors.borderSubtle;
    final effectiveColor = color ?? colors.transparentSurface;
    final effectiveBorderRadius =
        border ?? BorderRadius.circular(borderRadius ?? radius.card);
    final effectivePadding = padding ?? EdgeInsets.all(spacing.sm);
    final effectiveBorderWidth = borderWidth ?? context.strokes.border;

    final content = DecoratedBox(
      decoration: ShapeDecoration(
        color: gradient == null ? effectiveColor : null,
        gradient: gradient,
        shape: RoundedSuperellipseBorder(
          borderRadius: effectiveBorderRadius,
          side: BorderSide(
            color: effectiveBorderColor,
            width: effectiveBorderWidth,
          ),
        ),
        shadows: shadows,
      ),
      child: Padding(padding: effectivePadding, child: child),
    );
    return ClipRSuperellipse(
      borderRadius: effectiveBorderRadius,
      child: content,
    );
  }
}
