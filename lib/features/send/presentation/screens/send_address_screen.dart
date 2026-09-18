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
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Second Send step: validate an address, URI, or Lightning invoice.
class SendAddressScreen extends ConsumerStatefulWidget {
  const SendAddressScreen({super.key, required this.target});

  final WalletPaymentTarget target;

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
    final outcome = await navigation.openRouteForResult<String>(
      command: () => routeContext.push<String>(
        RoutePaths.scan,
        extra: ScanPurpose.destinationPicker,
      ),
      failureTitle: 'Scanner could not open',
    );
    final result = outcome.value;
    if (!outcome.accepted || !mounted || result == null) return;
    ref
        .read(sendFlowViewModelProvider(widget.target).notifier)
        .updateDestination(result.trim());
  }

  Future<void> _paste() async {
    final result = await ref
        .read(sendFlowViewModelProvider(widget.target).notifier)
        .pasteDestination();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<String>():
        return;
      case AppFailureResult<String>(:final failure):
        context.toasts.show(
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
    var valid = false;
    final accepted = await navigation.run(
      command: () async {
        valid = await ref
            .read(sendFlowViewModelProvider(widget.target).notifier)
            .validateDestination();
      },
      failureTitle: 'Recipient could not be validated',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !valid || !mounted || !routeContext.mounted) return;
    await navigation.openRoute(
      command: () => routeContext.pushNamed<void>(
        RouteNames.sendAmount,
        pathParameters: {RoutePaths.paymentTargetParameter: widget.target.slug},
      ),
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

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              appBar: CustomAppBar(
                title: 'Send ${widget.target.assetLabel}',
                leadingIcon: true,
                centerTitle: false,
                fallbackLocation: RoutePaths.send,
                action: AsterIconButton(
                  onPressed: controlsEnabled && !navigation.inFlight
                      ? () => _openScan(context, navigation)
                      : null,
                  hapticIntent: null,
                  icon: MingCuteIcons.mgc_scan_line,
                  tooltip:
                      'Scan ${widget.target.destinationLabel.toLowerCase()}',
                  alignment: Alignment.centerLeft,
                ),
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
      ),
    );
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
        state.operation == SendFlowOperation.validatingDestination;
    final pasting = state.operation == SendFlowOperation.readingClipboard;
    return AsterFormBody(
      content: SendAddressCard(
        target: state.route.target,
        controller: controller,
        enabled: commandsEnabled && state.canChangeDestination,
        pasting: pasting,
        failureMessage: state
            .failureFor(SendFlowOperation.validatingDestination)
            ?.userMessage,
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
