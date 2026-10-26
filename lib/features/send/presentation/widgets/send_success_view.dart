import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// Terminal confirmation rendered only after the wallet accepts the payment.
///
/// The amount comes from the authoritative result, independent of editable
/// input, fiat quotes, fees, or the resulting wallet balance.
class SendSuccessView extends StatelessWidget {
  const SendSuccessView({
    super.key,
    required this.result,
    required this.bitcoinUnit,
    required this.onContinue,
    this.continuing = false,
  });

  final WalletSendResult result;
  final BitcoinUnit bitcoinUnit;
  final VoidCallback onContinue;
  final bool continuing;

  @override
  Widget build(BuildContext context) {
    final amount = WalletAmountDisplayFormatter().format(
      units: result.amount.units,
      route: result.route,
      bitcoinUnit: bitcoinUnit,
    );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.screenPadding,
        ),
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom:
                      context.windowInsets.bottomSystem + context.spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: context.spacing.sectionGap,
                          ),
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            label:
                                'Payment sent, ${result.route.asset.kind.displayName}, ${amount.text}',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WalletAssetIcon(
                                  kind: result.route.asset.kind,
                                  size: context.icons.xl * 2,
                                ),
                                SizedBox(height: context.spacing.xxl),
                                AmountText(
                                  amount.text,
                                  style: context.type.amountLarge,
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: context.spacing.md),
                                Text(
                                  'Payment sent',
                                  style: context.type.title,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    QuietPendingAction(
                      pending: continuing,
                      label: 'Continue',
                      child: CustomButton(
                        text: 'Continue',
                        hapticIntent: null,
                        onTap: onContinue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
