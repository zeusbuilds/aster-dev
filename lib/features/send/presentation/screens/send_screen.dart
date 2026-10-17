import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../view_model/view_models.dart';

/// First Send step: choose an asset and payment rail.
class SendScreen extends ConsumerWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(sendDestinationHandoffProvider.notifier).clear();
        }
      },
      child: AsterNavigationScope(
        child: Scaffold(
          backgroundColor: context.colorScheme.surface,
          appBar: CustomAppBar(
            title: 'Send',
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
                onRetry: () =>
                    ref.invalidate(walletPaymentCapabilitiesProvider),
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
        ),
      ),
    );
  }
}
