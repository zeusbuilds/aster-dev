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
    this.announceValidation = false,
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
      announceValidation = false,
      _content = null,
      _loadingTarget = target;

  final bool amountLocked;
  final String? validationMessage;
  final bool announceValidation;
  final _SendCardContent? _content;
  final WalletPaymentTarget? _loadingTarget;

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final paymentRoute = content?.route;
    final target = paymentRoute?.target ?? _loadingTarget!;
    final displaySymbol =
        content?.available.unit ??
        switch (target.assetKind) {
          WalletAssetKind.bitcoin => 'BTC',
          WalletAssetKind.usdt => 'USDT',
        };
    final card = AsterSplitCard(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WalletAmountEntry(
            value: content?.amountText ?? '',
            unit: displaySymbol,
            assetKind: target.assetKind,
          ),
          SizedBox(height: context.spacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AmountText(
                  content == null ? 'Loading estimate' : content.fiatText,
                  style: context.type.rowMeta.copyWith(
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
            AsterStatusMessage(
              message,
              tone: AsterStatusTone.danger,
              announce: announceValidation,
              textAlign: TextAlign.start,
            ),
          ],
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
              const CustomButton.compact(
                text: 'Max',
                variant: ButtonVariant.neutral,
                enabled: false,
              ),
            ],
          ),
          if (content != null) ...[
            SizedBox(height: context.spacing.sm),
            Text(
              amountLocked
                  ? 'Max unavailable: fixed invoice amount.'
                  : 'Max unavailable: fee-aware quote needed.',
              style: context.type.rowMeta.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (content != null) return card;
    return Semantics(
      liveRegion: true,
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
