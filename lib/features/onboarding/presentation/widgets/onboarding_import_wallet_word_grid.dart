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
    final colors = context.colors;
    final radius = context.radius;
    final textTheme = context.textTheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        mainAxisSpacing: spacing.spacing8,
        crossAxisSpacing: spacing.spacing8,
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
            horizontal: spacing.spacing12,
            vertical: spacing.spacing6,
          ),
          decoration: BoxDecoration(
            color: colors.fill1.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(radius.radius24),
            border: Border.all(
              color: colors.fill1.withValues(alpha: 0.1),
              width: 0.6,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                '$number',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.text5.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: spacing.spacing6),
              Expanded(
                child: word != null
                    ? Text(
                        word,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.text5,
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
                  size: spacing.spacing18,
                  color: isValid ? colors.success6 : colors.danger6,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
