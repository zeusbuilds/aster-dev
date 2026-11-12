import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Selects a wallet and leaves only after its native switch commits.
class WalletSelectionScreen extends ConsumerWidget {
  const WalletSelectionScreen({super.key, this.onClose, this.showBack = true});

  /// Returns an embedded chooser to its Settings panel.
  final VoidCallback? onClose;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletViewModelProvider);
    final content = Builder(
      builder: (context) {
        final navigation = AsterNavigationScope.of(context);
        final spacing = context.spacing;
        return walletState.when(
          skipLoadingOnRefresh: false,
          loading: () => _WalletSelectionScaffold(
            onClose: onClose,
            showBack: showBack,
            child: const AsterHorizontalSafeArea(
              child: Center(
                child: GridLoader(semanticLabel: 'Loading wallets'),
              ),
            ),
          ),
          // The router hands a registry error to Wallet Access. Do not expose
          // saved wallet names or a second recovery action while it redirects.
          error: (_, _) => _WalletSelectionScaffold(
            navigationLocked: navigation.inFlight,
            onClose: onClose,
            showBack: showBack,
            child: const SizedBox.shrink(),
          ),
          data: (data) {
            final switchingWalletId = data.switchingWalletId;
            final navigationLocked =
                data.isChangingWallet || navigation.inFlight;
            return _WalletSelectionScaffold(
              navigationLocked: navigationLocked,
              onClose: onClose,
              showBack: showBack,
              onAddWallet: navigationLocked
                  ? null
                  : () => _openAddWallet(context, navigation),
              child: SafeArea(
                top: false,
                bottom: false,
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: spacing.lg + context.windowInsets.bottomSafe,
                  ),
                  itemCount: data.wallets.length,
                  separatorBuilder: (context, index) =>
                      const AsterDivider.inset(),
                  itemBuilder: (context, index) {
                    final wallet = data.wallets[index];
                    final isSelected = data.activeWallet?.id == wallet.id;
                    final isSwitching = switchingWalletId == wallet.id;

                    return WalletSelectOptionRow(
                      key: ValueKey('wallet-${wallet.id}'),
                      wallet: wallet,
                      selected: isSelected,
                      enabled: !navigationLocked,
                      loading: isSwitching,
                      onTap: isSelected || navigationLocked
                          ? null
                          : () => unawaited(
                              _switchWallet(
                                context,
                                ref,
                                navigation,
                                wallet.id,
                              ),
                            ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
    return onClose == null ? AsterNavigationScope(child: content) : content;
  }

  void _openAddWallet(
    BuildContext context,
    AsterNavigationCommandOwner navigation,
  ) {
    unawaited(
      navigation.openRoute(
        command: () => context.pushNamed<void>(RouteNames.addWallet),
        failureTitle: 'Wallet setup could not open',
      ),
    );
  }

  Future<void> _switchWallet(
    BuildContext context,
    WidgetRef ref,
    AsterNavigationCommandOwner navigation,
    String walletId,
  ) async {
    final toasts = context.toasts;
    final viewModel = ref.read(walletViewModelProvider.notifier);
    final confirmationDelay = context.motionPolicy.duration(
      context.motion.selectionCommitDelay,
    );
    var switched = false;
    final accepted = await navigation.run(
      command: () async {
        switched = await viewModel.switchWallet(walletId);
        if (!context.mounted) return;
        if (switched) {
          unawaited(context.haptics.trigger(HapticIntent.selection));
          await WidgetsBinding.instance.endOfFrame;
          if (confirmationDelay > Duration.zero) {
            await Future<void>.delayed(confirmationDelay);
          }
          return;
        }
        final failure = ref
            .read(walletViewModelProvider)
            .value
            ?.operationFailure;
        if (failure == null) return;
        unawaited(context.haptics.trigger(HapticIntent.error));
        toasts.show(
          title: 'Wallet not switched',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
        viewModel.clearOperationFailure();
      },
      failureTitle: 'Wallet could not be switched',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !switched || !context.mounted) return;
    if (onClose case final close?) {
      close();
    } else {
      context.pop();
    }
  }
}

class _WalletSelectionScaffold extends StatelessWidget {
  const _WalletSelectionScaffold({
    required this.child,
    this.navigationLocked = false,
    this.onAddWallet,
    this.onClose,
    required this.showBack,
  });

  final Widget child;
  final bool navigationLocked;
  final VoidCallback? onAddWallet;
  final VoidCallback? onClose;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !navigationLocked,
      child: AsterPageScaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Select Wallet',
          leadingIcon: showBack,
          automaticallyImplyLeading: showBack,
          leadingEnabled: !navigationLocked,
          onBack: onClose,
          fallbackLocation: RoutePaths.settings,
          action: AsterIconButton(
            icon: RemixIcons.add_line,
            tooltip: 'Add wallet',
            onPressed: onAddWallet,
            hapticIntent: null,
            alignment: Alignment.centerLeft,
          ),
        ),
        body: child,
      ),
    );
  }
}
