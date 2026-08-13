import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
import '../../../market/presentation/view_model/view_models.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Final Send step: enter an exact amount and submit from the current screen.
class SendAmountScreen extends ConsumerStatefulWidget {
  const SendAmountScreen({super.key, required this.target});

  final WalletPaymentTarget target;

  @override
  ConsumerState<SendAmountScreen> createState() => _SendAmountScreenState();
}

class _SendAmountScreenState extends ConsumerState<SendAmountScreen>
    with WidgetsBindingObserver {
  Timer? _deadlineTimer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = ref.read(utcClockProvider)();
    WidgetsBinding.instance.addObserver(this);
    final flowProvider = sendFlowViewModelProvider(widget.target);
    ref.listenManual(
      flowProvider,
      (previous, next) => _scheduleDeadline(
        next.value,
        widget.target.assetKind == WalletAssetKind.bitcoin
            ? ref.read(bitcoinMarketViewModelProvider).value
            : null,
      ),
      fireImmediately: true,
    );
    if (widget.target.assetKind == WalletAssetKind.bitcoin) {
      ref.listenManual(
        bitcoinMarketViewModelProvider,
        (previous, next) =>
            _scheduleDeadline(ref.read(flowProvider).value, next.value),
        fireImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadlineTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setState(() => _now = ref.read(utcClockProvider)());
  }

  void _scheduleDeadline(SendFlowState? state, BitcoinMarketSnapshot? market) {
    _deadlineTimer?.cancel();
    if (state == null) return;
    final deadlines = <DateTime>[];
    final expiry = state.preview?.expiresAt;
    if (expiry != null) {
      deadlines.add(expiry);
    }
    final fee = state.feeEstimate;
    if (fee != null) {
      deadlines.add(fee.observedAt.add(WalletFeeRateEstimate.maximumAge));
    }
    if (market != null) deadlines.add(market.expiresAt);
    deadlines.sort();
    if (deadlines.isEmpty) return;
    final now = ref.read(utcClockProvider)();
    DateTime? nextDeadline;
    for (final deadline in deadlines) {
      if (deadline.isAfter(now)) {
        nextDeadline = deadline;
        break;
      }
    }
    if (nextDeadline == null) return;
    final delay = nextDeadline.difference(now);
    _deadlineTimer = Timer(delay + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(() => _now = ref.read(utcClockProvider)());
    });
  }

  Future<void> _submit() async {
    final provider = sendFlowViewModelProvider(widget.target);
    final submitted = await ref.read(provider.notifier).submit();
    if (!mounted) return;
    if (submitted) {
      context.toasts.show(
        title: 'Payment submitted',
        message: 'The wallet accepted the payment.',
        variant: ToastVariant.success,
      );
      context.go(RoutePaths.skeleton);
      return;
    }
    final failure = ref.read(provider).value?.failure;
    if (failure != null && failure.kind != AppFailureKind.validation) {
      context.toasts.show(
        title: 'Payment not submitted',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = sendFlowViewModelProvider(widget.target);
    final flow = ref.watch(provider);
    final market = widget.target.assetKind == WalletAssetKind.bitcoin
        ? ref.watch(bitcoinMarketViewModelProvider)
        : null;
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Send ${widget.target.assetLabel}',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: context.spacing.lg),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.screenPadding,
          ),
          child: flow.when(
            skipLoadingOnRefresh: false,
            data: (state) => state.preview == null
                ? _MissingDestination(
                    target: widget.target,
                    onBack: () => context.goNamed(
                      RouteNames.sendAddress,
                      pathParameters: {
                        RoutePaths.paymentTargetParameter: widget.target.slug,
                      },
                    ),
                  )
                : _AmountBody(
                    state: state,
                    now: _now,
                    market: market,
                    onAmountChanged: ref.read(provider.notifier).updateAmount,
                    onRefreshBalance: () =>
                        unawaited(ref.read(provider.notifier).refreshBalance()),
                    onRefreshFee: () =>
                        unawaited(ref.read(provider.notifier).refreshFee()),
                    onRetryQuote: market?.hasError ?? false
                        ? () => ref
                              .read(bitcoinMarketViewModelProvider.notifier)
                              .retry()
                        : null,
                    onSubmit: () => unawaited(_submit()),
                  ),
            loading: () => _AmountLoading(target: widget.target),
            error: (error, stackTrace) => _AmountFailure(
              failure: error is AppFailureException
                  ? error.failure
                  : FailureMapper.from(error, stackTrace),
              onRetry: ref.read(provider.notifier).retry,
            ),
          ),
        ),
      ),
    );
  }
}

final class _AmountBody extends StatelessWidget {
  _AmountBody({
    required this.state,
    required this.now,
    required this.market,
    required this.onAmountChanged,
    required this.onRefreshBalance,
    required this.onRefreshFee,
    required this.onRetryQuote,
    required this.onSubmit,
  });

  final SendFlowState state;
  final DateTime now;
  final AsyncValue<BitcoinMarketSnapshot>? market;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRefreshBalance;
  final VoidCallback onRefreshFee;
  final VoidCallback? onRetryQuote;
  final VoidCallback onSubmit;
  final WalletAmountDisplayFormatter _amountFormatter =
      WalletAmountDisplayFormatter();

