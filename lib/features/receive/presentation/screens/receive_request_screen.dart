import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Displays one real generated address or invoice for the selected route.
class ReceiveRequestScreen extends ConsumerStatefulWidget {
  const ReceiveRequestScreen({super.key, required this.target});

  final WalletPaymentTarget target;

  @override
  ConsumerState<ReceiveRequestScreen> createState() =>
      _ReceiveRequestScreenState();
}

class _ReceiveRequestScreenState extends ConsumerState<ReceiveRequestScreen>
    with WidgetsBindingObserver {
  Timer? _expiryTimer;
  late DateTime _now;
  late ProviderSubscription<AsyncValue<ReceiveFlowState>> _requestSubscription;
  bool _setupCommandActive = false;
  String? _preparationStateCode;

  bool get _requestActionInProgress {
    final flow = ref.read(receiveFlowViewModelProvider(widget.target));
    return _setupCommandActive ||
        flow.isLoading ||
        (flow.value?.isBusy ?? false);
  }

  Future<void> _changeRgbMode(RgbReceiveMode mode) async {
    if (_requestActionInProgress) return;
    setState(() => _setupCommandActive = true);
    try {
      if (mode == RgbReceiveMode.blind) {
        var decisionMade = false;
        final approved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Use blind receive?'),
            content: const Text(
              'Uses prepared Bitcoin outputs. Preparing more outputs costs a Bitcoin network fee.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (decisionMade) return;
                  decisionMade = true;
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (decisionMade) return;
                  decisionMade = true;
                  Navigator.pop(context, true);
                },
                child: const Text('Use blind receive'),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return;
      }
      if (!mounted) return;
      final toasts = context.toasts;
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .setRgbReceiveMode(mode);
      if (mounted) {
        _showCurrentFailure(
          toasts,
          'Could not change receive mode',
          skipExpectedSetup: true,
        );
      }
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _prepareRgbSetup() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    setState(() => _setupCommandActive = true);
    final notifier = ref.read(
      receiveFlowViewModelProvider(widget.target).notifier,
    );
    RgbWalletSetupReview? review;
    var submitted = false;
    try {
      final result = await notifier.prepareRgbSetup();
      if (result case AppSuccess<RgbWalletSetupReview>(:final value)) {
        review = value;
      }
      if (result case AppFailureResult<RgbWalletSetupReview>(:final failure)) {
        if (mounted) {
          _showReceiveFailure(toasts, 'Could not prepare wallet', failure);
        }
      }
      if (review == null || !mounted) return;
      final current = review;
      var decisionMade = false;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Prepare RGB wallet?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SetupReviewRow(
                  label: 'Outputs',
                  value:
                      'Up to ${RgbWalletSetupReview.outputCount} × '
                      '${RgbWalletSetupReview.outputValueSats} sat',
                ),
                _SetupReviewRow(
                  label: 'Fee rate',
                  value: '${current.feeRateSatPerVbyte} sat/vB',
                ),
                _SetupReviewRow(
                  label: 'Fee source',
                  value:
                      current.feeSource ==
                          WalletFeeRateSource.localRegtestPolicy
                      ? 'Local test fee rate'
                      : 'Network fee rate',
                ),
                _SetupReviewRow(
                  label: 'Expires',
                  value: DateFormat.jm(
                    Localizations.localeOf(context).toString(),
                  ).format(current.expiresAt.toLocal()),
                ),
                SizedBox(height: context.spacing.md),
                const Text(
                  'Outputs stay in your wallet. Only the network fee is spent. The actual output count may be lower.',
                ),
                SizedBox(height: context.spacing.sm),
                const Text(
                  'The final fee is unknown. No total fee cap applies.',
                ),
                SizedBox(height: context.spacing.sm),
                const Text('USDT receipt is available after confirmation.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (decisionMade) return;
                decisionMade = true;
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (decisionMade) return;
                decisionMade = true;
                Navigator.pop(context, true);
              },
              child: const Text('Confirm setup'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      submitted = true;
      _preparationStateCode = 'rgb_wallet_setup_pending';
      final confirmationToasts = context.toasts;
      await notifier.confirmRgbSetup(current);
      if (!mounted) return;
      final failure = _currentFailure();
      if (failure?.code == 'rgb_wallet_setup_review_changed') {
        // The same rejection code also covers a changed or already-dispatched
        // journal. Inspect its authoritative preparation phase once; never
        // infer permission to prepare again from wording or elapsed time.
        await notifier.checkRgbSetup();
        if (!mounted) return;
        if (_currentFailure()?.code == 'rgb_wallet_setup_required') {
          confirmationToasts.show(
            title: 'Review changed',
            message: 'Review the fee and confirm again.',
            variant: ToastVariant.warning,
          );
        } else {
          _showCurrentFailure(
            confirmationToasts,
            'Could not check preparation',
          );
        }
      } else {
        _showCurrentFailure(
          confirmationToasts,
          'Could not prepare wallet',
          skipPending: true,
        );
      }
    } finally {
      if (!submitted && review != null) {
        final cancellationToasts = mounted ? context.toasts : null;
        await notifier.cancelRgbSetup(review);
        if (mounted && cancellationToasts != null) {
          _showCurrentFailure(
            cancellationToasts,
            'Could not close review',
            skipExpectedSetup: true,
          );
        }
      }
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _retryRgbReceive() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    setState(() => _setupCommandActive = true);
    try {
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .retryRgbReceive();
      if (mounted) _showCurrentFailure(toasts, 'Could not create request');
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _checkRgbSetup() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    setState(() => _setupCommandActive = true);
    try {
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .checkRgbSetup();
      if (mounted) _showCurrentFailure(toasts, 'Could not check preparation');
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _retryRequest() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    await ref
        .read(receiveFlowViewModelProvider(widget.target).notifier)
        .retry();
    if (mounted) _showCurrentFailure(toasts, 'Could not create request');
  }

  void _showCurrentFailure(
    ToastPresentationService toasts,
    String title, {
    bool skipPending = false,
    bool skipExpectedSetup = false,
  }) {
    final failure = _currentFailure();
    if (failure == null ||
        (skipPending && failure.code == 'rgb_wallet_setup_pending') ||
        (skipExpectedSetup &&
            (failure.code == 'rgb_wallet_setup_pending' ||
                failure.code == 'rgb_wallet_setup_required'))) {
      return;
    }
    _showReceiveFailure(toasts, title, failure);
  }

  AppFailure? _currentFailure() {
    final flow = ref.read(receiveFlowViewModelProvider(widget.target));
    return switch (flow) {
      AsyncError(:final error, :final stackTrace) => FailureMapper.from(
        error,
        stackTrace,
      ),
      AsyncData(:final value) => value.failure,
      _ => null,
    };
  }

  static void _showReceiveFailure(
    ToastPresentationService toasts,
    String title,
    AppFailure failure,
  ) {
    final (heading, message, variant) = switch (failure.code) {
      'rgb_wallet_setup_required' => (
        'Preparation needed',
        'Prepare the wallet before receiving this asset.',
        ToastVariant.warning,
      ),
      'rgb_wallet_setup_pending' => (
        'Preparation pending',
        'Check again after confirmation.',
        ToastVariant.info,
      ),
      _ => (title, failure.userMessage, ToastVariant.failure),
    };
    toasts.show(title: heading, message: message, variant: variant);
  }

  @override
  void initState() {
    super.initState();
    _now = ref.read(utcClockProvider)();
    WidgetsBinding.instance.addObserver(this);
    _listenToRequest();
  }

  @override
  void didUpdateWidget(ReceiveRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) return;
    _requestSubscription.close();
    _listenToRequest();
  }

  void _listenToRequest() {
    _requestSubscription = ref.listenManual(
      receiveFlowViewModelProvider(widget.target),
      (previous, next) {
        final failure = switch (next) {
          AsyncError(:final error, :final stackTrace) => FailureMapper.from(
            error,
            stackTrace,
          ),
          AsyncData(:final value) => value.failure,
          _ => null,
        };
        if (failure?.code == 'rgb_wallet_setup_required' ||
            failure?.code == 'rgb_wallet_setup_pending') {
          _preparationStateCode = failure!.code;
        } else if (next.isLoading ||
            (next.hasValue && next.value?.failure == null)) {
          _preparationStateCode = null;
        }
        _scheduleExpiry(next.value);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestSubscription.close();
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _scheduleExpiry(
      ref.read(receiveFlowViewModelProvider(widget.target)).value,
      notify: true,
    );
  }

  void _scheduleExpiry(ReceiveFlowState? state, {bool notify = false}) {
    _expiryTimer?.cancel();
    final now = ref.read(utcClockProvider)().toUtc();
    if (notify) {
      setState(() => _now = now);
    } else {
      _now = now;
    }
    final expiry = state?.request?.expiresAt;
    if (expiry == null) return;
    final delay = expiry.difference(now);
    if (delay <= Duration.zero) return;
    _expiryTimer = Timer(delay, () {
      if (!mounted) return;
      _scheduleExpiry(state, notify: true);
    });
  }

  Future<void> _copy() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    final result = await ref
        .read(receiveFlowViewModelProvider(widget.target).notifier)
        .copyRequest();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<void>():
        toasts.show(
          title: 'Payment request copied',
          variant: ToastVariant.success,
        );
      case AppFailureResult<void>(:final failure):
        toasts.show(
          title: 'Could not copy request',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  Future<void> _share() async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    final renderBox = context.findRenderObject();
    final origin = renderBox is RenderBox && renderBox.hasSize
        ? () {
            final offset = renderBox.localToGlobal(Offset.zero);
            return ShareOrigin(
              left: offset.dx,
              top: offset.dy,
              width: renderBox.size.width,
              height: renderBox.size.height,
            );
          }()
        : null;
    final result = await ref
        .read(receiveFlowViewModelProvider(widget.target).notifier)
        .shareRequest(origin: origin);
    if (!mounted) return;
    if (result case AppFailureResult<ShareDisposition>(:final failure)) {
      toasts.show(
        title: 'Could not share request',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }

  Future<void> _regenerate(AsterNavigationCommandOwner navigation) async {
    if (_requestActionInProgress) return;
    final toasts = context.toasts;
    await navigation.run(
      command: () async {
        final regenerated = await ref
            .read(receiveFlowViewModelProvider(widget.target).notifier)
            .regenerate();
        if (!mounted) return;
        if (regenerated) return;
        final failure = ref
            .read(receiveFlowViewModelProvider(widget.target))
            .value
            ?.failure;
        if (failure != null) {
          toasts.show(
            title: 'Could not regenerate request',
            message: failure.userMessage,
            variant: ToastVariant.failure,
          );
        }
      },
      failureTitle: 'Payment request could not be regenerated',
      hapticIntent: null,
      blocksRoutePop: true,
    );
  }

  Future<void> _showAmountSheet(
    BuildContext context,
    AsterNavigationCommandOwner navigation,
  ) async {
    if (_requestActionInProgress) return;
    await navigation.openRoute(
      command: () => ReceiveAmountSheet.show(context, target: widget.target),
      failureTitle: 'Amount editor could not open',
      hapticIntent: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = receiveFlowViewModelProvider(widget.target);
    final flow = ref.watch(provider);
    final sharing =
        flow.value?.operation == ReceiveFlowOperation.sharingRequest;
    final durableGenerationOwnsRoute =
        (flow.value?.isGenerating ?? false) || _setupCommandActive;
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final generationOwnsRoute =
              durableGenerationOwnsRoute || navigation.inFlight;
          return PopScope(
            canPop: !generationOwnsRoute,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              appBar: CustomAppBar(
                title: 'Receive ${widget.target.assetLabel}',
                leadingIcon: true,
                leadingEnabled: !generationOwnsRoute,
                centerTitle: false,
                fallbackLocation: RoutePaths.receive,
              ),
              body: IgnorePointer(
                ignoring: sharing,
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.spacing.screenPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.target == WalletPaymentTarget.usdtOnchain)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ref.read(provider.notifier).rgbReceiveMode ==
                                          RgbReceiveMode.witness
                                      ? 'Witness receive'
                                      : 'Blind receive',
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    generationOwnsRoute ||
                                        flow.isLoading ||
                                        ((flow.value?.isBusy ?? false) &&
                                            !sharing)
                                    ? null
                                    : () => unawaited(
                                        _changeRgbMode(
                                          ref
                                                      .read(provider.notifier)
                                                      .rgbReceiveMode ==
                                                  RgbReceiveMode.witness
                                              ? RgbReceiveMode.blind
                                              : RgbReceiveMode.witness,
                                        ),
                                      ),
                                child: Text(
                                  ref.read(provider.notifier).rgbReceiveMode ==
                                          RgbReceiveMode.witness
                                      ? 'Use blind receive'
                                      : 'Use witness receive',
                                ),
                              ),
                            ],
                          ),
                        Expanded(
                          child: flow.when(
                            skipLoadingOnRefresh: false,
                            data: (state) => _RequestBody(
                              // The platform sheet owns input while opening.
                              // Keep the request surface visually unchanged;
                              // the real state and command guards remain busy.
                              state: sharing
                                  ? state.copyWith(operation: null)
                                  : state,
                              now: _now,
                              commandsEnabled: !navigation.inFlight,
                              onCopy: () => unawaited(_copy()),
                              onShare: () => unawaited(_share()),
                              onRegenerate: () =>
                                  unawaited(_regenerate(navigation)),
                              onSetAmount: () => unawaited(
                                _showAmountSheet(context, navigation),
                              ),
                              onSetup: () => unawaited(_prepareRgbSetup()),
                              onCheckSetup: () => unawaited(_checkRgbSetup()),
                              onRetryReceive: () =>
                                  unawaited(_retryRgbReceive()),
                              setupBusy: _setupCommandActive,
                              preparationStateCode: _preparationStateCode,
                            ),
                            loading: () => const _RequestLoading(),
                            error: (error, stackTrace) => _RequestFailure(
                              failure: error is AppFailureException
                                  ? error.failure
                                  : FailureMapper.from(error, stackTrace),
                              onRetry: () => unawaited(_retryRequest()),
                              onSetup: () => unawaited(_prepareRgbSetup()),
                              onCheckSetup: () => unawaited(_checkRgbSetup()),
                              onRetryReceive: () =>
                                  unawaited(_retryRgbReceive()),
                              setupBusy: _setupCommandActive,
                              preparationStateCode: _preparationStateCode,
                            ),
                          ),
                        ),
                      ],
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

final class _RequestBody extends StatelessWidget {
  _RequestBody({
    required this.state,
    required this.now,
    required this.commandsEnabled,
    required this.onCopy,
    required this.onShare,
    required this.onRegenerate,
    required this.onSetAmount,
    required this.onSetup,
    required this.onCheckSetup,
    required this.onRetryReceive,
    required this.setupBusy,
    required this.preparationStateCode,
  });

  final ReceiveFlowState state;
  final DateTime now;
  final bool commandsEnabled;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRegenerate;
  final VoidCallback onSetAmount;
  final VoidCallback onSetup;
  final VoidCallback onCheckSetup;
  final VoidCallback onRetryReceive;
  final bool setupBusy;
  final String? preparationStateCode;
  final WalletAmountDisplayFormatter _formatter =
      WalletAmountDisplayFormatter();

  @override
  Widget build(BuildContext context) {
    final request = state.request;
    final expired = state.isExpiredAt(now);
    final amount = request?.amount;
    final appliedAmount = amount == null
        ? null
        : _formatter.format(
            units: amount.units,
            route: state.route,
            bitcoinUnit: state.bitcoinUnit,
          );
    return ListView(
      padding: EdgeInsets.only(
        bottom: context.windowInsets.bottomSafe + context.spacing.lg,
      ),
      children: [
        if (request == null)
          _AmountRequiredCard(target: state.route.target)
        else
          Squircle(
            borderRadius: context.radii.card,
            padding: EdgeInsets.all(context.spacing.xxl),
            child: Column(
              children: [
                if (expired)
                  AspectRatio(
                    aspectRatio: 1,
                    child: Center(
                      child: Icon(
                        MingCuteIcons.mgc_time_line,
                        size: context.icons.xl,
                        color: context.appColors.textSecondary,
                        semanticLabel:
                            'Expired payment request, QR code removed',
                      ),
                    ),
                  )
                else
                  ReceiveRequestQr(
                    encodedRequest: request.encodedRequest,
                    semanticLabel: '${state.route.target.requestLabel} QR code',
                    assetKind: state.route.asset.kind,
                  ),
                SizedBox(height: context.spacing.lg),
                if (!expired)
                  Text(
                    request.displayValue,
                    style: context.type.addressSmall,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (appliedAmount != null) ...[
                  SizedBox(height: context.spacing.sm),
                  AmountText(
                    appliedAmount.text,
                    style: context.type.rowValue,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (expired) ...[
                  SizedBox(height: context.spacing.sm),
                  Semantics(
                    container: true,
                    label: 'Expired',
                    excludeSemantics: true,
                    liveRegion: true,
                    child: Text('Expired', style: context.type.rowValue),
                  ),
                ] else if (request.expiresAt case final expiry?) ...[
                  SizedBox(height: context.spacing.sm),
                  NumericText(
                    'Expires ${DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_jms().format(expiry.toLocal())}',
                    style: context.type.rowMeta.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                SizedBox(height: context.spacing.md),
                CustomButton.compact(
                  text: 'Copy',
                  variant: ButtonVariant.secondary,
                  prefixIcon: MingCuteIcons.mgc_copy_2_line,
                  loading:
                      state.operation == ReceiveFlowOperation.copyingRequest,
                  enabled: commandsEnabled && state.canReadRequest && !expired,
                  hapticIntent: null,
                  onTap: onCopy,
                ),
              ],
            ),
          ),
        SizedBox(height: context.spacing.xxl),
        Squircle(
          padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
          child: Column(
            children: [
              AsterOptionRow(
                title: 'Set amount',
                amountDetails: appliedAmount?.text,
                prefixIcon: MingCuteIcons.mgc_edit_2_line,
                onTap: commandsEnabled && state.canEditAmount
                    ? onSetAmount
                    : null,
              ),
              if (request != null) ...[
                const AsterDivider.inset(),
                AsterOptionRow(
                  title: 'Generate new request',
                  details: state.isGenerating ? 'Generating' : null,
                  prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                  hapticIntent: null,
                  onTap: commandsEnabled && state.canRegenerate
                      ? onRegenerate
                      : null,
                ),
                const AsterDivider.inset(),
                AsterOptionRow(
                  title: 'Share',
                  prefixIcon: MingCuteIcons.mgc_share_forward_line,
                  hapticIntent: null,
                  onTap: commandsEnabled && state.canReadRequest && !expired
                      ? onShare
                      : null,
                ),
              ],
              if ((preparationStateCode ?? state.failure?.code) ==
                  'rgb_wallet_setup_required') ...[
                const AsterDivider.inset(),
                AsterOptionRow(
                  title: 'Try receive again',
                  prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                  onTap: commandsEnabled && !setupBusy ? onRetryReceive : null,
                ),
                const AsterDivider.inset(),
                AsterOptionRow(
                  title: 'Prepare wallet',
                  prefixIcon: MingCuteIcons.mgc_settings_3_line,
                  onTap: commandsEnabled && !setupBusy ? onSetup : null,
                ),
              ],
              if ((preparationStateCode ?? state.failure?.code) ==
                  'rgb_wallet_setup_pending') ...[
                const AsterDivider.inset(),
                AsterOptionRow(
                  title: 'Check preparation',
                  prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                  onTap: commandsEnabled && !setupBusy ? onCheckSetup : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final class _AmountRequiredCard extends StatelessWidget {
  const _AmountRequiredCard({required this.target});

  final WalletPaymentTarget target;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Amount required before creating ${target.semanticLabel} request',
      excludeSemantics: true,
      child: Squircle(
        borderRadius: context.radii.card,
        padding: EdgeInsets.all(context.spacing.xxl),
        child: Column(
          children: [
            WalletAssetIcon(kind: target.assetKind, size: context.icons.xl),
            SizedBox(height: context.spacing.lg),
            Text(
              'Amount required',
              style: context.type.title,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

final class _RequestLoading extends StatelessWidget {
  const _RequestLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading payment request',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: Squircle(
          borderRadius: context.radii.card,
          child: AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(color: context.appColors.surfaceSubtle),
          ),
        ),
      ),
    );
  }
}

final class _RequestFailure extends StatelessWidget {
  const _RequestFailure({
    required this.failure,
    required this.onRetry,
    required this.onSetup,
    required this.onCheckSetup,
    required this.onRetryReceive,
    required this.setupBusy,
    required this.preparationStateCode,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onSetup;
  final VoidCallback onCheckSetup;
  final VoidCallback onRetryReceive;
  final bool setupBusy;
  final String? preparationStateCode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            (preparationStateCode ?? failure.code) == 'rgb_wallet_setup_pending'
                ? MingCuteIcons.mgc_time_line
                : MingCuteIcons.mgc_information_line,
            size: context.icons.xl,
            color: context.appColors.textSecondary,
          ),
          SizedBox(height: context.spacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              switch (preparationStateCode ?? failure.code) {
                'rgb_wallet_setup_required' => 'Preparation needed',
                'rgb_wallet_setup_pending' => 'Preparation pending',
                _ => 'Request unavailable',
              },
              style: context.type.title,
              textAlign: TextAlign.center,
            ),
          ),
          if ((preparationStateCode ?? failure.code) ==
              'rgb_wallet_setup_required') ...[
            SizedBox(height: context.spacing.lg),
            CustomButton.compact(
              text: 'Try receive again',
              enabled: !setupBusy,
              onTap: onRetryReceive,
              variant: ButtonVariant.tonal,
            ),
            SizedBox(height: context.spacing.sm),
            CustomButton(
              text: 'Prepare wallet',
              loading: setupBusy,
              enabled: !setupBusy,
              onTap: onSetup,
            ),
          ] else if ((preparationStateCode ?? failure.code) ==
              'rgb_wallet_setup_pending') ...[
            SizedBox(height: context.spacing.lg),
            CustomButton(
              text: 'Check preparation',
              loading: setupBusy,
              enabled: !setupBusy,
              onTap: onCheckSetup,
            ),
          ] else if (failure.retryable) ...[
            SizedBox(height: context.spacing.lg),
            CustomButton(text: 'Retry', onTap: onRetry),
          ],
        ],
      ),
    );
  }
}

/// Deliberate consent details, rather than operational prose in the QR screen.
final class _SetupReviewRow extends StatelessWidget {
  const _SetupReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: context.spacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: context.type.rowMeta)),
        SizedBox(width: context.spacing.md),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}
