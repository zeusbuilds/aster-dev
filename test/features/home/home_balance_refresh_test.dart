import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/screens/screens.dart';
import 'package:aster/features/home/presentation/view_model/view_models.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/features/transaction/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  testWidgets(
    'returning from real Activity updates the retained Home balance',
    (tester) async {
      final h = await _Harness.create(tester);
      final router = GoRouter(
        initialLocation: '/test-home',
        routes: [
          GoRoute(path: '/test-home', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: RoutePaths.transactionList,
            name: RouteNames.transactionList,
            builder: (_, _) =>
                const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
          ),
        ],
      );
      addTearDown(router.dispose);
      await h.pump(tester, router: router);
      await _until(tester, () => h.homeUnits == 0);
      await _until(
        tester,
        () => tester
            .widgetList<AssetRow>(find.byType(AssetRow))
            .any(
              (row) => row.kind == WalletAssetKind.bitcoin && row.onTap != null,
            ),
      );
      expect(h.syncCount, 0);

      h.engine
        ..balance = _balance(10000000)
        ..activities = [
          WalletActivity(
            id: 'activity-${List.filled(64, 'a').join()}',
            source: WalletActivitySource.bitcoinTransaction,
            operation: WalletActivityOperation.bitcoinReceive,
            asset: WalletAsset.bitcoin,
            rail: PaymentRail.onchain,
            direction: WalletActivityDirection.received,
            status: WalletActivityStatus.succeeded,
            amount: WalletAmount.onchain(
              assetId: WalletAsset.bitcoin.id,
              units: 10000000,
            ),
            occurredAt: _now,
            confirmedAt: _now,
            confirmationHeight: 417,
            txid: List.filled(64, 'a').join(),
          ),
        ]
        ..networkStatus = WalletNetworkStatus(
          environment: BlockchainEnvironment.regtest,
          blockHeight: 427,
          nodePublicKey: '020000000000000000000000000000000000000000000000000000000000000000',
          channelCount: 0,
          usableChannelCount: 0,
          peerCount: 0,
        );
      await tester.ensureVisible(find.byType(AssetRow).first);
      await tester.tap(find.byType(AssetRow).first);
      await _until(
        tester,
        () => h.container
            .read(activityViewModelProvider(WalletAssetKind.bitcoin))
            .hasValue,
      );
      await _until(
        tester,
        () => find.byType(TransactionListScreen).evaluate().isNotEmpty,
      );
      expect(
        find.bySemanticsLabel(RegExp('Received, on-chain, .*Completed')),
        findsOneWidget,
      );
      expect(
        h.homeUnits,
        0,
        reason: 'Activity must leave retained Home mounted.',
      );
      await tester.pump(const Duration(seconds: 65));
      expect(h.syncCount, 0, reason: 'A covered Home must not poll.');

      router.pop();
      await _until(tester, () => h.homeUnits == 10000000);
      await _until(
        tester,
        () => find.byType(TransactionListScreen).evaluate().isEmpty,
      );
      expect(h.syncCount, 1);
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a visible Home discovers a later receipt without a reload', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.pump(tester);
    await _until(tester, () => h.homeUnits == 0);
    expect(h.engine.calls.where((call) => call == 'balance'), hasLength(1));
    expect(h.syncCount, 0, reason: 'Initial loading must not double-read.');

    h.engine.balance = _balance(10000000);
    await tester.pump(const Duration(seconds: 31));
    await _until(tester, () => h.homeUnits == 10000000);
    expect(h.syncCount, 1);
  });

  testWidgets(
    'Home naturally publishes later confirmation after success Continue',
    (tester) async {
      final h = await _Harness.create(tester, rgb: true);
      h.engine.balance = _balance(99561);
      h.engine.balances[testRgbRoute.asset.id] = testRgbBalance(100);
      final router = GoRouter(
        initialLocation: '/test-home',
        routes: [
          GoRoute(path: '/test-home', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/submitted',
            builder: (context, _) => Scaffold(
              body: SendSuccessView(
                result: WalletSendResult(
                  route: testRgbRoute,
                  amount: WalletAmount.onchain(
                    assetId: testRgbRoute.asset.id,
                    units: 50,
                  ),
                  referenceId: List.filled(64, 'a').join(),
                  status: WalletPaymentStatus.pending,
                ),
                bitcoinUnit: BitcoinUnit.sats,
                onContinue: () => context.go('/test-home'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await h.pump(tester, router: router);
      await _until(tester, () => h.homeUnits == 99561 && h.rgbUnits == 100);
      unawaited(router.push<void>('/submitted'));
      await _until(
        tester,
        () => find.text('Payment sent').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
      await _until(
        tester,
        () =>
            find.text('Payment sent').evaluate().isEmpty &&
            h.container.read(homeViewModelProvider).value?.refreshing == false,
      );
      // Acceptance can precede recipient acknowledgement/broadcast and mining.
      expect(h.rgbUnits, 100);
      h.engine.balance = _balance(98305);
      h.engine.balances[testRgbRoute.asset.id] = testRgbBalance(50);
      expect(await h.harness.repository.sync(), isA<AppSuccess<void>>());
      expect(h.rgbUnits, 100, reason: 'Native reads do not mutate Home state.');

      await tester.pump(const Duration(seconds: 31));
      await _until(tester, () => h.homeUnits == 98305 && h.rgbUnits == 50);
      final rows = tester.widgetList<AssetRow>(find.byType(AssetRow)).toList();
      expect(
        rows
            .singleWhere((row) => row.kind == WalletAssetKind.bitcoin)
            .totalText,
        '98,305 sats',
      );
      expect(
        rows.singleWhere((row) => row.kind == WalletAssetKind.usdt).totalText,
        '0.00005 USDT',
      );
      expect(h.harness.toasts.messages, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained inactive tabs stop polling and refresh once on entry', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await h.pump(
      tester,
      child: ValueListenableBuilder<bool>(
        valueListenable: active,
        child: const HomeScreen(),
        builder: (_, value, child) => TickerMode(enabled: value, child: child!),
      ),
    );
    await _until(tester, () => h.homeUnits == 0);
    active.value = false;
    await tester.pump();
    h.engine.balance = _balance(10000000);
    await tester.pump(const Duration(seconds: 95));
    expect(h.syncCount, 0);
    expect(h.homeUnits, 0);

    active.value = true;
    await _until(tester, () => h.homeUnits == 10000000);
    expect(h.syncCount, 1);
  });

  testWidgets('OS resume waits for the confirmed native foreground state', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.pump(tester);
    await _until(tester, () => h.homeUnits == 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 60));
    expect(h.syncCount, 0);
    final lifecycle = h.container.read(
      walletLifecycleViewModelProvider.notifier,
    );
    await lifecycle.handle(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 60));
    expect(h.syncCount, 0, reason: 'Native resume has not been confirmed.');

    h.engine.balance = _balance(10000000);
    await lifecycle.handle(AppLifecycleState.resumed);
    await _until(tester, () => h.homeUnits == 10000000);
    expect(h.syncCount, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slow automatic refresh retains a return read without queuing polls',
    (tester) async {
      final h = await _Harness.create(tester);
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await h.pump(
        tester,
        child: ValueListenableBuilder<bool>(
          valueListenable: active,
          child: const HomeScreen(),
          builder: (_, value, child) =>
              TickerMode(enabled: value, child: child!),
        ),
      );
      await _until(tester, () => h.homeUnits == 0);
      final gate = Completer<void>();
      h.engine.syncGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await tester.pump(const Duration(seconds: 31));
      await _until(tester, () => h.syncCount == 1);
      expect(find.byTooltip('Updating balances'), findsNothing);
      expect(find.byTooltip('Refresh balances'), findsNothing);
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 95));
      expect(h.syncCount, 1, reason: 'No polls may queue behind a slow read.');

      h.engine.balance = _balance(10000000);
      h.engine.syncGate = null;
      gate.complete();
      await _until(tester, () => h.syncCount == 2);
      await _until(tester, () => h.homeUnits == 10000000);
      await tester.pump(const Duration(seconds: 1));
      expect(
        h.syncCount,
        2,
        reason: 'One deferred entry refresh owns one timer.',
      );
    },
  );

  for (final (label, syncFailure) in [
    ('transport', TimeoutException('private endpoint credential')),
    (
      'partial RGB witness refresh',
      const AppFailureException(
        AppFailure(
          code: 'wallet_sync_incomplete',
          kind: AppFailureKind.unavailable,
          userMessage: 'Wallet updates are unavailable. Try again.',
          retryable: true,
        ),
      ),
    ),
  ]) {
    testWidgets(
      'automatic $label failures silently retain amounts and recover',
      (tester) async {
        final h = await _Harness.create(tester);
        h.engine.balance = _balance(10000000);
        await h.pump(tester);
        await _until(tester, () => h.homeUnits == 10000000);
        h.engine.syncError = syncFailure;
        await tester.pump();
        await tester.pump(const Duration(seconds: 31));
        await _until(
          tester,
          () =>
              h.container.read(homeViewModelProvider).value?.refreshFailure !=
              null,
        );
        expect(h.homeUnits, 10000000);
        expect(
          find.textContaining('Balances may be out of date.'),
          findsNothing,
        );
        expect(find.textContaining('private endpoint'), findsNothing);
        expect(
          find.text('Wallet updates are unavailable. Try again.'),
          findsNothing,
        );
        expect(
          h.harness.toasts.messages,
          isEmpty,
          reason: 'No automatic toast spam.',
        );
        await tester.pump(const Duration(seconds: 31));
        await _until(tester, () => h.syncCount == 2);
        expect(h.homeUnits, 10000000);
        expect(h.harness.toasts.messages, isEmpty);

        h.engine.syncError = null;
        h.engine.balance = _balance(11000000);
        await tester.pump(const Duration(seconds: 31));
        await _until(tester, () => h.homeUnits == 11000000);
        expect(
          find.textContaining('Balances may be out of date.'),
          findsNothing,
        );
        expect(h.harness.toasts.messages, isEmpty);
      },
    );
  }

  testWidgets(
    'terminal initial errors expose no inert refresh command or poll',
    (tester) async {
      final h = await _Harness.create(tester);
      h.engine.balanceError = StateError('terminal private cause');
      await h.pump(tester);
      await _until(
        tester,
        () => h.container.read(homeViewModelProvider).hasError,
      );
      expect(find.byTooltip('Refresh balances'), findsNothing);
      await tester.pump(const Duration(seconds: 95));
      expect(h.syncCount, 0);
      expect(h.engine.calls.where((call) => call == 'balance'), hasLength(1));
    },
  );

  testWidgets('Android Home keeps its painted top fixed and bottom bounce', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    tester.view.physicalSize = const Size(390, 600);
    await h.pump(
      tester,
      child: Theme(
        data: AppTheme.light().copyWith(platform: TargetPlatform.android),
        child: const HomeScreen(),
      ),
    );
    await _until(tester, () => h.homeUnits == 0);
    await tester.pump(const Duration(seconds: 1));
    final scrollView = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(CustomScrollView),
        )
        .first;
    final scrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, position.minScrollExtent);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byTooltip('Refresh balances'), findsNothing);

    expect(find.byType(StretchingOverscrollIndicator), findsWidgets);
    final actions = find.byType(HomeActionButtons);
    final paintedActionsBefore = tester.getRect(actions);
    final topDrag = await tester.startGesture(tester.getCenter(scrollView));
    await topDrag.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await topDrag.moveBy(const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, position.minScrollExtent);
    expect(
      tester.getRect(actions),
      paintedActionsBefore,
      reason: 'Android stretch must not move or scale the clamped top content.',
    );
    await topDrag.up();
    await tester.pump(const Duration(seconds: 1));

    expect(position.maxScrollExtent, greaterThan(position.minScrollExtent));
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.fling(scrollView, const Offset(0, 900), 3000);
    for (var frame = 0; frame < 80; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(position.pixels, greaterThanOrEqualTo(position.minScrollExtent));
    }

    position.jumpTo(position.maxScrollExtent);
    final bottomDrag = await tester.startGesture(tester.getCenter(scrollView));
    await bottomDrag.moveBy(const Offset(0, -40));
    await tester.pump();
    await bottomDrag.moveBy(const Offset(0, -180));
    await tester.pump();
    expect(position.pixels, greaterThan(position.maxScrollExtent));
    await bottomDrag.up();
    await tester.pump(const Duration(seconds: 2));
    expect(
      h.syncCount,
      0,
      reason: 'Overscroll never requests a balance refresh.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal during a refresh never rearms the timer', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.pump(tester);
    await _until(tester, () => h.homeUnits == 0);
    final gate = Completer<void>();
    h.engine.syncGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pump(const Duration(seconds: 31));
    await _until(tester, () => h.syncCount == 1);
    await tester.pumpWidget(const SizedBox.shrink());
    h.engine.syncGate = null;
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 95));
    expect(h.syncCount, 1);
    expect(tester.takeException(), isNull);
  });
}

