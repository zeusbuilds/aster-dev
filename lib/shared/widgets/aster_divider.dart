import 'package:flutter/material.dart';

import '../theme/theme.dart';

class AsterDivider extends StatelessWidget {
  const AsterDivider({super.key}) : inset = false;

  const AsterDivider.inset({super.key}) : inset = true;

  final bool inset;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final strokes = context.strokes;
    final resolvedIndent = inset ? spacing.screenPadding : spacing.none;

    return Divider(
      color: context.appColors.borderSubtle,
      height: strokes.divider,
      thickness: strokes.divider,
      indent: resolvedIndent,
      endIndent: resolvedIndent,
    );
  }
}
