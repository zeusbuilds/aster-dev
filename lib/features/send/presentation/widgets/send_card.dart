import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';

/// Exact amount, quote, and available-balance surface for Send.
class SendCard extends StatelessWidget {
  const SendCard({
    super.key,
    required this.route,
    required this.amountText,
    required this.available,
    required this.fiatText,
    required this.amountLocked,
    this.validationMessage,
  });

  final PaymentRoute route;
  final String amountText;
  final FormattedWalletAmount available;
  final String fiatText;
  final bool amountLocked;
  final String? validationMessage;

  @override
  Widget build(BuildContext context) {
    final target = route.target;
    final asset = target.assetModel;
    return Column(
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
                      amountText.isEmpty ? '0' : amountText,
                      style: context.type.amountLarge,
                      maxLines: 1,
                    ),
                  ),
                  SizedBox(width: context.spacing.md),
                  SvgPicture.asset(
                    asset.icon,
                    width: context.icons.lg,
                    height: context.icons.lg,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.circle,
                      size: context.icons.lg,
                      color: AssetDisplay.colorOf(context, asset),
                    ),
                  ),
                  SizedBox(width: context.spacing.sm),
                  Text(route.asset.symbol, style: context.type.title),
                ],
              ),
              SizedBox(height: context.spacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountText(
                      fiatText,
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
                      'Available: ${available.text}',
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
              CustomButton.compact(text: 'Max', enabled: false, onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }
}
