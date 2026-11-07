import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/shared/routing/routing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final empty = AsyncData(WalletState());
  final active = AsyncData(
    WalletState(wallets: [_profile()], activeWallet: _profile()),
  );

  test('unresolved wallet access is held at the wallet gate', () {
    expect(
      RouteGuards.redirect(
        location: RoutePaths.send,
        walletState: const AsyncLoading(),
      ),
      RoutePaths.splash,
    );
    expect(
      RouteGuards.redirect(
        location: RoutePaths.splash,
        walletState: AsyncError(StateError('redacted'), StackTrace.empty),
      ),
      isNull,
    );
  });

  test('empty registry can reach onboarding but never wallet routes', () {
    expect(
      RouteGuards.redirect(location: RoutePaths.home, walletState: empty),
      RoutePaths.onboardingWelcome,
    );
    expect(
      RouteGuards.redirect(
        location: RoutePaths.onboardingWelcome,
        walletState: empty,
      ),
      isNull,
    );
    expect(
      RouteGuards.redirect(
        location: '/onboarding/legacy-step',
        walletState: empty,
      ),
      RoutePaths.onboardingWelcome,
    );
  });

  test('a retained pre-deletion wallet never bypasses a terminal access error', () {
    final retained = AsyncError<WalletState>(
      const AppFailureException(
        AppFailure(
          code: 'wallet_deletion_incomplete',
          kind: AppFailureKind.storage,
          userMessage: 'Wallet removal could not finish.',
          retryable: false,
          requiresReconciliation: true,
        ),
      ),
      StackTrace.empty,
      // Model the retained value produced by AsyncNotifier's error transition.
      // ignore: invalid_use_of_internal_member
    ).copyWithPrevious(active);
    expect(retained.value?.activeWallet, isNotNull);
    expect(
      RouteGuards.redirect(location: RoutePaths.home, walletState: retained),
      RoutePaths.splash,
    );
    expect(
      RouteGuards.redirect(location: RoutePaths.splash, walletState: retained),
      isNull,
    );
  });

  test('active registry leaves wallet routes and rejects onboarding', () {
    expect(
      RouteGuards.redirect(location: RoutePaths.send, walletState: active),
      isNull,
    );
    expect(
      RouteGuards.redirect(
        location: RoutePaths.onboardingWelcome,
        walletState: active,
      ),
      RoutePaths.home,
    );
  });
}

WalletProfile _profile() {
  return WalletProfile(
    id: '11111111111111111111111111111111',
    name: 'Primary Wallet',
    createdAt: DateTime.utc(2026, 8, 8),
    updatedAt: DateTime.utc(2026, 8, 8),
    environment: BlockchainEnvironment.regtest,
    state: WalletProfileState.ready,
    storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
}
