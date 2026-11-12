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
import 'receive_request_screen.dart';

/// First Receive step: choose an asset and payment rail.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  final _requests =
      <
        WalletPaymentTarget,
        ProviderSubscription<AsyncValue<ReceiveFlowState>>
      >{};
  var _target = WalletPaymentTarget.bitcoinOnchain;
  var _requestKey = GlobalKey();
  var _showRequest = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.fitsDuoLandscapePanes && !_showRequest) {
      _showRequest = true;
      _retainRequest(_target);
    }
  }

  // Keep only visited requests for this route, including their generation
  // result and any reconciliation requirement. An inactive request is paused.
  void _retainRequest(WalletPaymentTarget target) {
    final subscription = _requests.putIfAbsent(
      target,
      () => ref.listenManual(receiveFlowViewModelProvider(target), (_, _) {}),
    );
    if (subscription.isPaused) subscription.resume();
  }

  void _clearRequests() {
    for (final subscription in _requests.values) {
      subscription.close();
    }
    _requests.clear();
  }

  @override
  void dispose() {
    _clearRequests();
    super.dispose();
  }

  static bool _isBusy(AsyncValue<ReceiveFlowState> flow) =>
      flow.value?.isBusy ?? false;

  void _returnToPicker() {
    if (_isBusy(ref.read(receiveFlowViewModelProvider(_target)))) return;
    _clearRequests();
    setState(() {
      _showRequest = false;
      _target = WalletPaymentTarget.bitcoinOnchain;
      _requestKey = GlobalKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final split = context.fitsDuoLandscapePanes;
    final compactRequest = _showRequest && !split;
    final capabilities = ref.watch(walletPaymentCapabilitiesProvider);
    final busy =
        _showRequest &&
        ref.watch(receiveFlowViewModelProvider(_target).select(_isBusy));
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          return DuoBackNavigation(
            showBack: !compactRequest,
            onBack: busy || navigation.inFlight
                ? null
                : () => unawaited(
                    navigation.run(
                      command: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(RoutePaths.home);
                        }
                      },
                      failureTitle: 'Previous page could not open',
                    ),
                  ),
            builder: (context, usesRail) {
              final picker = Scaffold(
                backgroundColor: context.colorScheme.surface,
                appBar: CustomAppBar(
                  title: 'Receive',
                  leadingIcon: !usesRail,
                  automaticallyImplyLeading: !usesRail,
                  leadingEnabled: !busy,
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
                      selectedTarget: split ? _target : null,
                      selectionEnabled: !busy,
                      onSelected: (target) async {
                        if (split) {
                          if (target == _target ||
                              _isBusy(
                                ref.read(receiveFlowViewModelProvider(_target)),
                              )) {
                            return;
                          }
                          _requests[_target]?.pause();
                          _retainRequest(target);
                          setState(() {
                            _target = target;
                            _requestKey = GlobalKey();
                          });
                        } else {
                          await context.pushNamed<void>(
                            RouteNames.receiveRequest,
                            pathParameters: {
                              RoutePaths.paymentTargetParameter: target.slug,
                            },
                          );
                        }
                      },
                    ),
                  ),
                ),
              );
              final request = ReceiveRequestScreen.embedded(
                key: _requestKey,
                target: _target,
                onBack: compactRequest ? _returnToPicker : null,
              );
              return PopScope<void>(
                canPop: !compactRequest,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && compactRequest && !navigation.inFlight) {
                    _returnToPicker();
                  }
                },
                child: split
                    ? DuoLandscapePanes(left: picker, right: request)
                    : compactRequest
                    ? request
                    : picker,
              );
            },
          );
        },
      ),
    );
  }
}