  @override
  Widget build(BuildContext context) {
    const inputCodec = WalletAmountInputCodec();
    final available = _amountFormatter.format(
      units: state.availableUnits,
      route: state.route,
      bitcoinUnit: state.bitcoinUnit,
    );
    final fiatText = _fiatText(state, market, now);
    final inputMessage = _amountMessage(state);
    final fee = state.feeEstimate;
    final feeStale = fee?.isStaleAt(now) ?? false;
    final submitting = state.operation == SendFlowOperation.submitting;
    final canSubmit = state.canSubmitAt(now);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                SendCard(
                  route: state.route,
                  amountText: state.amountText,
                  available: available,
                  fiatText: fiatText,
                  amountLocked: state.amountIsLocked,
                  validationMessage: inputMessage,
                ),
                SizedBox(height: context.spacing.md),
                Squircle(
                  borderRadius: context.radii.input,
                  padding: EdgeInsets.all(context.spacing.lg),
                  child: Column(
                    children: [
                      DetailRow(
                        title: state.route.rail == PaymentRail.onchain
                            ? 'Network fee rate'
                            : 'Payment rail',
                        value: state.route.rail == PaymentRail.onchain
                            ? fee == null
                                  ? 'Unavailable'
                                  : '${fee.satsPerVbyte} sats/vbyte'
                            : 'Lightning',
                      ),
                      if (feeStale || state.feeFailure != null) ...[
                        SizedBox(height: context.spacing.sm),
                        Text(
                          state.feeFailure?.userMessage ??
                              'Refresh the network fee before sending.',
                          style: context.type.errorMessage.copyWith(
                            color: context.appColors.warning,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.spacing.sm),
                        CustomButton.compact(
                          text: 'Refresh fee',
                          loading:
                              state.operation ==
                              SendFlowOperation.refreshingFee,
                          enabled: !state.isBusy,
                          hapticIntent: null,
                          onTap: onRefreshFee,
                        ),
                      ],
                      if (onRetryQuote case final retry?) ...[
                        SizedBox(height: context.spacing.sm),
                        CustomButton.compact(
                          text: 'Retry USD quote',
                          hapticIntent: null,
                          onTap: retry,
                        ),
                      ],
                      SizedBox(height: context.spacing.sm),
                      CustomButton.compact(
                        text: 'Refresh balance',
                        loading:
                            state.operation ==
                            SendFlowOperation.refreshingBalance,
                        enabled: !state.isBusy,
                        hapticIntent: null,
                        onTap: onRefreshBalance,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.spacing.md),
                Squircle(
                  borderRadius: context.radii.input,
                  padding: EdgeInsets.all(context.spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recipient', style: context.type.sectionLabel),
                      SizedBox(height: context.spacing.xs),
                      Text(
                        state.preview!.displayDestination,
                        style: context.type.addressSmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.spacing.md),
        AsterNumericKeypad(
          value: state.amountText,
          enabled: !state.isBusy && !state.amountIsLocked,
          allowDecimal:
              inputCodec.displayPrecision(state.route, state.bitcoinUnit) > 0,
          onChanged: onAmountChanged,
        ),
        SizedBox(height: context.spacing.md),
        CustomButton(
          text: 'Send',
          loading: submitting,
          enabled: canSubmit,
          hapticIntent: null,
          onTap: onSubmit,
        ),
      ],
    );
  }

  String _fiatText(
    SendFlowState state,
    AsyncValue<BitcoinMarketSnapshot>? market,
    DateTime now,
  ) {
    if (state.currencyCode != 'USD') {
      return '${state.currencyCode} quote unavailable';
    }
    final units = state.amountInput.units;
    if (units == null) return '\$0.00';
    final snapshot = market?.value;
    final price =
        state.route.asset.kind == WalletAssetKind.bitcoin &&
            (snapshot?.isCurrentAt(now) ?? false)
        ? snapshot!.currentUsdCents
        : null;
    final cents = WalletUsdEstimate.cents(
      units: units,
      route: state.route,
      bitcoinPriceCents: price,
    );
    if (cents == null) return 'USD quote unavailable';
    final value = WalletUsdEstimate.formatCents(cents);
    return state.route.asset.kind == WalletAssetKind.usdt
        ? '$value face value'
        : '≈ $value';
  }

  static String? _amountMessage(SendFlowState state) {
    if (state.failure case final failure?) return failure.userMessage;
    if (!state.amountInput.isValid) {
      return switch (state.amountInput.issue) {
        WalletAmountInputIssue.empty => null,
        WalletAmountInputIssue.malformed => 'Enter a valid decimal amount.',
        WalletAmountInputIssue.precisionExceeded =>
          'This amount has too many decimal places.',
        WalletAmountInputIssue.zero => 'Amount must be greater than zero.',
        WalletAmountInputIssue.outOfRange => 'This amount is too large.',
        null => null,
      };
    }
    if (!state.hasSufficientBalance) {
      return 'The available balance is too low for this amount.';
    }
    return null;
  }
}

final class _MissingDestination extends StatelessWidget {
  const _MissingDestination({required this.target, required this.onBack});

  final WalletPaymentTarget target;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter and validate a recipient before choosing an amount.',
            style: context.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: context.spacing.lg),
          CustomButton(text: 'Enter recipient', onTap: onBack),
        ],
      ),
    );
  }
}

final class _AmountLoading extends StatelessWidget {
  const _AmountLoading({required this.target});

  final WalletPaymentTarget target;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SendCard.loading(target: target),
        const Spacer(),
        const AsterNumericKeypad.loading(),
        SizedBox(height: context.spacing.md),
        const CustomButton(text: 'Send'),
      ],
    );
  }
}

final class _AmountFailure extends StatelessWidget {
  const _AmountFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            failure.userMessage,
            style: context.textTheme.bodyMedium,
            textAlign: TextAlign.center,
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
