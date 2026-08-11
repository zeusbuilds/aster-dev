import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/viewmodels.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// First Send step: choose an asset and payment rail.
class SendScreen extends ConsumerWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onSelected: (target) {
              unawaited(
                context.pushNamed(
                  RouteNames.sendAddress,
                  pathParameters: {
                    RoutePaths.paymentTargetParameter: target.slug,
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
