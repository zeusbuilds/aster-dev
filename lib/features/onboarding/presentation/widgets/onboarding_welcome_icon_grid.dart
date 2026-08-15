import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// 4×7 icon grid used on the onboarding welcome hero.
class OnboardingWelcomeIconGrid extends StatelessWidget {
  const OnboardingWelcomeIconGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final effects = context.effects;
    final rows = art.onboardingIconRows;
    final cols = art.onboardingIconColumns;
    final total = rows * cols;

    final centerIndex =
        art.onboardingIconHighlightRow * cols +
        art.onboardingIconHighlightColumn;
    // Authored tile composition in row-major order. Visual effect values stay
    // in the semantic effects system.
    const faintTiles = <List<bool>>[
      [false, true, false, false, false, false, true],
      [false, false, true, false, true, false, false],
      [true, false, true, false, false, true, false],
      [false, true, false, false, true, false, true],
    ];

    return AspectRatio(
      aspectRatio: cols / rows,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: art.onboardingIconGridGap,
          crossAxisSpacing: art.onboardingIconGridGap,
        ),
        itemCount: total,
        itemBuilder: (context, index) {
          if (index == centerIndex) {
            return const _CenterTile();
          }

          final row = index ~/ cols;
          final col = index % cols;
          final faint = faintTiles[row][col];

          return _GlassTile(
            opacity: faint
                ? effects.onboardingIconTileFaintOpacity
                : effects.onboardingIconTileStrongOpacity,
            outlined: faint,
          );
        },
      ),
    );
  }
}

class _CenterTile extends StatelessWidget {
  const _CenterTile();

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final spacing = context.spacing;
    final colors = context.appColors;

    return Squircle(
      padding: EdgeInsets.all(spacing.sm),
      borderRadius: art.onboardingIconTileRadius,
      borderColor: colors.transparentSurface,
      borderWidth: 0,
      color: context.colorScheme.surface,
      child: Center(child: SvgPicture.asset('assets/icons/tokens/usdt.svg')),
    );
  }
}

class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.opacity, required this.outlined});

  final double opacity;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final colors = context.appColors;
    final effects = context.effects;
    final strokes = context.strokes;

    return Squircle(
      borderRadius: art.onboardingIconTileRadius,
      borderColor: outlined
          ? context.colorScheme.surface.withValues(
              alpha: effects.brandGlassBorderOpacity,
            )
          : colors.transparentSurface,
      borderWidth: outlined ? strokes.hairline : 0,
      color: context.colorScheme.surface.withValues(alpha: opacity),
      padding: EdgeInsets.zero,
      child: const SizedBox.expand(),
    );
  }
}
