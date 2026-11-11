import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/theme.dart';
import '../widgets/aster_icon_button.dart';
import 'cover_tab_rail.dart';
import 'duo_landscape_scope.dart';

/// Places the page's Back action beneath the system status indicators on the
/// Duo inner display. The page retains its inline Back when the rail can't fit.
class DuoBackNavigation extends StatelessWidget {
  const DuoBackNavigation({
    super.key,
    required this.builder,
    this.onBack,
    this.showBack = true,
  });

  final Widget Function(BuildContext context, bool usesRail) builder;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rail = showBack
        ? context.duoLandscapeLayout?.availableRailFor(media)
        : null;
    final tabs = rail == null ? null : CoverTabRail.boundsOf(context);
    final size = context.metrics.minTouchTarget;

    return LayoutBuilder(
      builder: (context, constraints) {
        // A pane or sheet shares the window's MediaQuery but cannot position
        // and hit-test a control in the full window's coordinate space.
        final fits =
            rail != null &&
            (constraints.maxWidth - media.size.width).abs() <= 1 &&
            (constraints.maxHeight - media.size.height).abs() <= 1 &&
            rail.bounds.width >= size &&
            rail.bounds.height >= size;
        final bounds = fits
            ? Rect.fromLTWH(
                (rail.centerX - size / 2).clamp(
                  rail.bounds.left,
                  rail.bounds.right - size,
                ),
                rail.bounds.top,
                size,
                size,
              )
            : null;
        final usesRail = bounds != null && !(tabs?.overlaps(bounds) ?? false);
        return Stack(
          fit: StackFit.expand,
          children: [
            builder(context, usesRail),
            if (usesRail)
              Positioned.fromRect(
                rect: bounds,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    shadows: context.shadows.raised,
                  ),
                  child: Material(
                    color: context.appColors.surfaceRaised,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: AsterIconButton(
                      icon: RemixIcons.arrow_left_s_line,
                      tooltip: 'Back',
                      onPressed: onBack,
                      hapticIntent: null,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
