import 'package:flutter/material.dart';

/// Decorative capsule surface backed by Flutter's exact [StadiumBorder].
///
/// Use this only for UI that is intentionally pill-shaped. Cards, tiles,
/// fields, sheets, and non-capsule controls use `Squircle`.
class AsterPill extends StatelessWidget {
  const AsterPill({
    super.key,
    required this.child,
    this.color,
    this.gradient,
    this.padding = EdgeInsets.zero,
    this.side = BorderSide.none,
    this.shadows = const [],
  });

  final Widget child;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final BorderSide side;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        shape: StadiumBorder(side: side),
        shadows: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
