import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// Exact amount, quote, and available-balance surface for Send.
class SendCard extends StatelessWidget {
  SendCard({
    super.key,
    required PaymentRoute route,
    required String amountText,
    required FormattedWalletAmount available,
    required String fiatText,
    required this.amountLocked,
    this.validationMessage,
  }) : _content = _SendCardContent(
         route: route,
         amountText: amountText,
         available: available,
         fiatText: fiatText,
       ),
       _loadingTarget = null;

  /// Inert content skeleton with the same responsive geometry as the card.
  const SendCard.loading({super.key, required WalletPaymentTarget target})
    : amountLocked = false,
      validationMessage = null,
      _content = null,
      _loadingTarget = target;

  final bool amountLocked;
  final String? validationMessage;
  final _SendCardContent? _content;
  final WalletPaymentTarget? _loadingTarget;

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final paymentRoute = content?.route;
    final target = paymentRoute?.target ?? _loadingTarget!;
    final displaySymbol =
        paymentRoute?.asset.symbol ??
        switch (target.assetKind) {
          WalletAssetKind.bitcoin => 'BTC',
          WalletAssetKind.usdt => 'USDT',
        };
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(context.radii.card),
            topRight: Radius.circular(context.radii.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: context.spacing.lg,
            horizontal: context.spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NumericText(
                      content == null || content.amountText.isEmpty
                          ? '0'
                          : content.amountText,
                      style: context.type.amountLarge,
                      maxLines: 1,
                    ),
                  ),
                  SizedBox(width: context.spacing.md),
                  WalletAssetIcon(
                    kind: target.assetKind,
                    size: context.icons.lg,
                  ),
                  SizedBox(width: context.spacing.sm),
                  Text(displaySymbol, style: context.type.title),
                ],
              ),
              SizedBox(height: context.spacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountText(
                      content == null ? 'Loading estimate' : content.fiatText,
                      style: context.type.rowMetaStrong.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: context.spacing.md),
                  Expanded(
                    child: AmountText(
                      content == null
                          ? 'Available: Loading balance'
                          : 'Available: ${content.available.text}',
                      style: context.type.rowMetaStrong.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (validationMessage case final message?) ...[
                SizedBox(height: context.spacing.sm),
                Text(
                  message,
                  style: context.type.errorMessage.copyWith(
                    color: context.appColors.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
        Squircle(
          color: context.appColors.surfaceSubtle,
          borderColor: context.appColors.surfaceSubtle,
          border: BorderRadius.only(
            bottomLeft: Radius.circular(context.radii.card),
            bottomRight: Radius.circular(context.radii.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: context.spacing.sm,
            horizontal: context.spacing.xl,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  target.railLabel,
                  style: context.type.rowTitleStrong,
                ),
              ),
              if (amountLocked) ...[
                AsterPill(
                  color: context.colorScheme.primaryContainer,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.md,
                    vertical: context.spacing.xs,
                  ),
                  child: Text(
                    'Invoice amount',
                    style: context.type.badgeLabel.copyWith(
                      color: context.colorScheme.primary,
                    ),
                  ),
                ),
                SizedBox(width: context.spacing.sm),
              ],
              const CustomButton.compact(text: 'Max', enabled: false),
            ],
          ),
        ),
      ],
    );
    if (content != null) return card;
    return Semantics(
      label: 'Loading payment amount',
      excludeSemantics: true,
      child: AppSkeletonizer(enabled: true, child: card),
    );
  }
}

final class _SendCardContent {
  const _SendCardContent({
    required this.route,
    required this.amountText,
    required this.available,
    required this.fiatText,
  });

  final PaymentRoute route;
  final String amountText;
  final FormattedWalletAmount available;
  final String fiatText;
}
