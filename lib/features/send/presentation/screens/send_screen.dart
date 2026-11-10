import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../view_model/view_models.dart';
import 'send_address_screen.dart';

/// First Send step: choose an asset and payment rail.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  var _target = WalletPaymentTarget.bitcoinOnchain;
  var _recipientKey = GlobalKey();
  var _showRecipient = false;
  late final bool _startedWithScan;

  bool get _split => !_startedWithScan && context.fitsDuoLandscapePanes;

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
    if (_split) _showRecipient = true;
  }

  void _returnToPicker() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showRecipient = false;
      _target = WalletPaymentTarget.bitcoinOnchain;
      _recipientKey = GlobalKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final split = _split;
    final compactRecipient = _showRecipient && !split;
    final capabilities = ref.watch(walletPaymentCapabilitiesProvider);
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final picker = Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: const CustomAppBar(title: 'Send', leadingIcon: true),
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
                  onRetry: () =>
                      ref.invalidate(walletPaymentCapabilitiesProvider),
                  onSelected: (target) async {
                    if (split) {
                      if (target == _target) return;
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _target = target;
                        _recipientKey = GlobalKey();
                      });
                    } else {
                      await context.pushNamed<void>(
                        RouteNames.sendAddress,
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
          final recipient = SendAddressScreen.embedded(
            key: _recipientKey,
            target: _target,
            onBack: compactRecipient ? _returnToPicker : null,
          );
          return PopScope<void>(
            canPop: !compactRecipient,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) {
                ref.read(sendDestinationHandoffProvider.notifier).clear();
              } else if (compactRecipient && !navigation.inFlight) {
                _returnToPicker();
              }
            },
            child: split
                ? DuoLandscapePanes(left: picker, right: recipient)
                : compactRecipient
                ? recipient
                : picker,
          );
        },
      ),
    );
  }
}
