import 'package:flutter/material.dart';

/// Resolves authored motion against the user's accessibility preference.
@immutable
final class AsterMotionPolicy {
  const AsterMotionPolicy({required this.reduceMotion});

  factory AsterMotionPolicy.of(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final platformRequestsReducedMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    return AsterMotionPolicy(
      reduceMotion:
          (mediaQuery?.disableAnimations ?? false) ||
          platformRequestsReducedMotion,
    );
  }

  final bool reduceMotion;

  /// Returns zero for decorative/state-transition motion when reduced motion
  /// is requested, allowing callers to render the final state immediately.
  Duration duration(Duration authored) {
    return reduceMotion ? Duration.zero : authored;
  }
}

extension AsterMotionPolicyContext on BuildContext {
  AsterMotionPolicy get motionPolicy => AsterMotionPolicy.of(this);
}
