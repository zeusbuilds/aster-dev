import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Selects a wallet and leaves only after its native switch commits.
class WalletSelectionScreen extends ConsumerWidget {
  const WalletSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletViewModelProvider);
    final viewModel = ref.read(walletViewModelProvider.notifier);

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final spacing = context.spacing;
          return walletState.when(
            loading: () => const _WalletSelectionScaffold(
              child: Center(
                child: GridLoader(semanticLabel: 'Loading wallets'),
              ),
            ),
            error: (error, stackTrace) {
              final failure = error is AppFailureException
                  ? error.failure
                  : FailureMapper.from(error, stackTrace);
              return _WalletSelectionScaffold(
                navigationLocked: navigation.inFlight,
                child: _WalletLoadFailure(
                  failure: failure,
                  onRetry: viewModel.reload,
                ),
              );
            },
            data: (data) {
              final switchingWalletId = data.switchingWalletId;
              final navigationLocked =
                  switchingWalletId != null || navigation.inFlight;
              return _WalletSelectionScaffold(
                navigationLocked: navigationLocked,
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
      ),
    );
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
        context.toasts.show(
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
    context.pop();
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
            Semantics(
              liveRegion: true,
              child: Text(
                failure.userMessage,
                style: context.type.errorMessage,
                textAlign: TextAlign.center,
              ),
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
  const _WalletSelectionScaffold({
    required this.child,
    this.navigationLocked = false,
    this.onAddWallet,
  });

  final Widget child;
  final bool navigationLocked;
  final VoidCallback? onAddWallet;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !navigationLocked,
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Select Wallet',
          leadingIcon: true,
          leadingEnabled: !navigationLocked,
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
