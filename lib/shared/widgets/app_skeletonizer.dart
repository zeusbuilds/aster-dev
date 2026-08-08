import 'package:flutter/material.dart';

import 'package:skeletonizer/skeletonizer.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

/// A reusable skeleton loader widget with app-specific styling
///
/// Wraps [Skeletonizer] with the app's color scheme and shimmer effect.
/// Use this widget to show skeleton loading states throughout the app.
///
/// Example:
/// ```dart
/// AppSkeletonizer(
///   enabled: isLoading,
///   child: Text('Loading text'),
/// )
/// ```
class AppSkeletonizer extends StatelessWidget {
  /// Whether the skeleton effect is enabled
  final bool enabled;

  /// The child widget to skeletonize
  final Widget child;

  /// Optional override for the shimmer animation duration.
  final Duration? duration;

  /// Base color of the shimmer effect
  final Color? baseColor;

  /// Highlight color of the shimmer effect
  final Color? highlightColor;

  const AppSkeletonizer({
    super.key,
    required this.enabled,
    required this.child,
    this.duration,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final motion = context.motion;
    final effectiveBaseColor = baseColor ?? colors.surfaceSubtle;

    return Skeletonizer(
      enabled: enabled,
      effect: context.motionPolicy.reduceMotion
          ? SolidColorEffect(color: effectiveBaseColor)
          : ShimmerEffect(
              baseColor: effectiveBaseColor,
              highlightColor: highlightColor ?? context.colorScheme.surface,
              duration: duration ?? motion.skeletonShimmerDuration,
            ),
      child: child,
    );
  }
}
