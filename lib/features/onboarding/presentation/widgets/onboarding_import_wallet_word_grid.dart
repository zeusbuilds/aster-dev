import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../shared/shared.dart';

/// Displays a generated 12-word phrase as columns 1-6 and 7-12.
class OnboardingImportWalletWordGrid extends StatelessWidget {
  const OnboardingImportWalletWordGrid({super.key, required this.words})
    : assert(words.length == wordCount);

  static const wordCount = 12;
  static const wordsPerColumn = 6;

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(wordsPerColumn, (row) {
        final left = row;
        final right = row + wordsPerColumn;
        return Padding(
          padding: EdgeInsets.only(
            bottom: row < wordsPerColumn - 1 ? context.spacing.sm : 0,
          ),
          child: Row(
            children: [
              Expanded(
                child: _RecoveryWordTile(index: left, word: words[left]),
              ),
              SizedBox(width: context.spacing.sm),
              Expanded(
                child: _RecoveryWordTile(index: right, word: words[right]),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RecoveryWordTile extends StatelessWidget {
  const _RecoveryWordTile({required this.index, required this.word});

  final int index;
  final String word;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = context.effects;
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(index.toDouble()),
      label: '${index + 1}. $word',
      excludeSemantics: true,
      child: Squircle(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.md,
          vertical: context.spacing.sm,
        ),
        borderRadius: context.radii.recoveryWord,
        color: effects.brandGlassContentSurface(context.colorScheme),
        borderColor: context.colorScheme.surface.withValues(
          alpha: effects.brandGlassBorderOpacity,
        ),
        borderWidth: context.strokes.hairline,
        child: Row(
          children: [
            Text(
              '${index + 1}.',
              style: context.type.assetMeta
                  .copyWith(color: colors.onBrandArt)
                  .toNumeric(context),
            ),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: Text(
                word,
                style: context.type.rowTitle.copyWith(color: colors.onBrandArt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
