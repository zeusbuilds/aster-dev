import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// First Receive step: choose an asset and payment rail.
class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsterNavigationScope(
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Receive',
          leadingIcon: true,
          centerTitle: false,
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.screenPadding,
            ),
            child: PaymentTargetSelectionView(
              capabilities: ref.watch(walletPaymentCapabilitiesProvider),
              onRetry: () => ref.invalidate(walletPaymentCapabilitiesProvider),
              onSelected: (target) async {
                await context.pushNamed(
                  RouteNames.receiveRequest,
                  pathParameters: {
                    RoutePaths.paymentTargetParameter: target.slug,
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
