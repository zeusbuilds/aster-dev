import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/screens/screens.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home renders totals, persists visibility, and hides semantics', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final engine = FakeWalletEngine()..balance = _bitcoinBalance();
    final httpClient = _marketClient(now);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
      httpClient: httpClient,
      preferenceValues: const {'utexo.settings.v1.bitcoin_unit': 'sats'},
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => find.text('1,001.5 sats').evaluate().isNotEmpty,
    );

    expect(find.text('Available 901.25 sats'), findsOneWidget);
    expect(find.text(r'$1.00 USD estimated'), findsOneWidget);
    expect(find.text('Powered by CoinGecko'), findsOneWidget);
    expect(find.text('Unavailable on this network'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide balances'));
    await _pumpUntil(
      tester,
      () => find.byTooltip('Show balances').evaluate().isNotEmpty,
    );

    expect(find.text('1,001.5 sats'), findsNothing);
    expect(find.bySemanticsLabel('Bitcoin balance hidden'), findsOneWidget);
    expect(harness.haptics.intents.last, HapticIntent.selection);
    final settings = await harness.container.read(
      settingsRepositoryProvider.future,
    );
    final persisted = await settings.load();
    expect(persisted, isA<AppSuccess<SettingsSnapshot>>());
    expect(
      (persisted as AppSuccess<SettingsSnapshot>)
          .value
          .preferences
          .balancesVisible,
      isFalse,
    );
  });

  testWidgets('Home remains scrollable and accessible at 2x text scale', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final httpClient = _marketClient(now);
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(
      tester,
      harness,
      const HomeScreen(),
      textScaler: const TextScaler.linear(2),
    );
    await _pumpUntil(tester, () => find.text('Assets').evaluate().isNotEmpty);

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('fiat loading preserves loaded crypto balances', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AssetRow(
            kind: WalletAssetKind.bitcoin,
            title: 'Bitcoin',
            totalText: '1,001 sats',
            availableText: '900 sats',
            fiatContext: 'USD estimate unavailable',
            balancesVisible: true,
            fiatLoading: true,
          ),
        ),
      ),
    );

    expect(find.text('1,001 sats'), findsOneWidget);
    expect(
      tester
          .widgetList<AppSkeletonizer>(find.byType(AppSkeletonizer))
          .map((widget) => widget.enabled),
      [false, true, false],
    );
    expect(
      find.bySemanticsLabel(
        'Bitcoin total 1,001 sats, available 900 sats, '
        'fiat estimate loading',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home advances through independent asset quote expiries', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 11, 12);
    final bitcoinObservedAt = clockNow.subtract(
      BitcoinMarketSnapshot.maximumCurrentAge - const Duration(seconds: 3),
    );
    final usdtObservedAt = clockNow.subtract(
      BitcoinMarketSnapshot.maximumCurrentAge - const Duration(seconds: 1),
    );
    const assetConfiguration = RgbAssetConfiguration(
      contractId: 'contract-id',
      precision: 2,
    );
    final usdt = WalletAsset.rgbUsdt(
      assetId: assetConfiguration.contractId,
      precision: assetConfiguration.precision,
    );
    final engine = FakeWalletEngine()
      ..balances[WalletAsset.bitcoin.id] = _bitcoinBalance()
      ..balances[usdt.id] = _usdtBalance(usdt);
    final httpClient = _marketClientWithAssetTimestamps(
      now: clockNow,
      bitcoinObservedAt: bitcoinObservedAt,
      usdtObservedAt: usdtObservedAt,
    );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => clockNow,
      httpClient: httpClient,
      services: const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: assetConfiguration,
      ),
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => find.text(r'$125.00 USD estimated').evaluate().isNotEmpty,
    );
    expect(find.text(r'$1.00 USD estimated'), findsOneWidget);
    expect(find.text('Retry fiat quote'), findsNothing);

    clockNow = clockNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(r'$1.00 USD estimated'), findsOneWidget);
    expect(find.text('USD estimate unavailable'), findsOneWidget);
    expect(find.text('Retry fiat quote'), findsOneWidget);

    clockNow = clockNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(r'$1.00 USD estimated'), findsNothing);
    expect(find.text('USD estimate unavailable'), findsNWidgets(2));
    expect(find.text('Market quote expired'), findsOneWidget);
  });

  testWidgets('Home Send shortcut opens the target selector', (tester) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final httpClient = _marketClient(now);
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = GoRouter(
      initialLocation: '/test-home',
      routes: [
        GoRoute(
          path: '/test-home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: RoutePaths.send,
          builder: (context, state) => const Text('Send target selector'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);

    await tester.tap(find.widgetWithText(CustomButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.text('Send target selector'), findsOneWidget);
  });

  testWidgets('market header preserves loading geometry and signed semantics', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final observed = now.subtract(const Duration(minutes: 1));
    final historyGate = Completer<http.Response>();
    final currentGate = Completer<http.Response>();
    final httpClient = ResilientHttpClient(
      client: MockClient((request) {
        return request.url.path.endsWith('/range')
            ? historyGate.future
            : currentGate.future;
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => find
          .bySemanticsLabel('Bitcoin price loading. Powered by CoinGecko.')
          .evaluate()
          .isNotEmpty,
    );
    final loadingSize = tester.getSize(find.byType(PriceCard));
    expect(
      tester
          .widgetList<AppSkeletonizer>(
            find.descendant(
              of: find.byType(PriceCard),
              matching: find.byType(AppSkeletonizer),
            ),
          )
          .any((widget) => widget.enabled),
      isTrue,
    );
    expect(find.bySemanticsLabel(RegExp('000,000')), findsNothing);

    historyGate.complete(
      _historyResponse(now: now, firstPrice: 99000, lastPrice: 100000),
    );
    currentGate.complete(
      _currentResponse(observedAt: observed, bitcoinPrice: 100000),
    );
    const loadedLabel =
        r'Bitcoin price $100,000.00 USD. up 1.0% over 24 hours. '
        'Powered by CoinGecko.';
    await _pumpUntil(
      tester,
      () => find.bySemanticsLabel(loadedLabel).evaluate().isNotEmpty,
    );

    expect(tester.getSize(find.byType(PriceCard)), loadingSize);
    final percentage = find.byWidgetPredicate(
      (widget) => widget is NumericText && widget.text == '1.0%',
    );
    expect(percentage, findsOneWidget);
    final richText = tester.widget<Text>(
      find.descendant(of: percentage, matching: find.byType(Text)),
    );
    final spans = (richText.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['1.0', '%']);
    expect(spans.map((span) => span.style?.fontFamily), [
      'Public Sans',
      'DM Sans',
    ]);
  });

  testWidgets('market header announces falling and unavailable prices', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final fallingClient = _marketClient(
      now,
      firstPrice: 99000,
      bitcoinPrice: 98000,
    );
    final fallingHarness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: fallingClient,
    );
    await _pump(tester, fallingHarness, const HomeScreen());
    const fallingLabel =
        r'Bitcoin price $98,000.00 USD. down 1.0% over 24 hours. '
        'Powered by CoinGecko.';
    await _pumpUntil(
      tester,
      () => find.bySemanticsLabel(fallingLabel).evaluate().isNotEmpty,
    );
    await _disposeHarness(tester, fallingHarness);
    fallingClient.close();

    final unavailableClient = ResilientHttpClient(
      client: MockClient((request) async => http.Response('unavailable', 503)),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    final unavailableHarness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: unavailableClient,
    );
    addTearDown(unavailableClient.close);
    addTearDown(() => _disposeHarness(tester, unavailableHarness));
    await _pump(tester, unavailableHarness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => find
          .bySemanticsLabel('Bitcoin price unavailable. Powered by CoinGecko.')
          .evaluate()
          .isNotEmpty,
    );
  });

  testWidgets('home mesh blurs its own content without a backdrop capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: MeshGradientBackground()),
      ),
    );

    final mesh = find.byType(MeshGradientBackground);
    expect(mesh, findsOneWidget);
    expect(
      find.descendant(of: mesh, matching: find.byType(ImageFiltered)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mesh, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: mesh, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    expect(
      find.descendant(of: mesh, matching: find.byType(AsterNoiseTexture)),
      findsOneWidget,
    );
    final noiseImage = tester.widget<Image>(
      find.descendant(of: mesh, matching: find.byType(Image)),
    );
    expect(noiseImage.image, isA<ResizeImage>());
    final resizedNoise = noiseImage.image as ResizeImage;
    expect(resizedNoise.width, inInclusiveRange(1, 1600));
    expect(resizedNoise.height, isNull);
    expect(tester.takeException(), isNull);
  });
}

