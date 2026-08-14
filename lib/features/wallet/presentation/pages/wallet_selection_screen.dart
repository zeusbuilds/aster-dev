import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Selects a wallet and leaves only after its native switch commits.
class WalletSelectionScreen extends ConsumerWidget {
  const WalletSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final walletState = ref.watch(walletViewModelProvider);
    final viewModel = ref.read(walletViewModelProvider.notifier);

    return walletState.when(
      loading: () => const _WalletSelectionScaffold(
        child: Center(child: GridLoader(semanticLabel: 'Loading wallets')),
      ),
      error: (error, stackTrace) {
        final failure = error is AppFailureException
            ? error.failure
            : FailureMapper.from(error, stackTrace);
        return _WalletSelectionScaffold(
          child: _WalletLoadFailure(
            failure: failure,
            onRetry: viewModel.reload,
          ),
        );
      },
      data: (data) {
        final switchingWalletId = data.switchingWalletId;
        return _WalletSelectionScaffold(
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: spacing.lg),
            child: ListView.separated(
              itemCount: data.wallets.length,
              separatorBuilder: (context, index) => const AsterDivider.inset(),
              itemBuilder: (context, index) {
                final wallet = data.wallets[index];
                final isSelected = data.activeWallet?.id == wallet.id;
                final isSwitching = switchingWalletId == wallet.id;

                return WalletSelectOptionRow(
                  key: ValueKey('wallet-${wallet.id}'),
                  wallet: wallet,
                  selected: isSelected,
                  enabled: switchingWalletId == null,
                  loading: isSwitching,
                  onTap: isSelected
                      ? null
                      : () => unawaited(_switchWallet(context, ref, wallet.id)),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchWallet(
    BuildContext context,
    WidgetRef ref,
    String walletId,
  ) async {
    final viewModel = ref.read(walletViewModelProvider.notifier);
    final switched = await viewModel.switchWallet(walletId);
    if (!context.mounted) return;
    if (switched) {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      context.pop();
      return;
    }
    final failure = ref.read(walletViewModelProvider).value?.operationFailure;
    if (failure == null) return;
    unawaited(context.haptics.trigger(HapticIntent.error));
    context.toasts.show(
      title: 'Wallet not switched',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
    viewModel.clearOperationFailure();
  }
}

class _WalletLoadFailure extends StatelessWidget {
  const _WalletLoadFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failure.userMessage,
              style: context.type.errorMessage,
              textAlign: TextAlign.center,
            ),
            if (failure.retryable) ...[
              SizedBox(height: context.spacing.xxl),
              CustomButton(text: 'Retry', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletSelectionScaffold extends StatelessWidget {
  const _WalletSelectionScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Select Wallet',
        leadingIcon: true,
        fallbackLocation: RoutePaths.settings,
      ),
      body: child,
    );
  }
}
