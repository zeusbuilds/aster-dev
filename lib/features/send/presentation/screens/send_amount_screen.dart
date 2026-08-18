import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
import '../../../market/presentation/models/models.dart';
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
        ref.read(bitcoinMarketViewModelProvider).value?.snapshot,
      ),
      fireImmediately: true,
    );
    ref.listenManual(
      bitcoinMarketViewModelProvider,
      (previous, next) =>
          _scheduleDeadline(ref.read(flowProvider).value, next.value?.snapshot),
      fireImmediately: true,
    );
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
    _scheduleDeadline(
      ref.read(sendFlowViewModelProvider(widget.target)).value,
      ref.read(bitcoinMarketViewModelProvider).value?.snapshot,
    );
  }

  void _scheduleDeadline(SendFlowState? state, BitcoinMarketSnapshot? market) {
    _deadlineTimer?.cancel();
    final now = ref.read(utcClockProvider)().toUtc();
    // Provider state can arrive after one of its own deadlines. Keep the
    // render clock synchronized even when there is no future timer to arm.
    _now = now;
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
    final marketPrice = switch (state.route.asset.kind) {
      WalletAssetKind.bitcoin => market?.currentBitcoinPrice,
      WalletAssetKind.usdt => market?.currentUsdtPrice,
    };
    if (marketPrice != null) deadlines.add(marketPrice.expiresAt);
    deadlines.sort();
    if (deadlines.isEmpty) return;
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
      _scheduleDeadline(state, market);
    });
  }

  Future<void> _submit(AsterNavigationCommandOwner navigation) async {
    final provider = sendFlowViewModelProvider(widget.target);
    var submitted = false;
    final accepted = await navigation.run(
      command: () async {
        submitted = await ref.read(provider.notifier).submit();
        if (!mounted || submitted) return;
        final failure = ref.read(provider).value?.failure;
        if (failure != null && failure.kind != AppFailureKind.validation) {
          context.toasts.show(
            title: 'Payment not submitted',
            message: failure.userMessage,
            variant: ToastVariant.failure,
          );
        }
      },
      failureTitle: 'Payment could not be submitted',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !submitted || !mounted) return;
    context.toasts.show(
      title: 'Payment submitted',
      message: 'The wallet accepted the payment.',
      variant: ToastVariant.success,
    );
    context.go(RoutePaths.home);
  }

  @override
  Widget build(BuildContext context) {
    final provider = sendFlowViewModelProvider(widget.target);
    final flow = ref.watch(provider);
    final market = ref.watch(bitcoinMarketViewModelProvider);
    final durableSubmissionOwnsRoute = switch (flow.value) {
      final state? =>
        state.operation == SendFlowOperation.submitting || state.result != null,
      null => false,
    };
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final submissionOwnsRoute =
              durableSubmissionOwnsRoute || navigation.inFlight;
          return PopScope(
            canPop: !submissionOwnsRoute,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              appBar: CustomAppBar(
                title: 'Send ${widget.target.assetLabel}',
                leadingIcon: true,
                leadingEnabled: !submissionOwnsRoute,
                centerTitle: false,
                fallbackLocation: RoutePaths.sendAddressFor(widget.target.slug),
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
                            onBack: () => unawaited(
                              navigation.run(
                                command: () => context.goNamed(
                                  RouteNames.sendAddress,
                                  pathParameters: {
                                    RoutePaths.paymentTargetParameter:
                                        widget.target.slug,
                                  },
                                ),
                                failureTitle: 'Recipient screen could not open',
                                hapticIntent: null,
                              ),
                            ),
                          )
                        : _AmountBody(
                            state: state,
                            now: _now,
                            market: market,
                            onAmountChanged: ref
                                .read(provider.notifier)
                                .updateAmount,
                            onRefreshBalance: () => unawaited(
                              ref.read(provider.notifier).refreshBalance(),
                            ),
                            onRefreshFee: () => unawaited(
                              ref.read(provider.notifier).refreshFee(),
                            ),
                            onRetryQuote: _marketRetryable(state, market, _now)
                                ? () => ref
                                      .read(
                                        bitcoinMarketViewModelProvider.notifier,
                                      )
                                      .retry()
                                : null,
                            onSubmit: () => unawaited(_submit(navigation)),
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
            ),
          );
        },
      ),
    );
  }

  static bool _marketRetryable(
    SendFlowState state,
    AsyncValue<BitcoinMarketState> market,
    DateTime now,
  ) {
    final presentation = market.value;
    if (presentation?.refreshing ?? false) return false;
    if (presentation?.refreshFailure case final failure?) {
      return failure.retryable;
    }
    if (market.isLoading) return false;
    if (market case AsyncError(:final error, :final stackTrace)) {
      final failure = error is AppFailureException
          ? error.failure
          : FailureMapper.from(error, stackTrace);
      return failure.retryable;
    }
    final snapshot = presentation?.snapshot;
    if (snapshot == null || snapshot.quoteCurrency.code != state.currencyCode) {
      return true;
    }
    final price = switch (state.route.asset.kind) {
      WalletAssetKind.bitcoin => snapshot.currentBitcoinPrice,
      WalletAssetKind.usdt => snapshot.currentUsdtPrice,
    };
    return !(price?.isCurrentAt(now) ?? false);
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
  final AsyncValue<BitcoinMarketState> market;
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
    final preview = state.preview!;
    final fiatText = _fiatText(state, market, now);
    final inputMessage = _amountMessage(state, now);
    final fee = state.feeEstimate;
    final feeStale = fee?.isStaleAt(now) ?? false;
    final balanceFailure = state.failureFor(
      SendFlowOperation.refreshingBalance,
    );
    final submissionFailure = state.failureFor(SendFlowOperation.submitting);
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
                  announceValidation:
                      submissionFailure != null || state.isExpiredAt(now),
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
                        AsterStatusMessage(
                          state.feeFailure?.userMessage ??
                              'Refresh the network fee before sending.',
                          tone: AsterStatusTone.warning,
                          announce: true,
                        ),
                        if (state.feeFailure?.retryable != false) ...[
                          SizedBox(height: context.spacing.sm),
                          CustomButton.compact(
                            text: 'Refresh fee',
                            loading:
                                state.operation ==
                                SendFlowOperation.refreshingFee,
                            enabled: state.canRefreshFee,
                            hapticIntent: null,
                            onTap: onRefreshFee,
                          ),
                        ],
                      ],
                      if (onRetryQuote case final retry?) ...[
                        SizedBox(height: context.spacing.sm),
                        CustomButton.compact(
                          text: 'Retry fiat quote',
                          enabled: state.canEditPayment,
                          hapticIntent: null,
                          onTap: retry,
                        ),
                      ],
                      SizedBox(height: context.spacing.sm),
                      if (balanceFailure case final failure?) ...[
                        AsterStatusMessage(
                          failure.userMessage,
                          tone: AsterStatusTone.danger,
                          announce: true,
                        ),
                        SizedBox(height: context.spacing.sm),
                      ],
                      CustomButton.compact(
                        text: 'Refresh balance',
                        loading:
                            state.operation ==
                            SendFlowOperation.refreshingBalance,
                        enabled: state.canStart(
                          SendFlowOperation.refreshingBalance,
                        ),
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
                        preview.displayDestination,
                        style: context.type.addressSmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (preview.recipientLabel case final label?) ...[
                        SizedBox(height: context.spacing.md),
                        Text('Payment label', style: context.type.sectionLabel),
                        SizedBox(height: context.spacing.xs),
                        Text(label, style: context.type.statusMessage),
                      ],
                      if (preview.message case final message?) ...[
                        SizedBox(height: context.spacing.md),
                        Text('Message', style: context.type.sectionLabel),
                        SizedBox(height: context.spacing.xs),
                        Text(message, style: context.type.statusMessage),
                      ],
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
          enabled: state.canChangeAmount && !state.amountIsLocked,
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
    AsyncValue<BitcoinMarketState> market,
    DateTime now,
  ) {
    final units = state.amountInput.units;
    if (market.isLoading) {
      return '${state.currencyCode} quote loading';
    }
    final snapshot = market.value?.snapshot;
    if (snapshot == null || snapshot.quoteCurrency.code != state.currencyCode) {
      return '${state.currencyCode} quote unavailable';
    }
    final price = switch (state.route.asset.kind) {
      WalletAssetKind.bitcoin => snapshot.currentBitcoinPrice,
      WalletAssetKind.usdt => snapshot.currentUsdtPrice,
    };
    if (!(price?.isCurrentAt(now) ?? false)) {
      return '${state.currencyCode} quote unavailable';
    }
    if (units == null) {
      return WalletFiatEstimate.formatMinorUnits(
        minorUnits: 0,
        symbol: snapshot.quoteCurrency.symbol,
        code: snapshot.quoteCurrency.code,
        minorUnitDigits: snapshot.quoteCurrency.minorUnitDigits,
      );
    }
    final minorUnits = WalletFiatEstimate.minorUnits(
      units: units,
      route: state.route,
      assetPriceMinorUnits: price?.minorUnits,
    );
    if (minorUnits == null) {
      return '${state.currencyCode} quote unavailable';
    }
    final value = WalletFiatEstimate.formatMinorUnits(
      minorUnits: minorUnits,
      symbol: snapshot.quoteCurrency.symbol,
      code: snapshot.quoteCurrency.code,
      minorUnitDigits: snapshot.quoteCurrency.minorUnitDigits,
    );
    return '≈ $value';
  }

  static String? _amountMessage(SendFlowState state, DateTime now) {
    if (state.failureFor(SendFlowOperation.submitting) case final failure?) {
      return failure.userMessage;
    }
    if (state.isExpiredAt(now)) {
      return 'This payment request has expired.';
    }
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
    if (!state.amountUsesSupportedGranularity) {
      return 'Enter a whole-satoshi Lightning amount.';
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
            style: context.type.statusMessage,
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
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading payment amount',
      excludeSemantics: true,
      child: Column(
        children: [
          SendCard.loading(target: target),
          const Spacer(),
          const AsterNumericKeypad.loading(),
          SizedBox(height: context.spacing.md),
          const CustomButton(text: 'Send'),
        ],
      ),
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
