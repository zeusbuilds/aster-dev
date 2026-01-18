import 'package:flutter/material.dart';
import 'package:aster/shared/shared.dart';
import 'package:country_flags/country_flags.dart';

/// Widget representing a single country option in the country selection list
/// Shows country flag, name, and selection indicator
class CountrySelectOptionRow extends StatelessWidget {
  /// The country model to display
  final CountryModel country;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// Code of the currently selected country (CountryModel.code)
  final int selected;

  const CountrySelectOptionRow({
    super.key,
    required this.country,
    this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.spacing20,
          vertical: spacing.spacing16,
        ),
        child: Row(
          children: [
            CountryFlag.fromCountryCode(
              country.code,
              theme: ImageTheme(
                shape: Circle(),
                height: spacing.spacing28,
                width: spacing.spacing28,
              ),
            ),
            SizedBox(width: spacing.spacing16),
            Expanded(
              child: Text(
                country.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.text1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: spacing.spacing32),
            CustomRadio(
              option: 0,
              selected: selected,
              onChanged: (value) {
                onTap?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
