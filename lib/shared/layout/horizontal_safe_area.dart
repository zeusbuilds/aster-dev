import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps screen content clear of side-mounted system UI, including the
/// iPhone Duo cover display. The enclosing scaffold still paints edge to edge.
///
/// The screen owns vertical spacing: a pinned action and a scrolling list
/// may apply the bottom inset in different places.
class AsterHorizontalSafeArea extends StatelessWidget {
  const AsterHorizontalSafeArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, bottom: false, child: child);
}

/// Keeps a full-window status centered on the display while clearing system
/// UI on either side. Content inside a pane keeps its local safe area.
class AsterCenteredSafeArea extends StatelessWidget {
  const AsterCenteredSafeArea({
    super.key,
    required this.child,
    this.centerHorizontally = true,
    this.top = true,
    this.bottom = true,
  });

  final Widget child;
  final bool centerHorizontally;
  final bool top;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = MediaQuery.sizeOf(context).width;
        final padding = MediaQuery.paddingOf(context);
        final fullWidth = (constraints.maxWidth - width).abs() <= 1;
        return SafeArea(
          top: top,
          bottom: bottom,
          minimum: EdgeInsets.symmetric(
            horizontal: centerHorizontally && fullWidth
                ? math.max(padding.left, padding.right)
                : 0,
          ),
          child: child,
        );
      },
    );
  }
}
