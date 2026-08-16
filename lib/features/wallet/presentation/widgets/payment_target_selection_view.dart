import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import 'payment_target_tile.dart';

/// Shared loading, failure, and four-target list for payment entry screens.
class PaymentTargetSelectionView extends StatefulWidget {
  const PaymentTargetSelectionView({
    super.key,
    required this.capabilities,
    required this.onSelected,
    required this.onRetry,
  });

  final AsyncValue<List<WalletPaymentCapability>> capabilities;
  final Future<void> Function(WalletPaymentTarget target) onSelected;
  final VoidCallback onRetry;

  @override
  State<PaymentTargetSelectionView> createState() =>
      _PaymentTargetSelectionViewState();
}

final class _PaymentTargetSelectionViewState
    extends State<PaymentTargetSelectionView> {
  var _selectionInFlight = false;

  void _handleSelected(WalletPaymentTarget target) {
    if (_selectionInFlight) return;
    setState(() => _selectionInFlight = true);
    unawaited(context.haptics.trigger(HapticIntent.selection));
    unawaited(_completeSelection(target));
  }

  Future<void> _completeSelection(WalletPaymentTarget target) async {
    try {
      await widget.onSelected(target);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'UTEXO payment navigation',
          context: ErrorDescription('while opening a payment target'),
        ),
      );
    } finally {
      if (mounted) setState(() => _selectionInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.capabilities.when(
      skipLoadingOnRefresh: false,
      data: (items) => _PaymentTargetList(
        capabilities: items,
        onSelected: _selectionInFlight ? null : _handleSelected,
      ),
      loading: () => const _PaymentTargetLoading(),
      error: (error, stackTrace) => _PaymentTargetFailure(
        failure: error is AppFailureException
            ? error.failure
            : FailureMapper.from(error, stackTrace),
        onRetry: widget.onRetry,
      ),
    );
  }
}

final class _PaymentTargetList extends StatelessWidget {
  const _PaymentTargetList({required this.capabilities, this.onSelected});

  final List<WalletPaymentCapability> capabilities;
  final ValueChanged<WalletPaymentTarget>? onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: capabilities.length,
      separatorBuilder: (context, index) =>
          SizedBox(height: context.spacing.sm),
      itemBuilder: (context, index) => PaymentTargetTile(
        capability: capabilities[index],
        onSelected: onSelected,
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
