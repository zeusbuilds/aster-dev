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
    // Reserve the reverse control's complete touch target in the layout. This
    // keeps it centred on the divider when either asset label wraps, and puts
    // 32px between each asset row and the divider (8px here + half the 48px
    // control), rather than the previous 24px.
    final pairPadding = context.spacing.sm;
    final controlExtent = context.metrics.minTouchTarget;
    return Squircle(
      color: context.colorScheme.surface,
      borderColor: context.appColors.borderSubtle,
      borderRadius: context.radii.card,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwapPair(
            label: 'From',
            target: state.from,
            onTap: onSelectFrom,
            padding: EdgeInsets.fromLTRB(
              context.spacing.screenPadding,
              context.spacing.xxl,
              context.spacing.screenPadding,
              pairPadding,
            ),
          ),
          SizedBox(
            height: controlExtent + context.strokes.divider,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ColoredBox(color: context.colorScheme.surface),
                      ),
                      const AsterDivider(),
                      Expanded(
                        child: ColoredBox(
                          color: context.appColors.surfaceSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appColors.surfaceSubtle,
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
                    onPressed: state.canReverse ? onReverse : null,
                  ),
                ),
              ],
            ),
          ),
          ColoredBox(
            color: context.appColors.surfaceSubtle,
            child: SwapPair(
              label: 'To',
              target: state.to,
              onTap: onSelectTo,
              padding: EdgeInsets.fromLTRB(
                context.spacing.screenPadding,
                pairPadding,
                context.spacing.screenPadding,
                context.spacing.xxl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
