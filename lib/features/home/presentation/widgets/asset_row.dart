import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../formatting/formatting.dart';

/// One typed cross-rail asset summary in the Home portfolio.
class AssetRow extends StatelessWidget {
  const AssetRow({
    super.key,
    required this.kind,
    required this.title,
    required this.totalText,
    required this.availableText,
    required this.fiatContext,
    required this.balancesVisible,
    this.onTap,
    this.loading = false,
    this.fiatLoading = false,
  });

  factory AssetRow.loading({
    required WalletAssetKind kind,
    required String title,
  }) {
    return AssetRow(
      kind: kind,
      title: title,
      totalText: kind == WalletAssetKind.bitcoin
          ? '0.00000000 BTC'
          : '0.000000 USDT',
      availableText: kind == WalletAssetKind.bitcoin
          ? '0.00000000 BTC'
          : '0.000000 USDT',
      fiatContext: 'Fiat estimate',
      balancesVisible: true,
      loading: true,
    );
  }

  factory AssetRow.loaded({
    Key? key,
    required HomeAssetDisplay display,
    required bool balancesVisible,
    bool fiatLoading = false,
    VoidCallback? onTap,
  }) {
    return AssetRow(
      key: key,
      kind: display.kind,
      title: display.title,
      totalText: display.total.text,
      availableText: display.available.text,
      fiatContext: display.fiatContext,
      balancesVisible: balancesVisible,
      fiatLoading: fiatLoading,
      onTap: onTap,
    );
  }

  final WalletAssetKind kind;
  final String title;
  final String totalText;
  final String availableText;
  final String fiatContext;
  final bool balancesVisible;
  final VoidCallback? onTap;
  final bool loading;
  final bool fiatLoading;

  @override
  Widget build(BuildContext context) {
    final hidden = !loading && !balancesVisible;
    final semanticValue = loading
        ? '$title balance loading'
        : hidden
        ? '$title balance hidden'
        : '$title total $totalText, available $availableText, '
              '${fiatLoading ? 'fiat estimate loading' : fiatContext}';
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticValue,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Row(
              children: [
                WalletAssetIcon(kind: kind, size: context.icons.xl),
                SizedBox(width: context.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(title, style: context.type.assetTitle),
                          ),
                          SizedBox(width: context.spacing.md),
                          Expanded(
                            child: AppSkeletonizer(
                              enabled: loading,
                              child: _BalanceValue(
                                value: hidden ? '••••' : totalText,
                                style: context.type.assetValue,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: context.spacing.xxs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppSkeletonizer(
                              enabled: loading || (fiatLoading && !hidden),
                              child: Text(
                                hidden ? 'Balance hidden' : fiatContext,
                                style: context.type.assetMeta.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          SizedBox(width: context.spacing.md),
                          Expanded(
                            child: AppSkeletonizer(
                              enabled: loading,
                              child: _BalanceValue(
                                value: hidden
                                    ? 'Available ••••'
                                    : 'Available $availableText',
                                style: context.type.assetMeta.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                                maxLines: 2,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceValue extends StatelessWidget {
  const _BalanceValue({
    required this.value,
    required this.style,
    this.maxLines = 1,
    this.textAlign,
  });

  final String value;
  final TextStyle style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AmountText(
      value,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
