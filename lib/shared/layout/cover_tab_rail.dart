import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'duo_display_layout.dart';

/// The tab capsule's footprint on either Duo display. Routes with tabs
/// install this scope so other routes retain their own spacing.
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
    if (geometry == null) return null;
    final rail = geometry.availableRailFor(MediaQuery.of(context));
    if (rail == null) return null;

    final (bounds: band, :centerX) = rail;
    final spacing = context.spacing.sm;
    final ceiling = geometry.isCover ? band.top : band.top + spacing;
    final floor = band.bottom - spacing;
    final availableHeight = floor - ceiling;
    final minTarget = context.metrics.minTouchTarget;
    if (band.width < minTarget || availableHeight < itemCount * minTarget) {
      return null;
    }

    final preferred = context.metrics.bottomNavHeight;
    final railWidth = math.min(preferred, band.width);
    final railHeight = math.min(preferred * itemCount, availableHeight);
    return Rect.fromLTWH(
      (centerX - railWidth / 2).clamp(band.left, band.right - railWidth),
      floor - railHeight,
      railWidth,
      railHeight,
    );
  }

  @override
  bool updateShouldNotify(CoverTabRail oldWidget) => bounds != oldWidget.bounds;
}
