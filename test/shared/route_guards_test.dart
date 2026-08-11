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
      RouteGuards.redirect(location: RoutePaths.skeleton, walletState: empty),
      RoutePaths.onboardingWelcome,
    );
    expect(
      RouteGuards.redirect(
        location: RoutePaths.onboardingImportWallet,
        walletState: empty,
      ),
      isNull,
    );
    expect(
      RouteGuards.redirect(
        location: RoutePaths.onboardingCreateWallet,
        walletState: empty,
      ),
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
      RoutePaths.skeleton,
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
