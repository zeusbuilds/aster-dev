import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'duo_display_layout.dart';

/// The tab capsule's footprint on either Duo display. Only the app shell
/// installs this scope, so pushed routes retain their own spacing.
class CoverTabRail extends InheritedWidget {
  const CoverTabRail({required this.bounds, required super.child, super.key});

  final Rect? bounds;

  static Rect? boundsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverTabRail>()?.bounds;

  /// Whether the app shell needs clearance for its bottom tabs.
  static bool hasBottomFallbackOf(BuildContext context) {
    final rail = context.dependOnInheritedWidgetOfExactType<CoverTabRail>();
    return rail != null && rail.bounds == null;
  }

  /// Fits the capsule in the free region reported by the active UIKit view.
  static Rect? resolve(
    BuildContext context,
    DuoDisplayLayout? geometry,
    int itemCount,
  ) {
    final size = MediaQuery.sizeOf(context);
    final band = geometry?.railBand;
    if (geometry == null ||
        band == null ||
        !(geometry.isCover
            ? geometry.appliesTo(size)
            : geometry.isOpenLandscapeFor(size))) {
      return null;
    }

    final insets = MediaQuery.viewPaddingOf(context);
    final obscured = MediaQuery.viewInsetsOf(context);
    final onRight = geometry.isCover || band.center.dx >= size.width / 2;
    final start = math.max(
      band.left,
      onRight ? size.width - insets.right : obscured.left,
    );
    final end = math.min(
      band.right,
      onRight ? size.width - obscured.right : insets.left,
    );
    final spacing = context.spacing.sm;
    final ceiling = geometry.isCover
        ? math.max(0.0, band.top)
        : math.max(band.top, math.max(insets.top, obscured.top)) + spacing;
    final floor =
        math.min(
          band.bottom,
          size.height - math.max(insets.bottom, obscured.bottom),
        ) -
        spacing;
    final availableHeight = floor - ceiling;
    final minTarget = context.metrics.minTouchTarget;
    if (end - start < minTarget || availableHeight < itemCount * minTarget) {
      return null;
    }

    final preferred = context.metrics.bottomNavHeight;
    final railWidth = math.min(preferred, end - start);
    final railHeight = math.min(preferred * itemCount, availableHeight);
    return Rect.fromLTWH(
      (start + end - railWidth) / 2,
      floor - railHeight,
      railWidth,
      railHeight,
    );
  }

  @override
  bool updateShouldNotify(CoverTabRail oldWidget) => bounds != oldWidget.bounds;
}
