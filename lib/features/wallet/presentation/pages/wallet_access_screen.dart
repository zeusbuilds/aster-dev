import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/wallet_view_model.dart';

/// Route-level wallet access gate shown only while session state is unresolved.
class WalletAccessScreen extends ConsumerWidget {
  const WalletAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletViewModelProvider);
    return switch (state) {
      AsyncError<WalletState>(:final error, :final stackTrace) =>
        _WalletAccessFailure(
          failure: FailureMapper.from(error, stackTrace),
          onRetry: () => ref.read(walletViewModelProvider.notifier).reload(),
        ),
      _ => const SplashScreen(),
    };
  }
}

class _WalletAccessFailure extends StatelessWidget {
  const _WalletAccessFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(context.spacing.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  color: context.appColors.danger,
                  size: context.icons.xl,
                ),
                SizedBox(height: context.spacing.lg),
                Text(
                  'Wallet access unavailable',
                  style: context.type.title,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.spacing.sm),
                Text(
                  failure.userMessage,
                  style: context.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (failure.retryable) ...[
                  SizedBox(height: context.spacing.xxl),
                  CustomButton(text: 'Retry', onTap: onRetry),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
