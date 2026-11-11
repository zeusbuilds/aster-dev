import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// The square tile artwork used on the onboarding welcome hero.
class OnboardingWelcomeIconGrid extends StatelessWidget {
  const OnboardingWelcomeIconGrid({super.key}) : _section = null;

  /// Draws a rectangle within the staggered grid using its global coordinates.
  /// The optional highlight uses coordinates within this section.
  const OnboardingWelcomeIconGrid.section({
    super.key,
    required int columns,
    required int rows,
    required int startColumn,
    required int startRow,
    required int totalColumns,
    ({int row, int column, String asset})? highlight,
  }) : assert(columns > 0),
       assert(rows > 0),
       assert(startColumn >= 0),
       assert(startRow >= 0),
       assert(startColumn + columns <= totalColumns),
       _section = (
         columns: columns,
         rows: rows,
         startColumn: startColumn,
         startRow: startRow,
         totalColumns: totalColumns,
         highlight: highlight,
       );

  final ({
    int columns,
    int rows,
    int startColumn,
    int startRow,
    int totalColumns,
    ({int row, int column, String asset})? highlight,
  })?
  _section;

  // Authored tile composition in row-major order. The wider grid repeats
  // this pattern across its sections.
  static const _faintTiles = [
    [false, true, false, false, false, false, true],
    [false, false, true, false, true, false, false],
    [true, false, true, false, false, true, false],
    [false, true, false, false, true, false, true],
  ];

  @override
  Widget build(BuildContext context) {
    final art = context.art;
    final effects = context.effects;
    final section = _section;
    final rows = section?.rows ?? art.onboardingIconRows;
    final columns = section?.columns ?? art.onboardingIconColumns;
    final extraBefore =
        ((section?.totalColumns ?? columns) - art.onboardingIconColumns) ~/ 2;
    final highlight = section == null
        ? (
            row: art.onboardingIconHighlightRow,
            column: art.onboardingIconHighlightColumn,
            asset: 'assets/icons/tokens/usdt.svg',
          )
        : section.highlight;
    final gap = art.onboardingIconGridGap;
    final grid = GridView.builder(
      primary: section == null ? null : false,
      physics: const NeverScrollableScrollPhysics(),
      padding: section == null ? null : EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
      ),
      itemCount: rows * columns,
      itemBuilder: (context, index) {
        final localRow = index ~/ columns;
        final localColumn = index % columns;
        if (highlight != null &&
            localRow == highlight.row &&
            localColumn == highlight.column) {
          return _TokenTile(asset: highlight.asset);
        }

        final row = (section?.startRow ?? 0) + localRow;
        final column = (section?.startColumn ?? 0) + localColumn;
        final patternRow = _faintTiles[row % _faintTiles.length];
        final faint = patternRow[(column - extraBefore) % patternRow.length];

        return _GlassTile(
          opacity: faint
              ? effects.onboardingIconTileFaintOpacity
              : effects.onboardingIconTileStrongOpacity,
          outlined: faint,
        );
      },
    );
    if (section == null) {
      return AspectRatio(aspectRatio: columns / rows, child: grid);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth + gap) / columns - gap;
        return SizedBox(
          height: rows * tileSize + (rows - 1) * gap,
          child: grid,
        );
      },
    );
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({required this.asset});

  final String asset;

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
      child: Center(child: SvgPicture.asset(asset)),
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