ResilientHttpClient _marketClient(
  DateTime now, {
  int firstPrice = 99000,
  int bitcoinPrice = 100000,
}) {
  final observed = now.subtract(const Duration(minutes: 1));
  return ResilientHttpClient(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(
          now: now,
          firstPrice: firstPrice,
          lastPrice: bitcoinPrice,
        );
      }
      return _currentResponse(observedAt: observed, bitcoinPrice: bitcoinPrice);
    }),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
}

http.Response _historyResponse({
  required DateTime now,
  required int firstPrice,
  required int lastPrice,
}) {
  return http.Response(
    jsonEncode({
      'prices': [
        [
          now
              .subtract(BitcoinMarketSnapshot.historyWindow)
              .millisecondsSinceEpoch,
          firstPrice,
        ],
        [
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
          lastPrice,
        ],
      ],
    }),
    200,
  );
}

http.Response _currentResponse({
  required DateTime observedAt,
  required int bitcoinPrice,
}) {
  return http.Response(
    jsonEncode({
      'bitcoin': {
        'usd': bitcoinPrice,
        'last_updated_at': observedAt.millisecondsSinceEpoch ~/ 1000,
      },
    }),
    200,
  );
}

ResilientHttpClient _marketClientWithAssetTimestamps({
  required DateTime now,
  required DateTime bitcoinObservedAt,
  required DateTime usdtObservedAt,
}) {
  return ResilientHttpClient(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/range')) {
        return http.Response(
          jsonEncode({
            'prices': [
              [
                now
                    .subtract(BitcoinMarketSnapshot.historyWindow)
                    .millisecondsSinceEpoch,
                99000,
              ],
              [bitcoinObservedAt.millisecondsSinceEpoch, 100000],
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 100000,
            'last_updated_at': bitcoinObservedAt.millisecondsSinceEpoch ~/ 1000,
          },
          'tether': {
            'usd': 1,
            'last_updated_at': usdtObservedAt.millisecondsSinceEpoch ~/ 1000,
          },
        }),
        200,
      );
    }),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
}

