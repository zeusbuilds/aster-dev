import 'dart:async';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  for (final network in BlockchainEnvironment.values) {
    testWidgets('wallet details uses the active $network profile metadata', (
      tester,
    ) async {
      final profile = _profile(environment: network);
      await _pumpDetails(
        tester,
        _ControlledWalletViewModel(Future.value(_state(profile))),
      );

      expect(find.text('Wallet details'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text(profile.name), findsOneWidget);
      expect(find.text('Wallet ID'), findsOneWidget);
      expect(find.text(profile.displayId), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(
        find.text(switch (network) {
          BlockchainEnvironment.mainnet => 'Mainnet',
          BlockchainEnvironment.signet => 'Signet',
          BlockchainEnvironment.regtest => 'Regtest',
        }),
        findsOneWidget,
      );
      expect(find.text('Added'), findsOneWidget);
      expect(
        find.text(
          DateFormat.yMMMd('en_US').format(profile.createdAt.toLocal()),
        ),
        findsOneWidget,
      );
      expect(find.text(profile.id), findsNothing);
      expect(find.text(profile.storageToken), findsNothing);
      expect(find.textContaining('xpub'), findsNothing);
      expect(find.textContaining('seed'), findsNothing);
      expect(find.text('Unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading and wallet switching never retain old profile details', (
    tester,
  ) async {
    final first = _profile();
    final second = _profile(
      id: '11111111111111111111111111111111',
      name: 'Second wallet',
      environment: BlockchainEnvironment.mainnet,
    );
    final viewModel = _ControlledWalletViewModel(Future.value(_state(first)));
    await _pumpDetails(tester, viewModel);
    expect(find.text(first.name), findsOneWidget);

    final refresh = Completer<WalletState>();
    viewModel.refreshFrom(refresh.future);
    await tester.pump();
    expect(find.bySemanticsLabel('Loading wallet details'), findsNothing);
    expect(find.text(first.name), findsNothing);
    expect(find.text(first.displayId), findsNothing);
    refresh.complete(_state(first));
    await tester.pump();

    viewModel.publish(
      AsyncData(_state(first).copyWith(switchingWalletId: second.id)),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading wallet details'), findsNothing);
    expect(find.text(first.name), findsNothing);
    expect(find.text(second.name), findsNothing);

    viewModel.publish(AsyncData(_state(second)));
    await tester.pump();
    expect(find.text(second.name), findsOneWidget);
    expect(find.text(second.displayId), findsOneWidget);
    expect(find.text('Mainnet'), findsOneWidget);
    expect(find.text(first.name), findsNothing);
    expect(find.text(first.displayId), findsNothing);

    final failedRefresh = Completer<WalletState>();
    viewModel.refreshFrom(failedRefresh.future);
    await tester.pump();
    failedRefresh.completeError(
      const AppFailureException(_retryableFailure),
      StackTrace.current,
    );
    await tester.pump();
    expect(find.text('Wallet unavailable'), findsNothing);
    expect(find.text(second.name), findsNothing);
    expect(find.text(second.displayId), findsNothing);
    expect(find.text(_retryableFailure.userMessage), findsNothing);
  });

  for (final missing in [true, false]) {
    testWidgets(
      '${missing ? 'missing' : 'provisioning'} wallet exposes no metadata',
      (tester) async {
        final profile = _profile(state: WalletProfileState.provisioning);
        await _pumpDetails(
          tester,
          _ControlledWalletViewModel(
            Future.value(missing ? WalletState() : _state(profile)),
          ),
        );

        expect(find.text('Wallet unavailable'), findsNothing);
        expect(find.text(profile.name), findsNothing);
        expect(find.text(profile.displayId), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Added'), findsNothing);
        expect(find.bySemanticsLabel('Back'), findsOneWidget);
      },
    );
  }

  for (final retryable in [true, false]) {
    testWidgets(
      '${retryable ? 'retryable' : 'terminal'} registry failure leaves recovery to wallet access',
      (tester) async {
        final failure = retryable
            ? _retryableFailure
            : const AppFailure(
                code: 'wallet_profile_configuration_invalid',
                kind: AppFailureKind.configuration,
                userMessage: 'Internal wallet configuration is not usable.',
                retryable: false,
              );
        final initial = Completer<WalletState>();
        final viewModel = _ControlledWalletViewModel(initial.future);
        await _pumpDetails(tester, viewModel);
        initial.completeError(AppFailureException(failure), StackTrace.current);
        await tester.pump();

        expect(find.text('Wallet unavailable'), findsNothing);
        expect(find.text(failure.userMessage), findsNothing);
        expect(find.bySemanticsLabel('Back'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Delete wallet'), findsNothing);
      },
    );
  }

  testWidgets(
    'wallet details remains readable with a long name and large text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(bottom: 68);
      tester.view.viewPadding = const FakeViewPadding(bottom: 68);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final profile = _profile(name: 'W' * 64);
      await _pumpDetails(
        tester,
        _ControlledWalletViewModel(Future.value(_state(profile))),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.text(profile.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Added'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();
      expect(find.text('Added').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

const _retryableFailure = AppFailure(
  code: 'wallet_profile_read_unavailable',
  kind: AppFailureKind.storage,
  userMessage: 'Internal wallet profile storage read failed.',
  retryable: true,
);

WalletProfile _profile({
  String id = '0123456789abcdef0123456789abcdef',
  String name = 'Primary wallet',
  BlockchainEnvironment environment = BlockchainEnvironment.regtest,
  WalletProfileState state = WalletProfileState.ready,
}) => WalletProfile(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 10, 25, 0, 15),
  updatedAt: DateTime.utc(2026, 10, 25, 0, 15),
  environment: environment,
  state: state,
  storageToken: 'fedcba9876543210fedcba9876543210',
);

WalletState _state(WalletProfile profile) =>
    WalletState(wallets: [profile], activeWallet: profile);

Future<void> _pumpDetails(
  WidgetTester tester,
  _ControlledWalletViewModel viewModel, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: applicationProviderRetryPolicy,
      overrides: [walletViewModelProvider.overrideWith(() => viewModel)],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const WalletDetailsScreen(),
      ),
    ),
  );
  await tester.pump();
}

final class _ControlledWalletViewModel extends WalletViewModel {
  _ControlledWalletViewModel(this.initial);

  Future<WalletState> initial;

  @override
  Future<WalletState> build() => initial;

  void publish(AsyncValue<WalletState> next) => state = next;

  void refreshFrom(Future<WalletState> next) {
    initial = next;
    ref.invalidateSelf();
  }
}
