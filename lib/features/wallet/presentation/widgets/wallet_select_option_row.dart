import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';

/// Accessible single-choice row for one non-secret wallet profile.
class WalletSelectOptionRow extends StatelessWidget {
  const WalletSelectOptionRow({
    super.key,
    required this.wallet,
    required this.selected,
    required this.enabled,
    this.loading = false,
    this.onTap,
  });

  final WalletProfile wallet;

  /// Whether this is the current wallet.
  final bool selected;

  /// Whether the wallet choice set is available.
  ///
  /// A selected wallet remains enabled but has no tap action. An in-flight
  /// switch disables every choice until the repository returns.
  final bool enabled;

  /// Whether this row owns the current wallet-switch operation.
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final icons = context.icons;
    final effectiveOnTap = enabled && !selected && !loading ? onTap : null;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${wallet.name}, ${wallet.displayId}',
      value: loading ? 'Switching' : null,
      liveRegion: loading,
      onTap: effectiveOnTap,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: effectiveOnTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screenPadding,
              vertical: spacing.lg,
            ),
            child: Row(
              children: [
                AsterSelectionIndicator(selected: selected),
                SizedBox(width: spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.name,
                        style: context.type.rowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        wallet.displayId,
                        style: context.type.supportingMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.lg),
                SizedBox.square(
                  dimension: icons.md,
                  child: loading
                      ? const GridLoader(
                          colorStyle: GridLoaderColorStyle.themePrimary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