WalletBalance _bitcoinBalance() {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(1000),
    onchainFuture: onchain(1000),
    onchainSpendable: onchain(900),
    onchainLocked: onchain(100),
    lightningOwned: lightning(1500),
    lightningSpendable: lightning(1250),
    lightningReceivable: lightning(0),
  );
}

WalletBalance _usdtBalance(WalletAsset asset) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: asset.id, units: units);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(10000),
    onchainFuture: onchain(10000),
    onchainSpendable: onchain(9000),
    onchainLocked: onchain(1000),
    lightningOwned: lightning(2500),
    lightningSpendable: lightning(2000),
    lightningReceivable: lightning(0),
  );
}

Future<void> _pump(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
  Widget child, {
  TextScaler? textScaler,
}) {
  _configurePhone(tester);
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            final content = AsterFeedbackScope(
              haptics: harness.haptics,
              toasts: harness.toasts,
              child: child,
            );
            return textScaler == null
                ? content
                : MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: textScaler),
                    child: content,
                  );
          },
        ),
      ),
    ),
  );
}

Future<void> _pumpRouter(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
  GoRouter router,
) {
  _configurePhone(tester);
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: harness.toasts,
          child: child!,
        ),
      ),
    ),
  );
}

void _configurePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var frame = 0; frame < 200; frame += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for Home UI state.');
}

Future<void> _disposeHarness(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final disposal = harness.dispose();
  await tester.pump();
  await disposal;
}
