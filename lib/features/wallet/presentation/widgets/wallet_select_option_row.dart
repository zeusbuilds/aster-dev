import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import '../../data/models/models.dart';

/// Widget representing a single wallet option in the wallet selection list
/// Shows wallet name, ID, and selection indicator
class WalletSelectOptionRow extends StatelessWidget {
  /// The wallet model to display
  final WalletModel wallet;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// ID of the currently selected wallet (WalletModel.id)
  final int selected;

  const WalletSelectOptionRow({
    super.key,
    required this.wallet,
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
            CustomRadio(
              option: wallet.id,
              selected: selected,
              onChanged: (value) {
                onTap?.call();
              },
            ),
            SizedBox(width: spacing.spacing16),
            Expanded(
              child: Text(
                wallet.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.text1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: spacing.spacing32),
            Text(
              wallet.walletId,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text1,
              ),
              maxLines: 1,
            ),
            SizedBox(width: spacing.spacing12),
            Icon(
              MingCuteIcons.mgc_edit_2_line,
              size: spacing.spacing18,
              color: colors.text3,
            ),
          ],
        ),
      ),
    );
  }
}
