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
    final radius = context.radii;
    final textTheme = context.textTheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        mainAxisSpacing: spacing.sm,
        crossAxisSpacing: spacing.sm,
        childAspectRatio: 4.5,
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

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: context.colorScheme.surface.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(radius.card),
            border: Border.all(
              color: context.colorScheme.surface.withValues(alpha: 0.1),
              width: 0.6,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                '$number',
                style: textTheme.labelSmall?.copyWith(
                  color: AsterColors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: word != null
                    ? Text(
                        word,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AsterColors.white,
                          fontWeight: FontWeight.w500,
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
                  size: spacing.xl,
                  color: isValid ? colors.success : colors.danger,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
