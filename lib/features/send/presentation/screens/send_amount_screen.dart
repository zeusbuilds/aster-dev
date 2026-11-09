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
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';
import '../view_model/rgb_send_preparation.dart';
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
  Timer? _minimumSubmitTimer;
  Completer<void>? _minimumSubmitDelay;
  late DateTime _now;
  var _hasDependencies = false;
  var _presentingSubmission = false;
  var _feedbackScheduled = false;
  var _recipientRedirectScheduled = false;
  final _announcedFailures = <(String, String, DateTime?)>{};
  static const _minimumSubmitLoadingDuration = Duration(seconds: 2);

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasDependencies = true;
    ModalRoute.isCurrentOf(context);
    TickerMode.valuesOf(context);
    _schedulePresentationFeedback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadlineTimer?.cancel();
    _minimumSubmitTimer?.cancel();
    final minimumSubmitDelay = _minimumSubmitDelay;
    if (minimumSubmitDelay != null && !minimumSubmitDelay.isCompleted) {
      minimumSubmitDelay.complete();
    }
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
    _schedulePresentationFeedback();
    if (state == null || state.result != null) return;
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

  bool get _canPresentFeedback =>
      mounted &&
      _hasDependencies &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      !ref.read(walletLifecycleViewModelProvider).blocksInteraction;

  void _schedulePresentationFeedback() {
    if (!mounted || !_hasDependencies || _feedbackScheduled) return;
    _feedbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedbackScheduled = false;
      if (!_canPresentFeedback || _presentingSubmission) return;
      final state = ref.read(sendFlowViewModelProvider(widget.target)).value;
      if (state == null || state.result != null) return;
      if (!state.requiresReconciliation &&
          state.isExpiredAt(ref.read(utcClockProvider)())) {
        _showFailureFeedback(
          const AppFailure(
            code: 'payment_request_expired',
            kind: AppFailureKind.validation,
            userMessage:
                'This invoice has expired. Enter a new invoice to continue.',
            retryable: false,
          ),
        );
      }
    });
  }

  void _showFailureFeedback(
    AppFailure failure, {
    SendFlowOperation? readOperation,
    bool userInitiated = false,
    ToastPresentationService? toasts,
  }) {
    if (!_canPresentFeedback) return;
    final preview = ref
        .read(sendFlowViewModelProvider(widget.target))
        .value
        ?.preview;
    final key = (
      failure.code,
      failure.userMessage,
      failure.code == 'payment_request_expired' ? preview?.expiresAt : null,
    );
    if (!_announcedFailures.add(key) && !userInitiated) return;
    final feedback = SendFailureFeedback.fromFailure(
      failure,
      readOperation: readOperation,
    );
    (toasts ?? context.toasts).show(
      title: feedback.title,
      message: feedback.message,
      variant: feedback.variant,
    );
  }

  Future<void> _submit(AsterNavigationCommandOwner navigation) async {
    final toasts = context.toasts;
    final provider = sendFlowViewModelProvider(widget.target);
    await navigation.run(
      command: () async {
        setState(() => _presentingSubmission = true);
        final minimumDelay = Completer<void>();
        _minimumSubmitDelay = minimumDelay;
        _minimumSubmitTimer = Timer(
          _minimumSubmitLoadingDuration,
          minimumDelay.complete,
        );
        try {
          // Submit immediately. Only the accepted receipt's presentation waits
          // for the minimum interval; slower payments incur no extra delay.
          final submitted = await ref
              .read(provider.notifier)
              .submit(
                confirmRgbSetup: _confirmRgbSetup,
                onRgbSetupResult: (result) {
                  if (!_canPresentFeedback) return;
                  final (title, message) = switch (result) {
                    RgbSendPreparationResult.prepared => (
                      'Wallet prepared',
                      'Tap Send again to continue.',
                    ),
                    RgbSendPreparationResult.pending => (
                      'Preparation pending',
                      'Wait for the Bitcoin transaction to confirm, then tap Send.',
                    ),
                    _ => (
                      'Preparation needs checking',
                      'Tap Send to check its status. Preparation will not be repeated.',
                    ),
                  };
                  toasts.show(
                    title: title,
                    message: message,
                    variant: ToastVariant.warning,
                  );
                },
              );
          if (submitted) await minimumDelay.future;
          if (!mounted || submitted) return;
          final state = ref.read(provider).value;
          final failure = state?.failure ?? state?.feeFailure;
          if (failure != null) {
            _showFailureFeedback(
              failure,
              readOperation: state?.feeFailure != null
                  ? SendFlowOperation.refreshingFee
                  : null,
              userInitiated: true,
              toasts: toasts,
            );
          }
        } finally {
          _minimumSubmitTimer?.cancel();
          _minimumSubmitTimer = null;
          _minimumSubmitDelay = null;
          if (!minimumDelay.isCompleted) minimumDelay.complete();
          if (mounted) setState(() => _presentingSubmission = false);
        }
      },
      failureTitle: 'Payment could not be submitted',
      hapticIntent: null,
      blocksRoutePop: true,
    );
  }

  Future<bool> _confirmRgbSetup(RgbWalletSetupReview review) async {
    if (!_canPresentFeedback) return false;
    final sats = BitcoinAmountFormatter(
      unit: BitcoinUnit.sats,
      locale: 'en_US',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsterConfirmationDialog(
        title: 'Prepare wallet for USDT?',
        content: Text(
          'Create ${RgbWalletSetupReview.outputCount} wallet outputs of '
          '${sats.format(RgbWalletSetupReview.outputValueSats)} each '
          '(${sats.format(RgbWalletSetupReview.outputCount * RgbWalletSetupReview.outputValueSats)} total). This moves BTC '
          'within your wallet. A Bitcoin network fee also applies at '
          '${review.feeRateSatPerVbyte} sat/vB; a total fee cap is unavailable. '
          'Your USDT payment will not be sent.',
        ),
        confirmText: 'Prepare',
      ),
    );
    return mounted && confirmed == true;
  }

  Widget _missingRecipient() {
    if (!_recipientRedirectScheduled) {
      _recipientRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recipientRedirectScheduled = false;
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        final state = ref.read(sendFlowViewModelProvider(widget.target)).value;
        if (state == null || state.preview != null || state.result != null) {
          return;
        }
        // The router rejects direct amount links without a validated recipient.
        // Also return safely if a retained flow loses its preview on this route.
        GoRouter.maybeOf(context)?.goNamed(
          RouteNames.sendAddress,
          pathParameters: {
            RoutePaths.paymentTargetParameter: widget.target.slug,
          },
        );
      });
    }
    return _AmountLoading(target: widget.target);
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
          if (flow case AsyncData<SendFlowState>(:final value)
              when value.result != null && !_presentingSubmission) {
            return PopScope(
              canPop: false,
              child: Scaffold(
                backgroundColor: context.colorScheme.surface,
                body: SendSuccessView(
                  result: value.result!,
                  bitcoinUnit: value.bitcoinUnit,
                  continuing: navigation.inFlight,
                  onContinue: () => unawaited(
                    navigation.run(
                      command: () => context.go(RoutePaths.home),
                      failureTitle: 'Home could not open',
                      hapticIntent: null,
                    ),
                  ),
                ),
              ),
            );
          }
          final submissionOwnsRoute =
              durableSubmissionOwnsRoute || navigation.inFlight;
          return PopScope(
            canPop: !submissionOwnsRoute,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              appBar: CustomAppBar(
                title: widget.target.sendTitle,
                leadingIcon: true,
                leadingEnabled: !submissionOwnsRoute,
                centerTitle: false,
                fallbackLocation: RoutePaths.sendAddressFor(widget.target.slug),
              ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.screenPadding,
                  ),
                  child: flow.when(
                    skipLoadingOnRefresh: false,
                    data: (state) => state.preview == null
                        ? _missingRecipient()
                        : _AmountBody(
                            state: state,
                            now: _now,
                            market: market,
                            presentingSubmission: _presentingSubmission,
                            onAmountChanged: ref
                                .read(provider.notifier)
                                .updateAmount,
                            onMax: ref.read(provider.notifier).useMaxAmount,
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
}

final class _AmountBody extends StatelessWidget {
  _AmountBody({
    required this.state,
    required this.now,
    required this.market,
    required this.presentingSubmission,
    required this.onAmountChanged,
    required this.onMax,
    required this.onSubmit,
  });

  final SendFlowState state;
  final DateTime now;
  final AsyncValue<BitcoinMarketState> market;
  final bool presentingSubmission;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onMax;
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
    final fee = state.feeEstimate;
    final submitting =
        presentingSubmission || state.operation == SendFlowOperation.submitting;
    final canSubmit = !presentingSubmission && state.canAttemptSubmitAt(now);

    return AsterFormBody(
      bottomPadding: context.windowInsets.bottomSystem + context.spacing.lg,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendCard(
            route: state.route,
            amountText: state.amountText,
            available: available,
            fiatText: fiatText,
            amountLocked: state.amountIsLocked,
            onMax:
                !presentingSubmission &&
                    state.canChangeAmount &&
                    !state.amountIsLocked &&
                    state.availableUnits > 0
                ? onMax
                : null,
          ),
          SizedBox(height: context.spacing.md),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.xl,
              vertical: context.spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailRow(
                  title: state.route.rail == PaymentRail.onchain
                      ? switch (fee?.source) {
                          WalletFeeRateSource.localRegtestPolicy =>
                            'Local test fee rate',
                          WalletFeeRateSource.devSignetPolicy =>
                            'Dev Signet fee rate',
                          _ => 'Network fee rate',
                        }
                      : 'Payment rail',
                  value: state.route.rail == PaymentRail.onchain
                      ? fee == null || fee.isStaleAt(now)
                            ? 'Unavailable'
                            : '${fee.satsPerVbyte} sats/vbyte'
                      : 'Lightning',
                ),
                SizedBox(height: context.spacing.sm),
                Semantics(
                  label: 'Address, ${preview.displayDestination}',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Address', style: context.type.rowMeta),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: SizedBox(width: context.spacing.lg),
                        ),
                        ...NumericTextSpans.build(
                          context,
                          // Display-only break opportunities keep long identifiers
                          // beside the label. Semantics and payment state retain
                          // the unmodified destination.
                          preview.displayDestination.characters.join('\u200B'),
                          context.type.rowValue,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
                if (preview.witnessBitcoinAmountSats != null) ...[
                  SizedBox(height: context.spacing.sm),
                  const DetailRow(
                    title: 'Recipient Bitcoin output',
                    value: '1,000 sats',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.xxl),
          child: AsterNumericKeypad(
            value: state.amountText,
            enabled: state.canChangeAmount && !state.amountIsLocked,
            allowDecimal:
                inputCodec.displayPrecision(state.route, state.bitcoinUnit) > 0,
            onChanged: onAmountChanged,
          ),
        ),
        SizedBox(height: context.spacing.xxxl),
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
      return '—';
    }
    final snapshot = market.value?.snapshot;
    if (snapshot == null || snapshot.quoteCurrency.code != state.currencyCode) {
      return '—';
    }
    final price = switch (state.route.asset.kind) {
      WalletAssetKind.bitcoin => snapshot.currentBitcoinPrice,
      WalletAssetKind.usdt => snapshot.currentUsdtPrice,
    };
    if (!(price?.isCurrentAt(now) ?? false)) {
      return '—';
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
      return '—';
    }
    final value = WalletFiatEstimate.formatMinorUnits(
      minorUnits: minorUnits,
      symbol: snapshot.quoteCurrency.symbol,
      code: snapshot.quoteCurrency.code,
      minorUnitDigits: snapshot.quoteCurrency.minorUnitDigits,
    );
    return '≈ $value';
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
      child: AsterFormBody(
        bottomPadding: context.windowInsets.bottomSystem + context.spacing.lg,
        content: SendCard.loading(target: target),
        actions: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.xxl),
            child: const AsterNumericKeypad.loading(),
          ),
          SizedBox(height: context.spacing.xxxl),
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
    return AsterFormBody(
      bottomPadding: context.windowInsets.bottomSystem + context.spacing.lg,
      actions: const [],
      content: Column(
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
