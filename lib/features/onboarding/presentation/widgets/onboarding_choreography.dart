import 'package:flutter/material.dart';

import '../../../../shared/theme/theme.dart';

/// Supplies one transition timeline to the structural groups of an onboarding
/// step.
///
/// The coordinator mounts an outgoing and incoming scope over the same
/// animation. Outgoing groups leave bottom-to-top, while incoming groups enter
/// top-to-bottom. Outside a coordinated flow, items render normally so the
/// reusable screens remain valid as standalone routes and in widget tests.
class OnboardingChoreographyScope extends InheritedWidget {
  const OnboardingChoreographyScope({
    super.key,
    required this.animation,
    required this.exiting,
    required super.child,
  });

  /// Shared normalized timeline for the current step handoff.
  final Animation<double> animation;

  /// Whether descendants belong to the step being dismissed.
  final bool exiting;

  static OnboardingChoreographyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnboardingChoreographyScope>();

  @override
  bool updateShouldNotify(OnboardingChoreographyScope oldWidget) =>
      animation != oldWidget.animation || exiting != oldWidget.exiting;
}

/// Animates one of four ordered structural groups in an onboarding step.
class OnboardingChoreographyItem extends StatelessWidget {
  const OnboardingChoreographyItem({
    super.key,
    required this.id,
    required this.visualIndex,
    required this.child,
  });

  /// Every onboarding screen follows the same four-part visual hierarchy.
  static const groupCount = 4;

  /// Stable identifier used by motion regression tests.
  final String id;

  /// Top-to-bottom position in the screen hierarchy, from zero through three.
  final int visualIndex;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(visualIndex >= 0 && visualIndex < groupCount);
    final scope = OnboardingChoreographyScope.maybeOf(context);
    if (scope == null) return child;

    final motion = context.motion;
    final sequenceIndex = scope.exiting
        ? groupCount - visualIndex - 1
        : visualIndex;
    final start =
        (scope.exiting ? 0 : motion.contentTransitionIncomingStart) +
        sequenceIndex * motion.choreographyStaggerInterval;
    final end = start + motion.choreographyItemInterval;
    final curve = scope.exiting ? motion.fastEase : motion.choreographyCurve;

    return AnimatedBuilder(
      animation: scope.animation,
      child: child,
      builder: (context, child) {
        final progress = _intervalProgress(
          scope.animation.value,
          start: start,
          end: end,
          curve: curve,
        );
        final visibility = scope.exiting ? 1 - progress : progress;
        final offsetProgress = scope.exiting ? progress : 1 - progress;
        return Opacity(
          key: ValueKey('$id-opacity'),
          opacity: visibility,
          child: Transform.translate(
            key: ValueKey('$id-transform'),
            offset: Offset(
              0,
              motion.contentTransitionVerticalOffset * offsetProgress,
            ),
            transformHitTests: false,
            child: child,
          ),
        );
      },
    );
  }
}

double _intervalProgress(
  double value, {
  required double start,
  required double end,
  required Curve curve,
}) {
  if (value <= start) return 0;
  if (value >= end) return 1;
  return curve.transform((value - start) / (end - start));
}
