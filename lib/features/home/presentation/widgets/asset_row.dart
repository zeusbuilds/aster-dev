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
    this.denomination,
    this.loading = false,
    this.fiatLoading = false,
    this.fiatSemanticContext,
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
      fiatContext: display.fiatLabel ?? display.fiatContext,
      fiatSemanticContext: display.fiatContext,
      denomination: display.total.unit,
      balancesVisible: balancesVisible,
      fiatLoading: fiatLoading,
      onTap: onTap,
    );
  }

  /// Display denomination follows the persisted Bitcoin unit preference.
  final String? denomination;
  final WalletAssetKind kind;
  final String title;
  final String totalText;
  final String availableText;
  final String fiatContext;
  final String? fiatSemanticContext;
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
              '${fiatLoading ? 'fiat estimate loading' : fiatSemanticContext ?? fiatContext}';
    return Semantics(
      button: onTap != null,
      enabled: onTap != null && !loading,
      onTap: loading ? null : onTap,
      label: semanticValue,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth =
                    (constraints.maxWidth -
                        context.icons.xl -
                        context.spacing.md * 2) /
                    3;
                final stacked =
                    unwrappedTextWidth(
                      context,
                      title,
                      context.type.assetTitle,
                    ) >
                    columnWidth;
                final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: context.type.assetTitle),
                    SizedBox(height: context.spacing.xxs),
                    Text(
                      denomination ??
                          (kind == WalletAssetKind.bitcoin ? 'BTC' : 'USDT'),
                      style: context.type.assetMeta,
                    ),
                  ],
                );
                final values = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppSkeletonizer(
                      enabled: loading || (fiatLoading && !hidden),
                      child: _BalanceValue(
                        value: hidden ? '••••' : fiatContext,
                        style: context.type.assetValue,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(height: context.spacing.xxs),
                    AppSkeletonizer(
                      enabled: loading,
                      child: _BalanceValue(
                        value: hidden ? '••••' : totalText,
                        style: context.type.assetMeta,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                );
                return Row(
                  crossAxisAlignment: stacked
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    WalletAssetIcon(kind: kind, size: context.icons.xl),
                    SizedBox(width: context.spacing.md),
                    if (stacked)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            identity,
                            SizedBox(height: context.spacing.sm),
                            values,
                          ],
                        ),
                      )
                    else ...[
                      Expanded(child: identity),
                      SizedBox(width: context.spacing.md),
                      Expanded(flex: 2, child: values),
                    ],
                  ],
                );
              },
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
