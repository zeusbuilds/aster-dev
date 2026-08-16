import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';

/// Exact amount editor that regenerates a Receive request only on submit.
class ReceiveAmountSheet extends ConsumerWidget {
  const ReceiveAmountSheet({super.key, required this.target});

  final WalletPaymentTarget target;

  static Future<void> show(
    BuildContext context, {
    required WalletPaymentTarget target,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.transparentSurface,
      builder: (context) => ReceiveAmountSheet(target: target),
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    ReceiveFlowViewModel notifier,
  ) async {
    final applied = await notifier.applyAmount();
    if (!context.mounted) return;
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    final failure = ref
        .read(receiveFlowViewModelProvider(target))
        .value
        ?.failure;
    if (failure != null) {
      context.toasts.show(
        title: 'Amount not applied',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = receiveFlowViewModelProvider(target);
    final flow = ref.watch(provider);
    final maxHeight =
        MediaQuery.sizeOf(context).height *
        context.metrics.sheetMaxHeightFactor;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Squircle(
          color: context.colorScheme.surface,
          border: BorderRadius.vertical(
            top: Radius.circular(context.radii.sheet),
          ),
          borderColor: context.appColors.transparentSurface,
          borderWidth: 0,
          padding: EdgeInsets.zero,
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: context.spacing.lg),
            child: flow.when(
              skipLoadingOnRefresh: false,
              data: (value) => _AmountSheetBody(
                state: value,
                onChanged: ref.read(provider.notifier).updateAmount,
                onApply: () => unawaited(
                  _apply(context, ref, ref.read(provider.notifier)),
                ),
              ),
              loading: () => const Center(
                child: GridLoader(semanticLabel: 'Loading amount editor'),
              ),
              error: (error, stackTrace) => _SheetFailure(
                failure: error is AppFailureException
                    ? error.failure
                    : FailureMapper.from(error, stackTrace),
                onRetry: ref.read(provider.notifier).retry,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AmountSheetBody extends StatelessWidget {
  const _AmountSheetBody({
    required this.state,
    required this.onChanged,
    required this.onApply,
  });

  final ReceiveFlowState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    const codec = WalletAmountInputCodec();
    final issue = switch (state.amountInput.issue) {
      WalletAmountInputIssue.malformed => 'Enter a valid decimal amount.',
      WalletAmountInputIssue.precisionExceeded =>
        'This amount has too many decimal places.',
      WalletAmountInputIssue.zero => 'Amount must be greater than zero.',
      WalletAmountInputIssue.outOfRange => 'This amount is too large.',
      WalletAmountInputIssue.empty || null => null,
    };
    final amountMessage =
        issue ??
        (!state.amountUsesSupportedGranularity
            ? 'Enter a whole-satoshi Lightning amount.'
            : null);
    final visibleMessage = amountMessage ?? state.failure?.userMessage;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.screenPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: context.spacing.md),
          SizedBox(
            width: context.metrics.sheetHandleWidth,
            height: context.metrics.sheetHandleHeight,
            child: AsterPill(
              color: context.colorScheme.surfaceContainerHigh,
              child: const SizedBox.expand(),
            ),
          ),
          SizedBox(height: context.spacing.lg),
          Text('Set amount', style: context.type.title),
          SizedBox(height: context.spacing.lg),
          Squircle(
            borderRadius: context.radii.input,
            padding: EdgeInsets.all(context.spacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: NumericText(
                    state.amountText.isEmpty ? '0' : state.amountText,
                    style: context.type.amountLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: context.spacing.md),
                Text(state.route.asset.symbol, style: context.type.title),
              ],
            ),
          ),
          if (visibleMessage case final message?) ...[
            SizedBox(height: context.spacing.sm),
            Text(
              message,
              style: context.type.errorMessage.copyWith(
                color: context.appColors.danger,
              ),
            ),
          ],
          SizedBox(height: context.spacing.lg),
          Flexible(
            child: SingleChildScrollView(
              child: AsterNumericKeypad(
                value: state.amountText,
                enabled: state.canEditAmount,
                allowDecimal:
                    codec.displayPrecision(state.route, state.bitcoinUnit) > 0,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(height: context.spacing.lg),
          CustomButton(
            text: state.amountText.isEmpty ? 'Clear amount' : 'Set amount',
            loading: state.isGenerating,
            enabled: state.canApplyAmount,
            hapticIntent: null,
            onTap: onApply,
          ),
        ],
      ),
    );
  }
}

final class _SheetFailure extends StatelessWidget {
  const _SheetFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.spacing.screenPadding),
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
