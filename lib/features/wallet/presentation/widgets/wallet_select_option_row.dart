import 'package:flutter/material.dart';

import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../data/models/models.dart';

/// Widget representing a single wallet option in the wallet selection list
///
/// Shows wallet name, ID, and selection indicator
class WalletSelectOptionRow extends StatelessWidget {
  /// The wallet model to display
  final WalletProfile wallet;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// ID of the currently selected wallet.
  final String? selected;

  const WalletSelectOptionRow({
    super.key,
    required this.wallet,
    this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;

    return Semantics(
      button: onTap != null,
      selected: selected == wallet.id,
      label: '${wallet.name}, ${wallet.displayId}',
      child: GestureDetector(
        onTapDown: onTap != null
            ? (_) async {
                final canVibrate = await Haptics.canVibrate();
                if (canVibrate) {
                  await Haptics.vibrate(HapticsType.selection);
                }
              }
            : null,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.screenPadding,
            vertical: spacing.lg,
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
              SizedBox(width: spacing.lg),
              Expanded(
                child: Text(
                  wallet.name,
                  style: type.rowTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: spacing.xxxl),
              Text(wallet.displayId, style: type.rowValue, maxLines: 1),
              SizedBox(width: spacing.md),
              Icon(
                MingCuteIcons.mgc_edit_2_line,
                size: icons.sm,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