final _now = DateTime.utc(2026, 10, 16, 12);

WalletBalance _balance(int units) {
  final asset = WalletAsset.bitcoin;
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  final lightning = WalletAmount.lightning(assetId: asset.id, units: 0);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(units),
    onchainFuture: onchain(units),
    onchainSpendable: onchain(units),
    onchainLocked: onchain(0),
    lightningOwned: lightning,
    lightningSpendable: lightning,
    lightningReceivable: lightning,
  );
}

final class _Harness {
  _Harness(this.harness);

  final PaymentFlowTestHarness harness;
  ProviderContainer get container => harness.container;
  FakeWalletEngine get engine => harness.engine;
  int get syncCount => engine.calls.where((call) => call == 'sync').length;
  int? get homeUnits => container
      .read(homeViewModelProvider)
      .value
      ?.portfolio
      .bitcoin
      .onchainSettled
      .units;
  int? get rgbUnits => container
      .read(homeViewModelProvider)
      .value
      ?.portfolio
      .usdt
      ?.onchainSettled
      .units;

  static Future<_Harness> create(
    WidgetTester tester, {
    bool rgb = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = ResilientHttpClient(
      retryPolicy: RetryPolicy(maxAttempts: 1),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            jsonEncode({
              'prices': [
                [
                  _now
                      .subtract(const Duration(hours: 24))
                      .millisecondsSinceEpoch,
                  99000,
                ],
                [_now.millisecondsSinceEpoch, 100000],
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'bitcoin': {
              'usd': 100000,
              'last_updated_at': _now.millisecondsSinceEpoch ~/ 1000,
            },
          }),
          200,
        );
      }),
    );
    final harness = await PaymentFlowTestHarness.create(
      engine: FakeWalletEngine()..balance = _balance(0),
      services: rgb
          ? testRgbServices
          : const WalletServiceConfiguration(
              environment: BlockchainEnvironment.regtest,
              sdkNetwork: 'regtest',
            ),
      clock: () => _now,
      httpClient: client,
      preferenceValues: const {'aster.settings.v1.bitcoin_unit': 'sats'},
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final disposal = harness.dispose();
      await tester.pump();
      await disposal;
      client.close();
    });
    return _Harness(harness);
  }

  Future<void> pump(
    WidgetTester tester, {
    GoRouter? router,
    Widget child = const HomeScreen(),
  }) {
    Widget feedback(BuildContext context, Widget child) => AsterFeedbackScope(
      haptics: harness.haptics,
      toasts: harness.toasts,
      child: child,
    );
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: router == null
            ? MaterialApp(
                theme: AppTheme.light(),
                home: Builder(builder: (context) => feedback(context, child)),
              )
            : MaterialApp.router(
                theme: AppTheme.light(),
                routerConfig: router,
                builder: (context, child) => feedback(context, child!),
              ),
      ),
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame += 1) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Home refresh did not reach the expected state.');
}
