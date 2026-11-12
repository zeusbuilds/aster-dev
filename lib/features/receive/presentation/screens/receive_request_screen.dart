import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:remixicon/remixicon.dart';
import 'package:skeletonizer/skeletonizer.dart';

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
  const ReceiveRequestScreen({super.key, required this.target})
    : embedded = false,
      onBack = null;

  const ReceiveRequestScreen.embedded({
    super.key,
    required this.target,
    this.onBack,
  }) : embedded = true;

  final WalletPaymentTarget target;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  ConsumerState<ReceiveRequestScreen> createState() =>
      _ReceiveRequestScreenState();
}

class _ReceiveRequestScreenState extends ConsumerState<ReceiveRequestScreen>
    with WidgetsBindingObserver {
  Timer? _expiryTimer;
  AppFailure? _requestFailureBeingRetried;
  late DateTime _now;
  late ProviderSubscription<AsyncValue<ReceiveFlowState>> _requestSubscription;

  bool get _requestActionInProgress {
    final flow = ref.read(receiveFlowViewModelProvider(widget.target));
    return flow.isLoading || (flow.value?.isBusy ?? false);
  }

  Future<void> _retryRequest() async {
    final failure = _currentFailure();
    if (_requestActionInProgress ||
        _requestFailureBeingRetried != null ||
        failure?.retryable != true) {
      return;
    }
    final toasts = context.toasts;
    final target = widget.target;
    setState(() => _requestFailureBeingRetried = failure);
    try {
      await ref.read(receiveFlowViewModelProvider(target).notifier).retry();
      if (mounted && widget.target == target) {
        _showCurrentFailure(toasts, 'Could not create request');
      }
    } finally {
      if (mounted && widget.target == target) {
        setState(() => _requestFailureBeingRetried = null);
      }
    }
  }

  void _showCurrentFailure(ToastPresentationService toasts, String title) {
    final failure = _currentFailure();
    if (failure == null) return;
    toasts.show(
      title: title,
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
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
    _requestFailureBeingRetried = null;
    _requestSubscription.close();
    _listenToRequest();
  }

  void _listenToRequest() {
    _requestSubscription = ref.listenManual(
      receiveFlowViewModelProvider(widget.target),
      (previous, next) {
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
    final retrying = _requestFailureBeingRetried;
    final durableGenerationOwnsRoute = flow.value?.isGenerating ?? false;
    final content = Builder(
      builder: (context) {
        final navigation = AsterNavigationScope.of(context);
        final generationOwnsRoute =
            durableGenerationOwnsRoute || navigation.inFlight;
        return PopScope(
          canPop: !generationOwnsRoute,
          child: AsterPageScaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: CustomAppBar(
              title: 'Receive ${widget.target.assetLabel}',
              leadingIcon: !widget.embedded || widget.onBack != null,
              leadingEnabled: !generationOwnsRoute,
              onBack: widget.onBack,
              automaticallyImplyLeading: !widget.embedded,
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
                          ),
                          loading: () => retrying == null
                              ? _RequestLoading(target: widget.target)
                              : _RequestFailure(
                                  failure: retrying,
                                  retrying: true,
                                  onRetry: () => unawaited(_retryRequest()),
                                ),
                          error: (error, stackTrace) => _RequestFailure(
                            failure: error is AppFailureException
                                ? error.failure
                                : FailureMapper.from(error, stackTrace),
                            onRetry: () => unawaited(_retryRequest()),
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
    );
    return widget.embedded ? content : AsterNavigationScope(child: content);
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
    final actions = _RequestActions(
      appliedAmount: appliedAmount?.text,
      hasRequest: request != null,
      onSetAmount: commandsEnabled && state.canEditAmount ? onSetAmount : null,
      onRegenerate: commandsEnabled && state.canRegenerate
          ? onRegenerate
          : null,
      onShare: commandsEnabled && state.canReadRequest && !expired
          ? onShare
          : null,
    );
    final spacing = context.spacing;
    if (request == null) {
      return ListView(
        padding: EdgeInsets.only(
          bottom: context.windowInsets.bottomSafe + spacing.lg,
        ),
        children: [
          _AmountRequiredCard(target: state.route.target),
          SizedBox(height: spacing.xxl),
          actions,
        ],
      );
    }

    return _RequestLayout(
      qr: _qr(context, request, expired),
      details: _details(context, request, appliedAmount?.text, expired),
      actions: actions,
    );
  }

  Widget _qr(BuildContext context, WalletReceiveRequest request, bool expired) {
    if (expired) {
      return AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Icon(
            MingCuteIcons.mgc_time_line,
            size: context.icons.xl,
            color: context.appColors.textSecondary,
            semanticLabel: 'Expired payment request, QR code removed',
          ),
        ),
      );
    }
    return ReceiveRequestQr(
      encodedRequest: request.encodedRequest,
      semanticLabel: '${state.route.target.requestLabel} QR code',
      assetKind: state.route.asset.kind,
    );
  }

  List<Widget> _details(
    BuildContext context,
    WalletReceiveRequest request,
    String? appliedAmount,
    bool expired,
  ) {
    return [
      if (!expired && state.route.target == WalletPaymentTarget.usdtOnchain)
        ReceiveRequestAddress(value: request.displayValue)
      else if (!expired)
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
          appliedAmount,
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
      _requestCopyButton(
        onTap: commandsEnabled && state.canReadRequest && !expired
            ? onCopy
            : null,
      ),
    ];
  }
}

Widget _requestCopyButton({VoidCallback? onTap}) => CustomButton.compact(
  text: 'Copy',
  variant: ButtonVariant.secondary,
  prefixIcon: MingCuteIcons.mgc_copy_2_line,
  enabled: onTap != null,
  hapticIntent: null,
  onTap: onTap,
);

/// Positions the same cards in both the ready and loading states.
final class _RequestLayout extends StatelessWidget {
  const _RequestLayout({
    required this.qr,
    required this.details,
    required this.actions,
    this.loading = false,
  });

  final Widget qr;
  final List<Widget> details;
  final Widget actions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final children = [
      _requestCard(context, [qr, SizedBox(height: spacing.lg), ...details]),
      SizedBox(height: spacing.xxl),
      actions,
    ];
    return ListView(
      padding: EdgeInsets.only(
        bottom: context.windowInsets.bottomSafe + spacing.lg,
      ),
      children: loading
          ? [
              Semantics(
                container: true,
                liveRegion: true,
                label: 'Loading payment request',
                excludeSemantics: true,
                child: AppSkeletonizer(
                  enabled: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ]
          : children,
    );
  }

  Widget _requestCard(BuildContext context, List<Widget> children) {
    return Squircle(
      borderRadius: context.radii.card,
      padding: EdgeInsets.all(context.spacing.xxl),
      child: Column(children: children),
    );
  }
}

final class _RequestActions extends StatelessWidget {
  const _RequestActions({
    required this.hasRequest,
    this.appliedAmount,
    this.onSetAmount,
    this.onRegenerate,
    this.onShare,
    this.loading = false,
  });

  final bool hasRequest;
  final String? appliedAmount;
  final VoidCallback? onSetAmount;
  final VoidCallback? onRegenerate;
  final VoidCallback? onShare;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final placeholderChevron = loading ? RemixIcons.arrow_right_s_line : null;
    return Squircle(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: Column(
        children: [
          AsterOptionRow(
            title: 'Set amount',
            amountDetails: appliedAmount,
            prefixIcon: MingCuteIcons.mgc_edit_2_line,
            suffixIcon: placeholderChevron,
            onTap: onSetAmount,
          ),
          if (hasRequest) ...[
            const AsterDivider.inset(),
            AsterOptionRow(
              title: 'Generate new request',
              prefixIcon: MingCuteIcons.mgc_refresh_2_line,
              suffixIcon: placeholderChevron,
              hapticIntent: null,
              onTap: onRegenerate,
            ),
            const AsterDivider.inset(),
            AsterOptionRow(
              title: 'Share',
              prefixIcon: MingCuteIcons.mgc_share_forward_line,
              suffixIcon: placeholderChevron,
              hapticIntent: null,
              onTap: onShare,
            ),
          ],
        ],
      ),
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
  const _RequestLoading({required this.target});

  final WalletPaymentTarget target;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final type = context.type;
    final scaler = MediaQuery.textScalerOf(context);
    // Bone lays out the supplied style without applying the system scaler.
    TextStyle scaled(TextStyle style) {
      final size = style.fontSize;
      return size == null
          ? style
          : style.apply(fontSizeFactor: scaler.scale(size) / size);
    }

    final isRgb = target == WalletPaymentTarget.usdtOnchain;
    final expectsExpiry = isRgb || target.rail == PaymentRail.lightning;
    return _RequestLayout(
      loading: true,
      qr: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: AspectRatio(
          aspectRatio: 1,
          child: ColoredBox(color: context.appColors.surfaceSubtle),
        ),
      ),
      details: [
        Bone.multiText(
          key: const ValueKey('receive-loading-address'),
          lines: isRgb ? 2 : 1,
          style: scaled(type.addressSmall),
          textAlign: TextAlign.center,
        ),
        if (expectsExpiry) ...[
          SizedBox(height: spacing.sm),
          Bone.multiText(
            key: const ValueKey('receive-loading-expiry'),
            lines: 1,
            style: scaled(type.rowMeta),
            textAlign: TextAlign.center,
          ),
        ],
        SizedBox(height: spacing.md),
        Skeleton.shade(child: _requestCopyButton()),
      ],
      actions: const _RequestActions(hasRequest: true, loading: true),
    );
  }
}

final class _RequestFailure extends StatelessWidget {
  const _RequestFailure({
    required this.failure,
    required this.onRetry,
    this.retrying = false,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return ListView(
      padding: EdgeInsets.only(
        bottom: context.windowInsets.bottomSafe + spacing.lg,
      ),
      children: [
        Squircle(
          borderRadius: context.radii.card,
          padding: EdgeInsets.all(spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                MingCuteIcons.mgc_information_line,
                size: context.icons.xl,
                color: context.appColors.textSecondary,
              ),
              SizedBox(height: spacing.md),
              Semantics(
                container: true,
                liveRegion: true,
                excludeSemantics: true,
                label: 'Request unavailable',
                child: Text(
                  'Request unavailable',
                  style: context.type.title,
                  textAlign: TextAlign.center,
                ),
              ),
              if (failure.retryable) ...[
                SizedBox(height: spacing.lg),
                CustomButton(text: 'Retry', loading: retrying, onTap: onRetry),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
