import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// One side of the non-executable swap target selection.
class SwapPair extends StatelessWidget {
  const SwapPair({
    super.key,
    required this.label,
    required this.target,
    required this.onTap,
  });

  final String label;
  final WalletPaymentTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${target.semanticLabel}',
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.screenPadding,
                vertical: context.spacing.xxl,
              ),
              child: Row(
                children: [
                  Text(label, style: context.type.rowMeta),
                  SizedBox(width: context.spacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            WalletAssetIcon(
                              kind: target.assetKind,
                              size: context.icons.lg,
                            ),
                            SizedBox(width: context.spacing.sm),
                            Flexible(
                              child: Text(
                                '${target.assetLabel} · ${target.railLabel}',
                                style: context.type.rowTitleStrong,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: context.spacing.xs),
                  Icon(
                    RemixIcons.arrow_right_s_line,
                    size: context.icons.sm,
                    color: context.appColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
