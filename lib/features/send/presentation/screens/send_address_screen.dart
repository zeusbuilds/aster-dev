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

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _openScan() async {
    final result = await context.push<String?>(
      RoutePaths.scan,
      extra: ScanPurpose.destinationPicker,
    );
    if (!mounted || result == null) return;
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

  Future<void> _continue() async {
    final valid = await ref
        .read(sendFlowViewModelProvider(widget.target).notifier)
        .validateDestination();
    if (!mounted || !valid) return;
    await context.pushNamed(
      RouteNames.sendAmount,
      pathParameters: {RoutePaths.paymentTargetParameter: widget.target.slug},
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = sendFlowViewModelProvider(widget.target);
    ref.listen(provider, (previous, next) {
      final destination = next.value?.destination;
      if (destination == null || destination == _destinationController.text) {
        return;
      }
      _destinationController.value = TextEditingValue(
        text: destination,
        selection: TextSelection.collapsed(offset: destination.length),
      );
    });
    final flow = ref.watch(provider);
    final current = flow.value;
    final busy = current?.isBusy ?? false;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Send ${widget.target.assetLabel}',
          leadingIcon: true,
          centerTitle: false,
          action: AsterIconButton(
            onPressed: busy ? null : () => unawaited(_openScan()),
            icon: MingCuteIcons.mgc_scan_line,
            tooltip: 'Scan ${widget.target.destinationLabel.toLowerCase()}',
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
                controller: _destinationController,
                onChanged: ref.read(provider.notifier).updateDestination,
                onClear: () {
                  _destinationController.clear();
                  ref.read(provider.notifier).updateDestination('');
                },
                onPaste: () => unawaited(_paste()),
                onContinue: () => unawaited(_continue()),
              ),
              loading: () => const _DestinationLoading(),
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
  }
}

final class _DestinationBody extends StatelessWidget {
  const _DestinationBody({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onPaste,
    required this.onContinue,
  });

  final SendFlowState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPaste;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final validating =
        state.operation == SendFlowOperation.validatingDestination;
    final pasting = state.operation == SendFlowOperation.readingClipboard;
    return Column(
      children: [
        SendAddressCard(
          target: state.route.target,
          controller: controller,
          enabled: !state.isBusy,
          pasting: pasting,
          failureMessage: state.failure?.userMessage,
          onChanged: onChanged,
          onClear: onClear,
          onPaste: onPaste,
        ),
        const Spacer(),
        CustomButton(
          text: 'Continue',
          loading: validating,
          enabled: !state.isBusy && state.destination.trim().isNotEmpty,
          hapticIntent: null,
          onTap: onContinue,
        ),
      ],
    );
  }
}

final class _DestinationLoading extends StatelessWidget {
  const _DestinationLoading();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonizer(
      enabled: true,
      child: Column(
        children: [
          Squircle(
            borderRadius: context.radii.card,
            child: SizedBox(height: context.metrics.selectionIndicatorHeight),
          ),
          const Spacer(),
          const CustomButton(text: 'Continue'),
        ],
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
