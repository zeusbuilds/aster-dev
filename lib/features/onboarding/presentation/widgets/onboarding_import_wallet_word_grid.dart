import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';

/// Grid of 12 placeholder slots for recovery phrase words (UI only, no TextFields).
///
/// Optional [words]: length 12; display this text in each slot when non-null.
/// Optional [validationResults]: length 12; `true` = green check, `false` = red cross,
/// `null` = no indicator. Omit or pass null to show no icons.
class OnboardingImportWalletWordGrid extends StatelessWidget {
  const OnboardingImportWalletWordGrid({
    super.key,
    this.words,
    this.validationResults,
  });

  static const int wordCount = 12;
  static const int columnCount = 2;

  /// Optional text to show in each slot (length 12); null = empty.
  final List<String?>? words;

  /// Per-field validation: true = correct (check), false = wrong (cross), null = not validated.
  final List<bool?>? validationResults;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final metrics = context.metrics;
    final radius = context.radii;
    final strokes = context.strokes;
    final type = context.type;
    final icons = context.icons;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        mainAxisSpacing: spacing.sm,
        crossAxisSpacing: spacing.sm,
        childAspectRatio: metrics.recoveryWordGridAspectRatio,
      ),
      itemCount: wordCount,
      itemBuilder: (context, index) {
        final number = index + 1;
        final word =
            words != null &&
                index < words!.length &&
                words![index] != null &&
                words![index]!.isNotEmpty
            ? words![index]!
            : null;
        final isValid =
            validationResults != null &&
                index < validationResults!.length &&
                validationResults![index] != null
            ? validationResults![index]!
            : null;

        return Squircle(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
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
                  '$number',
                  style: type.amountSmall.copyWith(
                    color: colors.onBrandArt.withValues(
                      alpha: effects.brandContentSubtleOpacity,
                    ),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: word != null
                      ? Text(
                          word,
                          style: type.rowTitle.copyWith(
                            color: colors.onBrandArt,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
                if (isValid != null) ...[
                  Icon(
                    isValid
                        ? MingCuteIcons.mgc_check_fill
                        : MingCuteIcons.mgc_close_fill,
                    size: icons.sm,
                    color: isValid ? colors.success : colors.danger,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
