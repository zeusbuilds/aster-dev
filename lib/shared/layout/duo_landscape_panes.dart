import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Two independently scrolling surfaces separated at the center of the Duo.
class DuoLandscapePanes extends StatelessWidget {
  const DuoLandscapePanes({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController.none(
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeRight: true,
              child: left,
            ),
          ),
          VerticalDivider(
            width: context.strokes.border,
            thickness: context.strokes.border,
            color: context.appColors.borderSubtle,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: right,
            ),
          ),
        ],
      ),
    );
  }
}
