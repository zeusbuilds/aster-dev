import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';

/// One page of the recovery phrase carousel: 4 word slots, 1 per row.
/// Use horizontal padding when placed in a full-width PageView.
class OnboardingImportWalletWordPage extends StatelessWidget {
  const OnboardingImportWalletWordPage({
    super.key,
    required this.words,
    required this.validationResults,
    required this.startNumber,
  });

  /// Exactly 4 words for this page (indices 0–3).
  final List<String?> words;

  /// Exactly 4 validation results for this page.
  final List<bool?> validationResults;

  /// Starting word number (1, 5, or 9).
  final int startNumber;

  static const int slotsPerPage = 4;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final radius = context.radii;
    final strokes = context.strokes;
    final type = context.type;
    final icons = context.icons;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(slotsPerPage, (i) {
          final number = startNumber + i;
          final word =
              i < words.length && words[i] != null && words[i]!.isNotEmpty
              ? words[i]!
              : null;
          final isValid =
              i < validationResults.length && validationResults[i] != null
              ? validationResults[i]!
              : null;

          return Padding(
            padding: EdgeInsets.only(
              bottom: i < slotsPerPage - 1 ? spacing.md : 0,
            ),
            child: Squircle(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.lg,
                vertical: spacing.md,
              ),
              borderRadius: radius.card,
              color: context.colorScheme.surface.withValues(
                alpha: effects.brandGlassSurfaceOpacity,
              ),
              borderColor: context.colorScheme.surface.withValues(
                alpha: effects.brandGlassBorderOpacity,
              ),
              borderWidth: strokes.hairline,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Text(
                      '$number.',
                      style: type.assetValue
                          .copyWith(
                            color: colors.onBrandArt.withValues(
                              alpha: effects.brandContentMutedOpacity,
                            ),
                          )
                          .toNumeric(context),
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: word != null
                          ? Text(
                              word,
                              style: type.assetValue.copyWith(
                                color: colors.onBrandArt,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (isValid == false) ...[
                      SizedBox(width: spacing.md),
                      Icon(
                        MingCuteIcons.mgc_close_fill,
                        size: icons.sm,
                        color: colors.danger,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
