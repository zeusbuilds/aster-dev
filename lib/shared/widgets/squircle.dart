import 'dart:ui';

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
  final double borderWidth;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow> shadows;
  final EdgeInsets? padding;
  final BorderRadius? border;
  final ImageFilter? backdropFilter;

  /// Shares this non-overlapping backdrop filter with the nearest
  /// [BackdropGroup], allowing the engine to execute one filter pass.
  final bool groupBackdropFilter;

  const Squircle({
    super.key,
    required this.child,
    this.borderRadius,
    this.borderColor,
    this.borderWidth = 1,
    this.color,
    this.gradient,
    this.shadows = const [],
    this.padding,
    this.border,
    this.backdropFilter,
    this.groupBackdropFilter = false,
  }) : assert(!groupBackdropFilter || backdropFilter != null);

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

    final content = DecoratedBox(
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
    );
    Widget filteredContent = content;
    if (backdropFilter != null) {
      filteredContent = groupBackdropFilter
          ? BackdropFilter.grouped(filter: backdropFilter!, child: content)
          : BackdropFilter(filter: backdropFilter!, child: content);
    }

    return ClipRSuperellipse(
      borderRadius: effectiveBorderRadius,
      child: filteredContent,
    );
  }
}
