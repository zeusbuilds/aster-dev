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
    final spacing = context.spacing;
    final walletState = ref.watch(walletViewModelProvider);
    final viewModel = ref.read(walletViewModelProvider.notifier);

    return walletState.when(
      loading: () => const _WalletSelectionScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _WalletSelectionScaffold(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Wallets could not be loaded.',
                style: context.type.rowTitle,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing.lg),
              CustomButton(text: 'Retry', onTap: viewModel.reload),
            ],
          ),
        ),
      ),
      data: (data) => _WalletSelectionScaffold(
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: spacing.lg),
          child: ListView.separated(
            itemCount: data.wallets.length,
            separatorBuilder: (context, index) => const AsterDivider.inset(),
            itemBuilder: (context, index) {
              final wallet = data.wallets[index];
              final isSelected = data.activeWallet?.id == wallet.id;
              final isSwitching = data.switchingWalletId != null;

              return WalletSelectOptionRow(
                wallet: wallet,
                selected: isSelected,
                onTap: isSelected || isSwitching
                    ? null
                    : () async {
                        final switched = await viewModel.switchWallet(
                          wallet.id,
                        );
                        if (!switched) return;
                        if (!context.mounted) return;
                        context.pop();
                      },
              );
            },
          ),
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
      appBar: const CustomAppBar(title: 'Select Wallet', leadingIcon: true),
      body: child,
    );
  }
}
