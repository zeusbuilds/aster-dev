import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../models/models.dart';
import 'swap_pair.dart';

/// Typed pair selector with no quote or execution claims.
class SwapCard extends StatelessWidget {
  const SwapCard({
    super.key,
    required this.state,
    required this.onSelectFrom,
    required this.onSelectTo,
    required this.onReverse,
  });

  final SwapState state;
  final VoidCallback onSelectFrom;
  final VoidCallback onSelectTo;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Squircle(
          color: context.colorScheme.surface,
          borderColor: context.appColors.borderSubtle,
          borderRadius: context.radii.card,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwapPair(label: 'From', target: state.from, onTap: onSelectFrom),
              const AsterDivider(),
              SwapPair(label: 'To', target: state.to, onTap: onSelectTo),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(
              color: context.colorScheme.surface,
              width: context.strokes.focusRing,
            ),
          ),
          child: AsterIconButton(
            icon: RemixIcons.arrow_up_down_line,
            tooltip: 'Reverse swap direction',
            hapticIntent: HapticIntent.selection,
            onPressed: onReverse,
          ),
        ),
      ],
    );
  }
}
