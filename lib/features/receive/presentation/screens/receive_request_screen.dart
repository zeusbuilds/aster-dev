import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';
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

  @override
  void initState() {
    super.initState();
    _now = ref.read(utcClockProvider)();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(
      receiveFlowViewModelProvider(widget.target),
      (previous, next) => _scheduleExpiry(next.value),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setState(() => _now = ref.read(utcClockProvider)());
  }

  void _scheduleExpiry(ReceiveFlowState? state) {
    _expiryTimer?.cancel();
    final expiry = state?.request.expiresAt;
    if (expiry == null) return;
    final delay = expiry.difference(ref.read(utcClockProvider)());
    if (delay <= Duration.zero) {
      _now = ref.read(utcClockProvider)();
      return;
    }
    _expiryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = ref.read(utcClockProvider)());
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

  Future<void> _regenerate() async {
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
  }

  @override
  Widget build(BuildContext context) {
    final provider = receiveFlowViewModelProvider(widget.target);
    final flow = ref.watch(provider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Receive ${widget.target.assetLabel}',
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
            data: (state) => _RequestBody(
              state: state,
              now: _now,
              onCopy: () => unawaited(_copy()),
              onShare: () => unawaited(_share()),
              onRegenerate: () => unawaited(_regenerate()),
              onSetAmount: () {
                ref.read(provider.notifier).clearFailure();
                unawaited(
                  ReceiveAmountSheet.show(context, target: widget.target),
                );
              },
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
    );
  }
}

final class _RequestBody extends StatelessWidget {
  _RequestBody({
    required this.state,
    required this.now,
    required this.onCopy,
    required this.onShare,
    required this.onRegenerate,
    required this.onSetAmount,
  });

  final ReceiveFlowState state;
  final DateTime now;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRegenerate;
  final VoidCallback onSetAmount;
  final WalletAmountDisplayFormatter _formatter =
      WalletAmountDisplayFormatter();

  @override
  Widget build(BuildContext context) {
    final expired = state.isExpiredAt(now);
    final amount = state.request.amount;
    final appliedAmount = amount == null
        ? null
        : _formatter.format(
            units: amount.units,
            route: state.route,
            bitcoinUnit: state.bitcoinUnit,
          );
    return ListView(
      children: [
        Squircle(
          borderRadius: context.radii.sheet,
          padding: EdgeInsets.all(context.spacing.xxl),
          child: Column(
            children: [
              Semantics(
                image: true,
                label: '${state.route.target.requestLabel} QR code',
                excludeSemantics: true,
                child: Padding(
                  padding: EdgeInsets.all(context.spacing.lg),
                  child: PrettyQrView.data(
                    data: state.request.encodedRequest,
                    decoration: PrettyQrDecoration(
                      shape: PrettyQrDotsSymbol(
                        color: context.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.spacing.lg),
              Text(
                state.request.displayValue,
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
                Text(
                  'This payment request has expired.',
                  style: context.type.errorMessage.copyWith(
                    color: context.appColors.warning,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: context.spacing.md),
              CustomButton.compact(
                text: 'Copy',
                prefixIcon: MingCuteIcons.mgc_copy_2_line,
                loading: state.operation == ReceiveFlowOperation.copyingRequest,
                enabled: !state.isBusy && !expired,
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
                details: appliedAmount?.text,
                prefixIcon: MingCuteIcons.mgc_edit_2_line,
                onTap: state.isBusy ? null : onSetAmount,
              ),
              const AsterDivider.inset(),
              AsterOptionRow(
                title: 'Generate new request',
                details: state.isGenerating ? 'Generating' : null,
                prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                hapticIntent: null,
                onTap: state.isBusy ? null : onRegenerate,
              ),
              const AsterDivider.inset(),
              AsterOptionRow(
                title: 'Share',
                details: state.operation == ReceiveFlowOperation.sharingRequest
                    ? 'Opening'
                    : null,
                prefixIcon: MingCuteIcons.mgc_share_forward_line,
                hapticIntent: null,
                onTap: state.isBusy || expired ? null : onShare,
              ),
            ],
          ),
        ),
        if (state.failure case final failure?) ...[
          SizedBox(height: context.spacing.md),
          Text(
            failure.userMessage,
            style: context.type.errorMessage.copyWith(
              color: context.appColors.danger,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

final class _RequestLoading extends StatelessWidget {
  const _RequestLoading();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonizer(
      enabled: true,
      child: Squircle(
        borderRadius: context.radii.sheet,
        child: AspectRatio(
          aspectRatio: 1,
          child: ColoredBox(color: context.appColors.surfaceSubtle),
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
