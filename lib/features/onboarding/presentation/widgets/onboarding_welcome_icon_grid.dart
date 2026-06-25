import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// 4×7 icon grid used on the onboarding welcome hero.
class OnboardingWelcomeIconGrid extends StatelessWidget {
  const OnboardingWelcomeIconGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final rows = art.onboardingIconRows;
    final cols = art.onboardingIconColumns;
    final total = rows * cols;

    // Center highlight tile (3rd from left, 2nd row).
    const centerRow = 1;
    const centerCol = 3;
    final centerIndex = centerRow * cols + centerCol;
    // Per-tile opacities, row order: top → bottom, col order: left → right.
    const tileOpacities = <List<double>>[
      [0.30, 0.05, 0.30, 0.30, 0.30, 0.30, 0.05],
      [0.30, 0.30, 0.05, 0.30, 0.05, 0.30, 0.30],
      [0.05, 0.30, 0.05, 0.30, 0.30, 0.05, 0.30],
      [0.30, 0.05, 0.30, 0.30, 0.05, 0.30, 0.05],
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
          final opacity = tileOpacities[row][col];

          return _BlurTile(opacity: opacity);
        },
      ),
    );
  }
}

class _CenterTile extends StatelessWidget {
  const _CenterTile();

  @override
  Widget build(BuildContext context) {
    final radius = context.radii;
    final spacing = context.spacing;
    final colors = context.appColors;

    return Squircle(
      padding: EdgeInsets.all(spacing.sm),
      borderRadius: radius.xs,
      borderColor: colors.transparentSurface,
      borderWidth: 0,
      color: context.colorScheme.surface,
      child: Center(child: SvgPicture.asset('assets/icons/tokens/usdc.svg')),
    );
  }
}

class _BlurTile extends StatelessWidget {
  const _BlurTile({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final radius = context.radii;
    final colors = context.appColors;
    final effects = context.effects;
    final art = context.art;
    final strokes = context.strokes;
    final hasBorder = (opacity - 0.05).abs() < 0.001;

    return Squircle(
      borderRadius: radius.xs,
      borderColor: hasBorder
          ? context.colorScheme.surface.withValues(
              alpha: effects.brandGlassBorderOpacity,
            )
          : colors.transparentSurface,
      borderWidth: hasBorder ? strokes.hairline : 0,
      color: context.colorScheme.surface.withValues(alpha: opacity),
      padding: EdgeInsets.zero,
      backdropFilter: ImageFilter.blur(
        sigmaX: art.onboardingIconBlurSigma,
        sigmaY: art.onboardingIconBlurSigma,
      ),
      child: const SizedBox.expand(),
    );
  }
}
