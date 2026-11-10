import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import 'payment_target_tile.dart';

const _paymentTargetOrder = [
  WalletPaymentTarget.bitcoinOnchain,
  WalletPaymentTarget.usdtOnchain,
  WalletPaymentTarget.bitcoinLightning,
  WalletPaymentTarget.usdtLightning,
];

/// Shared loading, failure, and four-target list for payment entry screens.
class PaymentTargetSelectionView extends StatelessWidget {
  const PaymentTargetSelectionView({
    super.key,
    required this.capabilities,
    required this.onSelected,
    required this.onRetry,
    this.selectedTarget,
    this.selectionEnabled = true,
  });

  final AsyncValue<List<WalletPaymentCapability>> capabilities;
  final Future<void> Function(WalletPaymentTarget target) onSelected;
  final VoidCallback onRetry;
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
    return capabilities.when(
      skipLoadingOnRefresh: false,
      data: (items) => _PaymentTargetList(
        capabilities: items,
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
      ),
      loading: () => const _PaymentTargetLoading(),
      error: (error, stackTrace) => _PaymentTargetFailure(
        failure: error is AppFailureException
            ? error.failure
            : FailureMapper.from(error, stackTrace),
        onRetry: onRetry,
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

final class _PaymentTargetLoading extends StatelessWidget {
  const _PaymentTargetLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading payment options',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: _PaymentTargetList(
          capabilities: WalletPaymentTarget.values
              .map(WalletPaymentCapability.unavailable)
              .toList(growable: false),
        ),
      ),
    );
  }
}

final class _PaymentTargetFailure extends StatelessWidget {
  const _PaymentTargetFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              failure.userMessage,
              style: context.type.statusMessage,
              textAlign: TextAlign.center,
            ),
          ),
          if (failure.retryable) ...[
            SizedBox(height: context.spacing.lg),
            CustomButton(text: 'Retry', onTap: onRetry),
          ],
        ],
      ),
    );
  }
}
