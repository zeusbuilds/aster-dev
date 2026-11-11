import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import 'send_address_screen.dart';
import 'send_amount_screen.dart';

enum _SendStep { asset, address, amount, success }

/// Send entry and the in-place steps on the open Duo.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  var _target = WalletPaymentTarget.bitcoinOnchain;
  var _recipientKey = GlobalKey();
  final _amountKey = GlobalKey();
  var _step = _SendStep.asset;
  late final bool _startedWithScan;

  @override
  void initState() {
    super.initState();
    // A staged QR has no target yet. Keep explicit asset selection so the
    // default Bitcoin form cannot consume a scan intended for another asset.
    _startedWithScan = ref.read(sendDestinationHandoffProvider) != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_step == _SendStep.asset &&
        context.fitsDuoLandscapePanes &&
        !_startedWithScan) {
      _step = _SendStep.address;
    }
  }

  void _returnToPicker() {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _SendStep.asset;
      _target = WalletPaymentTarget.bitcoinOnchain;
      _recipientKey = GlobalKey();
    });
  }

  void _returnToAddress() {
    FocusScope.of(context).unfocus();
    setState(() => _step = _SendStep.address);
  }

  void _leaveSend() {
    FocusScope.of(context).unfocus();
    if (context.canPop()) {
      context.pop();
    } else {
      ref.read(sendDestinationHandoffProvider.notifier).clear();
      context.go(RoutePaths.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = context.fitsDuoLandscapePanes;
    final step = _step;
    final target = _target;
    final canPickAsset = step == _SendStep.asset || step == _SendStep.address;
    final compactRecipient = !split && step == _SendStep.address;
    final amountLocked =
        step == _SendStep.amount &&
        ref.watch(
          sendFlowViewModelProvider(target).select((flow) {
            final state = flow.value;
            return state?.operation == SendFlowOperation.submitting ||
                state?.result != null;
          }),
        );
    final capabilities = ref.watch(walletPaymentCapabilitiesProvider);
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final back = step == _SendStep.amount ? _returnToAddress : _leaveSend;
          return DuoBackNavigation(
            showBack:
                step != _SendStep.success && (split || step == _SendStep.asset),
            onBack: navigation.inFlight || amountLocked
                ? null
                : () => unawaited(
                    navigation.run(
                      command: back,
                      failureTitle: 'Previous page could not open',
                    ),
                  ),
            builder: (context, usesRail) {
              final pickerBack = !usesRail && canPickAsset;
              final picker = Scaffold(
                backgroundColor: context.colorScheme.surface,
                appBar: CustomAppBar(
                  title: 'Send',
                  leadingIcon: pickerBack,
                  automaticallyImplyLeading: pickerBack,
                  onBack: _leaveSend,
                ),
                body: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.spacing.screenPadding,
                    ),
                    child: PaymentTargetSelectionView(
                      capabilities: capabilities,
                      selectedTarget: split && step != _SendStep.asset
                          ? target
                          : null,
                      selectionEnabled: canPickAsset,
                      onRetry: () =>
                          ref.invalidate(walletPaymentCapabilitiesProvider),
                      onSelected: (selected) async {
                        if (_step != _SendStep.asset &&
                            _step != _SendStep.address) {
                          return;
                        }
                        if (split) {
                          if (_step == _SendStep.address &&
                              selected == _target) {
                            return;
                          }
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _step = _SendStep.address;
                            _target = selected;
                            _recipientKey = GlobalKey();
                          });
                        } else {
                          await context.pushNamed<void>(
                            RouteNames.sendAddress,
                            pathParameters: {
                              RoutePaths.paymentTargetParameter: selected.slug,
                            },
                          );
                        }
                      },
                    ),
                  ),
                ),
              );
              final detail = switch (step) {
                _SendStep.amount ||
                _SendStep.success => SendAmountScreen.embedded(
                  key: _amountKey,
                  target: target,
                  onBack: _returnToAddress,
                  onPaymentAccepted: () =>
                      setState(() => _step = _SendStep.success),
                  onSuccessContinue: _leaveSend,
                  showBack: step == _SendStep.amount && !usesRail,
                ),
                _SendStep.address => SendAddressScreen.embedded(
                  key: _recipientKey,
                  target: target,
                  onBack: compactRecipient ? _returnToPicker : null,
                  onAddressAccepted: () {
                    if (_step == _SendStep.address && _target == target) {
                      setState(() => _step = _SendStep.amount);
                    }
                  },
                ),
                _SendStep.asset => const SizedBox.expand(),
              };
              return PopScope<void>(
                canPop: canPickAsset && !compactRecipient,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) {
                    ref.read(sendDestinationHandoffProvider.notifier).clear();
                  } else if (!navigation.inFlight && !amountLocked) {
                    if (_step == _SendStep.amount) {
                      _returnToAddress();
                    } else if (compactRecipient) {
                      _returnToPicker();
                    }
                  }
                },
                child: split
                    ? DuoLandscapePanes(left: picker, right: detail)
                    : step == _SendStep.asset
                    ? picker
                    : detail,
              );
            },
          );
        },
      ),
    );
  }
}
