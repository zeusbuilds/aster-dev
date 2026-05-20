import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../view_model/viewmodels.dart';
import '../widgets/widgets.dart';

/// Screen for selecting and switching between available wallets
///
/// Displays a list of all wallets with the currently active wallet highlighted
class WalletSelectionScreen extends ConsumerWidget {
  const WalletSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final walletState = ref.watch(walletViewModelProvider);
    final viewModel = ref.read(walletViewModelProvider.notifier);

    // Loading state
    if (walletState.isLoading) {
      return Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: const CustomAppBar(title: 'Select Wallet', leadingIcon: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Error state
    if (walletState.errorMessage != null) {
      return Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: const CustomAppBar(title: 'Select Wallet', leadingIcon: true),
        body: Center(child: Text('Error: ${walletState.errorMessage}')),
      );
    }

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Select Wallet', leadingIcon: true),
      body: ListView.separated(
        padding: EdgeInsets.only(bottom: spacing.bottomSafeRaw(context)),
        itemCount: walletState.wallets.length,
        separatorBuilder: (context, index) => Divider(
          color: colors.surfaceSubtle,
          height: 1,
          thickness: 1,
          indent: spacing.screenPadding,
        ),
        itemBuilder: (context, index) {
          final wallet = walletState.wallets[index];
          final isSelected = walletState.activeWallet?.id == wallet.id;

          return WalletSelectOptionRow(
            wallet: wallet,
            selected: walletState.activeWallet?.id ?? -1,
            onTap: () async {
              if (!isSelected) {
                await viewModel.switchWallet(wallet.compactWalletId);
                await Future.delayed(const Duration(milliseconds: 250));
                if (!context.mounted) return;
                context.pop();
              }
            },
          );
        },
      ),
    );
  }
}
