import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import 'payment_target_tile.dart';

const _paymentTargetOrder = [
  WalletPaymentTarget.bitcoinOnchain,
  WalletPaymentTarget.usdtOnchain,
  WalletPaymentTarget.bitcoinLightning,
  WalletPaymentTarget.usdtLightning,
];

/// Shared four-target list for payment entry screens.
class PaymentTargetSelectionView extends StatelessWidget {
  const PaymentTargetSelectionView({
    super.key,
    required this.capabilities,
    required this.onSelected,
    this.selectedTarget,
    this.selectionEnabled = true,
  });

  final List<WalletPaymentCapability> capabilities;
  final Future<void> Function(WalletPaymentTarget target) onSelected;
  final WalletPaymentTarget? selectedTarget;
  final bool selectionEnabled;

  @override
  Widget build(BuildContext context) {
    if (AsterNavigationScope.maybeOf(context) != null) {
      return _buildContent(context);
    }
    return AsterNavigationScope(child: Builder(builder: _buildContent));
  }

  Widget _buildContent(BuildContext context) {
    final navigation = AsterNavigationScope.of(context);
    return _PaymentTargetList(
      capabilities: capabilities,
      selectedTarget: selectedTarget,
      onSelected: !selectionEnabled || navigation.inFlight
          ? null
          : (target) => unawaited(
              navigation.openRoute(
                command: () => onSelected(target),
                failureTitle: 'Payment option could not be opened',
                hapticIntent: HapticIntent.selection,
              ),
            ),
    );
  }
}

final class _PaymentTargetList extends StatelessWidget {
  const _PaymentTargetList({
    required this.capabilities,
    this.onSelected,
    this.selectedTarget,
  });

  final List<WalletPaymentCapability> capabilities;
  final ValueChanged<WalletPaymentTarget>? onSelected;
  final WalletPaymentTarget? selectedTarget;

  @override
  Widget build(BuildContext context) {
    final items = [...capabilities]
      ..sort(
        (first, second) => _paymentTargetOrder
            .indexOf(first.target)
            .compareTo(_paymentTargetOrder.indexOf(second.target)),
      );
    return ListView.separated(
      padding: EdgeInsets.only(
        top: context.spacing.md,
        bottom: context.windowInsets.bottomSafe + context.spacing.lg,
      ),
      itemCount: items.length,
      separatorBuilder: (context, index) =>
          SizedBox(height: context.spacing.md),
      itemBuilder: (context, index) => PaymentTargetTile(
        capability: items[index],
        onSelected: onSelected,
        selected: selectedTarget == null
            ? null
            : selectedTarget == items[index].target,
      ),
    );
  }
}
