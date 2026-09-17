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
    final durableGenerationOwnsRoute = flow.value?.isGenerating ?? false;
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
              body: SafeArea(
                top: false,
                minimum: EdgeInsets.only(bottom: context.spacing.lg),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.screenPadding,
                  ),
                  child: flow.when(
                    skipLoadingOnRefresh: false,
                    data: (state) => _RequestBody(
                      state: state,
                      now: _now,
                      commandsEnabled: !navigation.inFlight,
                      onCopy: () => unawaited(_copy()),
                      onShare: () => unawaited(_share()),
                      onRegenerate: () => unawaited(_regenerate(navigation)),
                      onSetAmount: () =>
                          unawaited(_showAmountSheet(context, navigation)),
                    ),
                    loading: () => const _RequestLoading(),
                    error: (error, stackTrace) => _RequestFailure(
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

final class _RequestBody extends StatelessWidget {
  _RequestBody({
    required this.state,
    required this.now,
    required this.commandsEnabled,
    required this.onCopy,
    required this.onShare,
    required this.onRegenerate,
    required this.onSetAmount,
  });

  final ReceiveFlowState state;
  final DateTime now;
  final bool commandsEnabled;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRegenerate;
  final VoidCallback onSetAmount;
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
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: context.spacing.lg),
          child: Text(
            '${state.route.target.assetLabel} · ${state.route.target.railLabel}',
            style: context.type.sectionLabel,
            textAlign: TextAlign.center,
          ),
        ),
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
                  details:
                      state.operation == ReceiveFlowOperation.sharingRequest
                      ? 'Opening'
                      : null,
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
  const _RequestFailure({required this.failure, required this.onRetry});

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
