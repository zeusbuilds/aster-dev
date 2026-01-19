import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';

/// Widget that applies a squircle (rounded superellipse) shape to its child
///
/// Provides a modern rounded rectangle shape with customizable border radius,
/// colors, gradients, shadows, and borders. Commonly used for cards and containers.
class Squircle extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow> shadows;
  final EdgeInsets padding;
  final BorderRadius? border;

  const Squircle({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.borderColor,
    this.borderWidth = 1,
    this.color,
    this.gradient,
    this.shadows = const [],
    this.padding = const EdgeInsets.all(8.0),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = context.radius;
    final spacing = context.spacing;
    final effectiveBorderColor = borderColor ?? colors.border2;
    final effectiveColor = color ?? Colors.transparent;
    final effectiveBorderRadius =
        border ??
        BorderRadius.circular(
          borderRadius == 24 ? radius.radius24 : borderRadius,
        );
    final effectivePadding = padding == const EdgeInsets.all(8.0)
        ? EdgeInsets.all(spacing.spacing8)
        : padding;

    return ClipRSuperellipse(
      borderRadius: effectiveBorderRadius,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: gradient == null ? effectiveColor : null,
          gradient: gradient,
          shape: RoundedSuperellipseBorder(
            borderRadius: effectiveBorderRadius,
            side: BorderSide(color: effectiveBorderColor, width: borderWidth),
          ),
          shadows: shadows,
        ),
        child: Padding(padding: effectivePadding, child: child),
      ),
    );
  }
}
