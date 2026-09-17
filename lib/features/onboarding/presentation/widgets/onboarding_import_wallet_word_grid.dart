import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../shared/shared.dart';

/// Displays a generated 12-word phrase as columns 1-6 and 7-12.
class OnboardingImportWalletWordGrid extends StatelessWidget {
  const OnboardingImportWalletWordGrid({
    super.key,
    required this.words,
    this.obscured = false,
  }) : assert(words.length == wordCount);

  static const wordCount = 12;
  static const wordsPerColumn = 6;

  final List<String> words;

  /// Prevents phrase words from being painted or exposed to accessibility.
  final bool obscured;

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
                child: _RecoveryWordTile(
                  index: left,
                  word: words[left],
                  obscured: obscured,
                ),
              ),
              SizedBox(width: context.spacing.sm),
              Expanded(
                child: _RecoveryWordTile(
                  index: right,
                  word: words[right],
                  obscured: obscured,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RecoveryWordTile extends StatelessWidget {
  const _RecoveryWordTile({
    required this.index,
    required this.word,
    required this.obscured,
  });

  final int index;
  final String word;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(index.toDouble()),
      label: obscured
          ? 'Recovery word ${index + 1}, hidden'
          : '${index + 1}. $word',
      excludeSemantics: true,
      child: Squircle(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.md,
          vertical: context.spacing.sm,
        ),
        borderRadius: context.radii.recoveryWord,
        color: colors.surfaceSubtle,
        borderColor: colors.borderSubtle,
        borderWidth: context.strokes.hairline,
        child: Row(
          children: [
            Text(
              '${index + 1}.',
              style: context.type.assetMeta.toNumeric(context),
            ),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: Text(
                obscured ? '••••••' : word,
                style: context.type.rowTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
