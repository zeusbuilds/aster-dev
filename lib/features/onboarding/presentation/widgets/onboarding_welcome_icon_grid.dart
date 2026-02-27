import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// 4×7 icon grid used on the onboarding welcome hero.
class OnboardingWelcomeIconGrid extends StatelessWidget {
  const OnboardingWelcomeIconGrid({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = 4;
    const cols = 7;
    const total = rows * cols;

    // Center highlight tile (3rd from left, 2nd row).
    const centerRow = 1;
    const centerCol = 3;
    const centerIndex = centerRow * cols + centerCol;

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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
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
    final radius = context.radius;
    final spacing = context.spacing;
    final colors = context.colors;

    return Container(
      padding: EdgeInsets.all(spacing.spacing6),
      decoration: BoxDecoration(
        color: colors.fill1,
        borderRadius: BorderRadius.circular(radius.radius4),
      ),
      child: Center(child: SvgPicture.asset('assets/icons/tokens/usdc.svg')),
    );
  }
}

class _BlurTile extends StatelessWidget {
  const _BlurTile({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final radiusTokens = context.radius;
    final colors = context.colors;

    final radius = BorderRadius.circular(radiusTokens.radius4);
    final hasBorder = (opacity - 0.05).abs() < 0.001;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: colors.fill1.withValues(alpha: opacity),
            border: hasBorder
                ? Border.all(
                    color: colors.fill1.withValues(alpha: 0.1),
                    width: 0.6,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
