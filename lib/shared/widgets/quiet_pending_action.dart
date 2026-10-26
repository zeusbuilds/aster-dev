import 'package:flutter/material.dart';

/// Keeps a short platform handoff visually stable while blocking repeated taps.
///
/// The command owner must still reject overlapping or obsolete invocations.
/// This wrapper preserves the child's geometry and colours, and exposes the
/// temporarily unavailable action accurately to assistive technologies.
class QuietPendingAction extends StatelessWidget {
  const QuietPendingAction({
    super.key,
    required this.pending,
    required this.label,
    required this.child,
  });

  final bool pending;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: pending,
    excludeSemantics: pending,
    button: pending,
    enabled: pending ? false : null,
    label: pending ? label : null,
    child: ExcludeFocus(
      excluding: pending,
      child: IgnorePointer(ignoring: pending, child: child),
    ),
  );
}
