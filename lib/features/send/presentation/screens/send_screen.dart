import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../view_model/view_models.dart';

/// First Send step: choose an asset and payment rail.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  late final SendDestinationHandoff _destinationHandoff;

  @override
  void initState() {
    super.initState();
    _destinationHandoff = ref.read(sendDestinationHandoffProvider.notifier);
  }

  @override
  void dispose() {
    _destinationHandoff.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Send',
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
          child: PaymentTargetSelectionView(
            capabilities: ref.watch(walletPaymentCapabilitiesProvider),
            onRetry: () => ref.invalidate(walletPaymentCapabilitiesProvider),
            onSelected: (target) async {
              await context.pushNamed(
                RouteNames.sendAddress,
                pathParameters: {
                  RoutePaths.paymentTargetParameter: target.slug,
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
