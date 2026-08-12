import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';

/// Widget representing a single wallet option in the wallet selection list
///
/// Shows wallet name, ID, and selection indicator
class WalletSelectOptionRow extends StatelessWidget {
  /// The wallet model to display
  final WalletProfile wallet;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// Whether this wallet is currently selected.
  final bool selected;

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

    void select() {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: '${wallet.name}, ${wallet.displayId}',
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkWell(
          onTap: onTap == null ? null : select,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screenPadding,
              vertical: spacing.lg,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: CustomRadio(option: true, selected: selected),
                  ),
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
      ),
    );
  }
}
