import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Four rows of square tiles used on the onboarding welcome hero.
class OnboardingWelcomeIconGrid extends StatelessWidget {
  const OnboardingWelcomeIconGrid({super.key, this.referenceWidth});

  /// The width of the original grid when expanding it across a wider window.
  final double? referenceWidth;

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final rows = art.onboardingIconRows;
    final baseColumns = art.onboardingIconColumns;
    final gap = art.onboardingIconGridGap;
    if (referenceWidth case final width?) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Include a trailing gap when comparing tile pitches. Round to the
          // nearest odd column count to keep one highlighted tile centered.
          final pitch = (width + gap) / baseColumns;
          final columns = ((constraints.maxWidth + gap) / pitch - 1) / 2;
          final count = 2 * columns.round() + 1;
          final tileSize = (constraints.maxWidth + gap) / count - gap;
          return SizedBox(
            height: rows * tileSize + (rows - 1) * gap,
            child: _buildGrid(context, count, padding: EdgeInsets.zero),
          );
        },
      );
    }
    return AspectRatio(
      aspectRatio: baseColumns / rows,
      child: _buildGrid(context, baseColumns),
    );
  }

  Widget _buildGrid(BuildContext context, int cols, {EdgeInsets? padding}) {
    final art = context.art;
    final effects = context.effects;
    final rows = art.onboardingIconRows;
    final extraBefore = (cols - art.onboardingIconColumns) ~/ 2;
    final centerIndex =
        art.onboardingIconHighlightRow * cols +
        art.onboardingIconHighlightColumn +
        extraBefore;
    // Authored tile composition in row-major order. Visual effect values stay
    // in the semantic effects system.
    const faintTiles = <List<bool>>[
      [false, true, false, false, false, false, true],
      [false, false, true, false, true, false, false],
      [true, false, true, false, false, true, false],
      [false, true, false, false, true, false, true],
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: art.onboardingIconGridGap,
        crossAxisSpacing: art.onboardingIconGridGap,
      ),
      itemCount: rows * cols,
      itemBuilder: (context, index) {
        if (index == centerIndex) {
          return const _CenterTile();
        }

        final row = index ~/ cols;
        final col = (index % cols - extraBefore) % art.onboardingIconColumns;
        final faint = faintTiles[row][col];

        return _GlassTile(
          opacity: faint
              ? effects.onboardingIconTileFaintOpacity
              : effects.onboardingIconTileStrongOpacity,
          outlined: faint,
        );
      },
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
