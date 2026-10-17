import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Keeps form actions at the bottom when space permits and scrolls the entire
/// form when the keyboard or large text leaves insufficient room.
///
/// The caller owns horizontal padding and the top/side safe area. Scrolling
/// roots can include their bottom safe inset in [bottomPadding] so it moves
/// with the form rather than shortening the viewport. Children must be finite
/// content, without Expanded or independently scrolling viewports.
class AsterFormBody extends StatelessWidget {
  const AsterFormBody({
    super.key,
    required this.content,
    required this.actions,
    this.bottomPadding = 0,
  }) : assert(bottomPadding >= 0);

  final Widget content;
  final List<Widget> actions;

  /// Space after the final action, inside the scrolling content.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: content),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(
              top: context.spacing.sectionGap,
              bottom: bottomPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
        ),
      ],
    );
  }
}
