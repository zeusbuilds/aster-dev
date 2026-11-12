import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
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
    // Modal routes can be inserted above the caller's feature scope. Reuse
    // the underlying feedback services, then capture the sheet's own route
    // origin at the action; an origin bound to the covered parent would drop
    // genuine sheet failures.
    final feedback = AsterFeedbackScope.maybeOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: context.appColors.transparentSurface,
      builder: (context) {
        final sheet = ReceiveAmountSheet(target: target);
        return feedback == null
            ? sheet
            : AsterFeedbackScope(
                haptics: feedback.haptics,
                toasts: feedback.toasts,
                child: sheet,
              );
      },
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    ReceiveFlowViewModel notifier,
    AsterNavigationCommandOwner navigation,
  ) async {
    final toasts = context.toasts;
    final route = ModalRoute.of(context);
    final flow = ref.read(receiveFlowViewModelProvider(target));
    final current = flow.value;
    if (current == null || flow.hasError || flow.isLoading) return;
    final validationMessage = _amountValidationMessage(current);
    if (validationMessage != null) {
      toasts.show(
        title: 'Check amount',
        message: validationMessage,
        variant: ToastVariant.warning,
      );
      return;
    }
    var applied = false;
    final accepted = await navigation.run(
      command: () async {
        applied = await notifier.applyAmount();
        if (!context.mounted || route?.isCurrent != true || applied) return;
        final failure = ref
            .read(receiveFlowViewModelProvider(target))
            .value
            ?.failure;
        if (failure != null) {
          toasts.show(
            title: 'Amount not applied',
            message: failure.userMessage,
            variant: ToastVariant.failure,
          );
        }
      },
      failureTitle: 'Amount could not be applied',
      hapticIntent: null,
    );
    // Generating a receive request does not send funds. The editor may close
    // while it completes; its parent still owns the resulting request. Never
    // let a late result pop that parent or a subsequently opened editor.
    if (!accepted || !applied || !context.mounted || route?.isCurrent != true) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _close(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = receiveFlowViewModelProvider(target);
    final flow = ref.watch(provider);
    final state = flow.value;
    if (state == null || flow.hasError) {
      // The request screen owns recovery. Only dismiss this sheet if it is
      // still the current modal, so a late update cannot pop another route.
      if (ModalRoute.of(context) is PopupRoute) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final latest = ref.read(provider);
          if (!latest.hasValue || latest.hasError) _close(context);
        });
      }
      return const SizedBox.shrink();
    }
    final viewport = MediaQuery.sizeOf(context);
    final maxHeight = viewport.height * context.metrics.sheetMaxHeightFactor;
    final isDuoCover =
        ref.watch(duoCoverLayoutProvider).value?.appliesTo(viewport) == true;
    final scrollsToBottom = isDuoCover || context.isOpenDuoLandscape;
    final scrollBottomPadding = scrollsToBottom
        ? context.windowInsets.bottomSafe + context.spacing.lg
        : null;

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
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
                child: AsterSheetSafeArea(
                  bottom: !scrollsToBottom,
                  minimum: scrollsToBottom
                      ? EdgeInsets.zero
                      : EdgeInsets.only(bottom: context.spacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AsterSheetHeader(
                        title: 'Set amount',
                        closeLabel: 'Close amount editor',
                        onClose: () => _close(context),
                      ),
                      Flexible(
                        child: _AmountSheetBody(
                          state: state,
                          bottomPadding: scrollBottomPadding ?? 0,
                          commandsEnabled:
                              !navigation.inFlight && !flow.isLoading,
                          onChanged: ref.read(provider.notifier).updateAmount,
                          onApply: () => unawaited(
                            _apply(
                              context,
                              ref,
                              ref.read(provider.notifier),
                              navigation,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _AmountSheetBody extends StatelessWidget {
  const _AmountSheetBody({
    required this.state,
    required this.bottomPadding,
    required this.commandsEnabled,
    required this.onChanged,
    required this.onApply,
  });

  final ReceiveFlowState state;
  final double bottomPadding;
  final bool commandsEnabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    const codec = WalletAmountInputCodec();
    final submitLabel = state.request == null
        ? 'Create request'
        : state.amountText.isEmpty && !state.amountRequired
        ? 'Clear amount'
        : 'Set amount';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.spacing.screenPadding,
        0,
        context.spacing.screenPadding,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: context.spacing.xs),
          Squircle(
            borderRadius: context.radii.card,
            padding: EdgeInsets.all(context.spacing.lg),
            child: WalletAmountEntry(
              value: state.amountText,
              unit: state.route.asset.kind == WalletAssetKind.bitcoin
                  ? state.bitcoinUnit.label
                  : state.route.asset.symbol,
              assetKind: state.route.asset.kind,
            ),
          ),
          SizedBox(height: context.spacing.lg),
          AsterNumericKeypad(
            value: state.amountText,
            enabled: commandsEnabled && state.canEditAmount,
            allowDecimal:
                codec.displayPrecision(state.route, state.bitcoinUnit) > 0,
            onChanged: onChanged,
          ),
          SizedBox(height: context.spacing.lg),
          CustomButton(
            text: submitLabel,
            loading: state.isGenerating,
            enabled:
                commandsEnabled &&
                state.canGenerateRequest &&
                state.canEditAmount &&
                (state.hasPendingAmountChange ||
                    _amountValidationMessage(state) != null),
            hapticIntent: null,
            onTap: onApply,
          ),
        ],
      ),
    );
  }
}

String? _amountValidationMessage(ReceiveFlowState state) {
  if (state.amountText.isEmpty && state.amountRequired) {
    return 'Enter an amount.';
  }
  final issue = switch (state.amountInput.issue) {
    WalletAmountInputIssue.malformed => 'Enter a valid decimal amount.',
    WalletAmountInputIssue.precisionExceeded =>
      'This amount has too many decimal places.',
    WalletAmountInputIssue.zero => 'Amount must be greater than zero.',
    WalletAmountInputIssue.outOfRange => 'This amount is too large.',
    WalletAmountInputIssue.empty || null => null,
  };
  if (issue != null) return issue;
  return state.amountUsesSupportedGranularity
      ? null
      : 'Enter a whole-satoshi Lightning amount.';
}
