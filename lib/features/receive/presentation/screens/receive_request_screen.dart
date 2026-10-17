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
              'A blind request uses prepared wallet-owned Bitcoin outputs. If none are available, you can prepare them separately and pay a Bitcoin network fee. Witness receive remains available without preparation.',
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
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .setRgbReceiveMode(mode);
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _prepareRgbSetup() async {
    if (_requestActionInProgress) return;
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
      if (review == null || !mounted) return;
      final current = review;
      var decisionMade = false;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Prepare RGB wallet?'),
          content: SingleChildScrollView(
            child: Text(
              'Create up to ${RgbWalletSetupReview.outputCount} wallet-owned outputs of '
              '${RgbWalletSetupReview.outputValueSats} sat each at '
              '${current.feeRateSatPerVbyte} sat/vB.\n'
              '${current.feeSource == WalletFeeRateSource.localRegtestPolicy ? 'Local test fee rate' : 'Network fee rate'}\n\n'
              'The native wallet may create fewer outputs after allowing for the network fee. The outputs remain in your wallet. Only the Bitcoin network fee is spent. '
              'The final fee is unknown until construction; no total fee cap applies. '
              'Receiving USDT starts only after confirmation.\n\n'
              'This review expires in two minutes.',
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
      await notifier.confirmRgbSetup(current);
    } finally {
      if (!submitted && review != null) await notifier.cancelRgbSetup(review);
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _retryRgbReceive() async {
    if (_requestActionInProgress) return;
    setState(() => _setupCommandActive = true);
    try {
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .retryRgbReceive();
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
  }

  Future<void> _checkRgbSetup() async {
    if (_requestActionInProgress) return;
    setState(() => _setupCommandActive = true);
    try {
      await ref
          .read(receiveFlowViewModelProvider(widget.target).notifier)
          .checkRgbSetup();
    } finally {
      if (mounted) setState(() => _setupCommandActive = false);
    }
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
      (previous, next) => _scheduleExpiry(next.value),
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
    final result = await ref
        .read(receiveFlowViewModelProvider(widget.target).notifier)
        .copyRequest();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<void>():
        context.toasts.show(
          title: 'Payment request copied',
          variant: ToastVariant.success,
        );
      case AppFailureResult<void>(:final failure):
        context.toasts.show(
          title: 'Could not copy request',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  Future<void> _share() async {
    if (_requestActionInProgress) return;
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
      context.toasts.show(
        title: 'Could not share request',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }

  Future<void> _regenerate(AsterNavigationCommandOwner navigation) async {
    if (_requestActionInProgress) return;
    await navigation.run(
      command: () async {
        final regenerated = await ref
            .read(receiveFlowViewModelProvider(widget.target).notifier)
            .regenerate();
        if (!mounted) return;
        if (regenerated) {
          context.toasts.show(
            title: 'New payment request ready',
            variant: ToastVariant.success,
          );
          return;
        }
        final failure = ref
            .read(receiveFlowViewModelProvider(widget.target))
            .value
            ?.failure;
        if (failure != null) {
          context.toasts.show(
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
                            ),
                            loading: () => const _RequestLoading(),
                            error: (error, stackTrace) => _RequestFailure(
                              failure: error is AppFailureException
                                  ? error.failure
                                  : FailureMapper.from(error, stackTrace),
                              onRetry: ref.read(provider.notifier).retry,
                              onSetup: () => unawaited(_prepareRgbSetup()),
                              onCheckSetup: () => unawaited(_checkRgbSetup()),
                              onRetryReceive: () =>
                                  unawaited(_retryRgbReceive()),
                              setupBusy: _setupCommandActive,
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
                  const AsterStatusMessage(
                    'This payment request has expired.',
                    tone: AsterStatusTone.warning,
                    announce: true,
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
            ],
          ),
        ),
        if (state.failure case final failure?) ...[
          SizedBox(height: context.spacing.md),
          AsterStatusMessage(failure.userMessage, tone: AsterStatusTone.danger),
          if (failure.code == 'rgb_wallet_setup_required')
            CustomButton.compact(
              text: 'Try receive again',
              enabled: !setupBusy,
              onTap: onRetryReceive,
              variant: ButtonVariant.tonal,
            ),
          if (failure.code == 'rgb_wallet_setup_required')
            CustomButton(
              text: 'Prepare wallet',
              loading: setupBusy,
              enabled: !setupBusy,
              onTap: onSetup,
            ),
          if (failure.code == 'rgb_wallet_setup_pending')
            CustomButton(
              text: 'Check preparation',
              loading: setupBusy,
              enabled: !setupBusy,
              onTap: onCheckSetup,
            ),
        ],
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
            SizedBox(height: context.spacing.sm),
            Text(
              'Set a ${target.assetLabel} amount to create this '
              '${target.railLabel} request.',
              style: context.type.statusMessage,
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
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onSetup;
  final VoidCallback onCheckSetup;
  final VoidCallback onRetryReceive;
  final bool setupBusy;

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
          if (failure.code == 'rgb_wallet_setup_required') ...[
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
          ] else if (failure.code == 'rgb_wallet_setup_pending') ...[
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
