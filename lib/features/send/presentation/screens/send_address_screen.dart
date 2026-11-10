import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../scan/domain/models/models.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Second Send step: validate an address, URI, or Lightning invoice.
class SendAddressScreen extends ConsumerStatefulWidget {
  const SendAddressScreen({super.key, required this.target})
    : embedded = false,
      onBack = null;

  const SendAddressScreen.embedded({
    super.key,
    required this.target,
    this.onBack,
  }) : embedded = true;

  final WalletPaymentTarget target;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  ConsumerState<SendAddressScreen> createState() => _SendAddressScreenState();
}

class _SendAddressScreenState extends ConsumerState<SendAddressScreen> {
  final _destinationController = TextEditingController();
  late ProviderSubscription<AsyncValue<SendFlowState>> _destinationSubscription;

  @override
  void initState() {
    super.initState();
    _listenToDestination();
  }

  @override
  void didUpdateWidget(SendAddressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) return;
    _destinationSubscription.close();
    _destinationController.clear();
    _listenToDestination();
  }

  // State owns the value; the controller owns selection/composition only.
  // Hydration also runs when a retained flow attaches to a new screen.
  void _listenToDestination() {
    _destinationSubscription = ref.listenManual(
      sendFlowViewModelProvider(widget.target),
      (_, next) {
        final destination = next.value?.destination;
        if (destination == null || destination == _destinationController.text) {
          return;
        }
        _destinationController.value = TextEditingValue(
          text: destination,
          selection: TextSelection.collapsed(offset: destination.length),
        );
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _destinationSubscription.close();
    _destinationController.dispose();
    super.dispose();
  }

  void _openScan(
    BuildContext routeContext,
    AsterNavigationCommandOwner navigation,
  ) {
    unawaited(_openScanForResult(routeContext, navigation));
  }

  Future<void> _openScanForResult(
    BuildContext routeContext,
    AsterNavigationCommandOwner navigation,
  ) async {
    final target = widget.target;
    final walletId = ref.read(walletViewModelProvider).value?.activeWallet?.id;
    final outcome = await navigation.openRouteForResult<String>(
      command: () => routeContext.push<String>(
        RoutePaths.scan,
        extra: ScanPurpose.destinationPicker,
      ),
      failureTitle: 'Scanner could not open',
    );
    final result = outcome.value;
    if (!outcome.accepted ||
        !mounted ||
        result == null ||
        target != widget.target ||
        walletId == null ||
        walletId != ref.read(walletViewModelProvider).value?.activeWallet?.id) {
      return;
    }
    ref
        .read(sendFlowViewModelProvider(target).notifier)
        .updateDestination(result.trim());
  }

  Future<void> _paste() async {
    final provider = sendFlowViewModelProvider(widget.target);
    if (ref.read(provider).value?.canReadClipboard != true) return;
    final toasts = context.toasts;
    final result = await ref.read(provider.notifier).pasteDestination();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<String>():
        return;
      case AppFailureResult<String>(:final failure):
        toasts.show(
          title: failure.code == 'clipboard_empty'
              ? 'Clipboard is empty'
              : 'Could not paste',
          message: failure.code == 'clipboard_empty'
              ? null
              : failure.userMessage,
          variant: failure.code == 'clipboard_empty'
              ? ToastVariant.info
              : ToastVariant.failure,
        );
    }
  }

  void _continue(
    BuildContext routeContext,
    AsterNavigationCommandOwner navigation,
  ) {
    unawaited(_validateAndOpenAmount(routeContext, navigation));
  }

  Future<void> _validateAndOpenAmount(
    BuildContext routeContext,
    AsterNavigationCommandOwner navigation,
  ) async {
    final toasts = routeContext.toasts;
    final target = widget.target;
    final provider = sendFlowViewModelProvider(target);
    final notifier = ref.read(provider.notifier);
    final destination = ref.read(provider).value?.destination;
    if (destination == null || destination.trim().isEmpty) return;
    var walletId = ref.read(walletViewModelProvider).value?.activeWallet?.id;

    bool ownsInput({bool requirePreview = false}) {
      if (!mounted ||
          widget.target != target ||
          !routeContext.mounted ||
          !(ModalRoute.of(routeContext)?.isCurrent ?? true) ||
          !TickerMode.valuesOf(routeContext).enabled ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) ||
          !identical(ref.read(provider.notifier), notifier)) {
        return false;
      }
      final wallet = ref.read(walletViewModelProvider);
      if (walletId == null ||
          wallet.isLoading ||
          wallet.hasError ||
          wallet.value?.isChangingWallet == true ||
          wallet.value?.activeWallet?.id != walletId) {
        return false;
      }
      final flow = ref.read(provider);
      final current = flow.value;
      return !flow.isLoading &&
          !flow.hasError &&
          current != null &&
          current.destination == destination &&
          (!requirePreview ||
              (current.hasValidatedDestination &&
                  current.failureFor(SendFlowOperation.validatingDestination) ==
                      null &&
                  current.failureFor(SendFlowOperation.preparingAmount) ==
                      null));
    }

    var valid = false;
    final accepted = await navigation.run(
      command: () async {
        FocusScope.of(routeContext).unfocus();
        final wallet = await ref.read(walletViewModelProvider.future);
        walletId ??= wallet.activeWallet?.id;
        if (!ownsInput()) return;
        valid = await notifier.validateDestination();
        if (!ownsInput()) {
          valid = false;
          return;
        }
        final current = ref.read(provider).requireValue;
        final failure = current.failureFor(
          SendFlowOperation.validatingDestination,
        );
        valid = valid && current.hasValidatedDestination && failure == null;
        if (!valid && failure != null && mounted) {
          toasts.show(
            title: 'Check recipient',
            message: failure.userMessage,
            variant: ToastVariant.warning,
          );
        }
        if (!valid || !ownsInput(requirePreview: true)) return;

        valid = await notifier.prepareAmount();
        if (!ownsInput()) {
          valid = false;
          return;
        }
        final prepared = ref.read(provider).requireValue;
        final balanceFailure = prepared.failureFor(
          SendFlowOperation.preparingAmount,
        );
        valid =
            valid &&
            prepared.hasValidatedDestination &&
            prepared.balancePreparedForDestination &&
            balanceFailure == null;
        if (!valid && balanceFailure != null && mounted) {
          toasts.show(
            title: balanceFailure.code == 'payment_request_expired'
                ? 'Invoice expired'
                : 'Balance unavailable',
            message: balanceFailure.userMessage,
            variant: ToastVariant.warning,
          );
        }
      },
      failureTitle: 'Recipient could not be validated',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted ||
        !valid ||
        !ownsInput(requirePreview: true) ||
        ref.read(provider).value?.balancePreparedForDestination != true) {
      return;
    }
    await navigation.openRoute(
      command: () async {
        if (!ownsInput(requirePreview: true) ||
            ref.read(provider).value?.balancePreparedForDestination != true) {
          return;
        }
        await routeContext.pushNamed<void>(
          RouteNames.sendAmount,
          pathParameters: {RoutePaths.paymentTargetParameter: target.slug},
        );
      },
      failureTitle: 'Amount entry could not open',
      hapticIntent: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = sendFlowViewModelProvider(widget.target);
    final flow = ref.watch(provider);
    final current = flow.value;
    final controlsEnabled = current?.canChangeDestination ?? false;

    final content = Builder(
      builder: (context) {
        final navigation = AsterNavigationScope.of(context);
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: CustomAppBar(
              title: widget.target.sendTitle,
              leadingIcon: !widget.embedded || widget.onBack != null,
              onBack: widget.onBack,
              automaticallyImplyLeading: !widget.embedded,
              centerTitle: false,
              fallbackLocation: RoutePaths.send,
              action: AsterIconButton(
                onPressed: controlsEnabled && !navigation.inFlight
                    ? () => _openScan(context, navigation)
                    : null,
                hapticIntent: null,
                icon: MingCuteIcons.mgc_scan_line,
                tooltip: 'Scan ${widget.target.destinationLabel.toLowerCase()}',
                alignment: Alignment.centerLeft,
              ),
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
                  data: (state) => _DestinationBody(
                    state: state,
                    commandsEnabled: !navigation.inFlight,
                    controller: _destinationController,
                    onChanged: ref.read(provider.notifier).updateDestination,
                    onClear: () {
                      _destinationController.clear();
                      ref.read(provider.notifier).updateDestination('');
                    },
                    onPaste: () => unawaited(_paste()),
                    onSubmitted: () => _continue(context, navigation),
                    onContinue: () => _continue(context, navigation),
                  ),
                  loading: () => _DestinationLoading(target: widget.target),
                  error: (error, stackTrace) => _DestinationFailure(
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
    );
    return widget.embedded ? content : AsterNavigationScope(child: content);
  }
}

final class _DestinationBody extends StatelessWidget {
  const _DestinationBody({
    required this.state,
    required this.commandsEnabled,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onPaste,
    required this.onSubmitted,
    required this.onContinue,
  });

  final SendFlowState state;
  final bool commandsEnabled;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPaste;
  final VoidCallback onSubmitted;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final validating =
        state.operation == SendFlowOperation.validatingDestination ||
        state.operation == SendFlowOperation.preparingAmount;
    final pasting = state.operation == SendFlowOperation.readingClipboard;
    return AsterFormBody(
      bottomPadding: context.windowInsets.bottomSafe + context.spacing.lg,
      content: SendAddressCard(
        target: state.route.target,
        controller: controller,
        enabled: commandsEnabled && state.canChangeDestination,
        pasting: pasting,
        onChanged: onChanged,
        onClear: onClear,
        onPaste: onPaste,
        onSubmitted: onSubmitted,
      ),
      actions: [
        CustomButton(
          text: 'Continue',
          loading: validating,
          enabled:
              commandsEnabled &&
              state.canStart(SendFlowOperation.validatingDestination) &&
              state.destination.trim().isNotEmpty,
          hapticIntent: null,
          onTap: onContinue,
        ),
      ],
    );
  }
}

final class _DestinationLoading extends StatelessWidget {
  const _DestinationLoading({required this.target});

  final WalletPaymentTarget target;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading recipient form',
      excludeSemantics: true,
      child: AsterFormBody(
        bottomPadding: context.windowInsets.bottomSafe + context.spacing.lg,
        content: SendAddressCard.loading(target: target),
        actions: const [CustomButton(text: 'Continue')],
      ),
    );
  }
}

final class _DestinationFailure extends StatelessWidget {
  const _DestinationFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: context.windowInsets.bottomSafe + context.spacing.lg,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
          ),
        ),
      ],
    );
  }
}
