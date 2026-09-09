import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Keeps form actions at the bottom when space permits and scrolls the entire
/// form when the keyboard or large text leaves insufficient room.
///
/// The caller owns horizontal padding and SafeArea. Children must be finite
/// content, without Expanded or independently scrolling viewports.
class AsterFormBody extends StatelessWidget {
  const AsterFormBody({
    super.key,
    required this.content,
    required this.actions,
  });

  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: content),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(top: context.spacing.sectionGap),
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
