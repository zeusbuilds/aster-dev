import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/screens/screens.dart';
import 'package:aster/features/home/presentation/widgets/candle_chart.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remixicon/remixicon.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
    await (FontLoader(
      'Public Sans',
    )..addFont(rootBundle.load('assets/fonts/PublicSans-Variable.ttf'))).load();
  });

  testWidgets('hidden balance values align with the asset row trailing edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: AssetRow(
                kind: WalletAssetKind.bitcoin,
                title: 'Bitcoin',
                totalText: '1 sats',
                availableText: '1 sats',
                fiatContext: r'$0.00',
                balancesVisible: false,
              ),
            ),
          ),
        ),
      ),
    );
    final rowRight = tester.getRect(find.byType(AssetRow)).right;
    final masks = find.byWidgetPredicate(
      (widget) => widget is AmountText && widget.text == '••••',
    );
    expect(masks, findsNWidgets(2));
    for (final mask in masks.evaluate()) {
      expect(
        tester
            .getRect(find.byElementPredicate((element) => element == mask))
            .right,
        rowRight,
      );
    }
  });

  testWidgets('Home loading surfaces announce one truthful status each', (
    tester,
  ) async {
    final wallet = Completer<WalletState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletViewModelProvider.overrideWith(
            () => _PendingWalletViewModel(wallet.future),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AsterNavigationScope(child: Scaffold(body: HomeHeader())),
        ),
      ),
    );

    final walletLoading = find.bySemanticsLabel('Loading active wallet');
    expect(walletLoading, findsOneWidget);
    expect(
      tester.getSemantics(walletLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.bySemanticsLabel('Wallet unavailable'), findsNothing);
    wallet.complete(WalletState());
    await tester.pump();

    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(
      tester,
      harness,
      const Scaffold(body: AssetsSection(home: AsyncLoading())),
    );
    final balancesLoading = find.bySemanticsLabel('Loading asset balances');
    expect(balancesLoading, findsOneWidget);
    expect(
      tester.getSemantics(balancesLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.bySemanticsLabel(RegExp('Bitcoin total')), findsNothing);
  });

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
      preferenceValues: const {'aster.settings.v1.bitcoin_unit': 'sats'},
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => find.text('1,001.5 sats').evaluate().isNotEmpty,
    );

    expect(find.text('Available 901.25 sats'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Bitcoin total .*available 901.25 sats')),
      findsOneWidget,
    );
    expect(find.text(r'≈ $1.00'), findsOneWidget);
    expect(find.text('Powered by CoinGecko'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('CoinGecko')), findsNothing);
    expect(find.text('Unavailable on this network'), findsNothing);
    expect(find.text('Not configured'), findsNothing);
    expect(
      tester.widgetList<AssetRow>(find.byType(AssetRow)).map((row) => row.kind),
      [WalletAssetKind.bitcoin],
    );

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

  testWidgets(
    'Home suppresses false feedback from a stale visibility completion',
    (tester) async {
      final now = DateTime.utc(2026, 8, 11, 12);
      final preferencesWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      final httpClient = _marketClient(now);
      final harness = await PaymentFlowTestHarness.create(
        clock: () => now,
        httpClient: httpClient,
        preferenceValues: const {'aster.settings.v1.balances_visible': true},
        preferenceServiceBuilder: (preferences) =>
            _BlockingVisibilityPreferencesService(
              preferences,
              writeStarted: preferencesWrite,
              releaseWrite: releaseWrite,
            ),
      );
      addTearDown(httpClient.close);
      addTearDown(() => _disposeHarness(tester, harness));
      await _pump(tester, harness, const HomeScreen());
      final enabledVisibilityButton = find.byWidgetPredicate(
        (widget) =>
            widget is AsterIconButton &&
            widget.tooltip == 'Hide balances' &&
            widget.onPressed != null,
      );
      await _pumpUntil(
        tester,
        () => enabledVisibilityButton.evaluate().isNotEmpty,
      );

      final visibilityButton = tester.widget<AsterIconButton>(
        enabledVisibilityButton,
      );
      visibilityButton.onPressed!();
      await preferencesWrite.future;
      harness.container.invalidate(settingsViewModelProvider);
      await tester.pump();
      releaseWrite.complete();
      await _pumpUntil(
        tester,
        () => find.byTooltip('Show balances').evaluate().isNotEmpty,
      );

      expect(harness.haptics.intents, isEmpty);
      expect(harness.toasts.messages, isEmpty);
    },
  );

  testWidgets('Home has no pull-to-refresh affordance', (tester) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final httpClient = _marketClient(now);
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(tester, () => find.text('Assets').evaluate().isNotEmpty);

    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);
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
    expect(find.text('USD estimate unavailable'), findsNothing);
    expect(
      tester
          .widgetList<AppSkeletonizer>(find.byType(AppSkeletonizer))
          .map((widget) => widget.enabled),
      [true, false],
    );
    expect(
      find.bySemanticsLabel(
        'Bitcoin total 1,001 sats, available 900 sats, '
        'fiat estimate loading',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unavailable fiat stays hidden when balances are hidden', (
    tester,
  ) async {
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
            balancesVisible: false,
            fiatLoading: true,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Bitcoin balance hidden'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('fiat estimate')), findsNothing);
    expect(find.text('1,001 sats'), findsNothing);
    expect(find.text('USD estimate unavailable'), findsNothing);
    expect(
      tester
          .widgetList<AppSkeletonizer>(find.byType(AppSkeletonizer))
          .any((widget) => widget.enabled),
      isFalse,
    );
  });

  testWidgets('a configured zero-balance asset remains in Home', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final engine = FakeWalletEngine()
      ..balances[testRgbRoute.asset.id] = testRgbBalance(0);
    final httpClient = _marketClient(now);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
      httpClient: httpClient,
      services: testRgbServices,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(tester, harness, const HomeScreen());
    await _pumpUntil(
      tester,
      () => _assetRow(WalletAssetKind.usdt).evaluate().isNotEmpty,
    );

    final row = tester.widget<AssetRow>(_assetRow(WalletAssetKind.usdt));
    expect(row.totalText, '0 USDT');
    expect(row.onTap, isNotNull);
    expect(find.text('Not configured'), findsNothing);
  });

  testWidgets(
    'missing asset fiat shimmers independently, recovers, and retains good quotes',
    (tester) async {
      final now = DateTime.utc(2026, 8, 11, 12);
      const configuration = RgbAssetConfiguration(
        contractId: 'contract-id',
        precision: 2,
      );
      final usdt = WalletAsset.rgbUsdt(
        assetId: configuration.contractId,
        precision: configuration.precision,
      );
      final engine = FakeWalletEngine()
        ..balances[WalletAsset.bitcoin.id] = _bitcoinBalance()
        ..balances[usdt.id] = _usdtBalance(usdt);
      var includeUsdt = false;
      var failRequests = false;
      final httpClient = ResilientHttpClient(
        client: MockClient((request) async {
          if (failRequests) return http.Response('unavailable', 503);
          if (request.url.path.endsWith('/range')) {
            return _historyResponse(
              now: now,
              firstPrice: 99000,
              lastPrice: 100000,
            );
          }
          return _currentResponse(
            observedAt: now.subtract(const Duration(minutes: 1)),
            bitcoinPrice: 100000,
            usdtPrice: includeUsdt ? 1 : null,
          );
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
        httpClient: httpClient,
        services: const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          usdtAsset: configuration,
        ),
      );
      addTearDown(httpClient.close);
      addTearDown(() => _disposeHarness(tester, harness));
      await _pump(tester, harness, const HomeScreen());
      await _pumpUntil(
        tester,
        () => find.text(r'≈ $1.00').evaluate().isNotEmpty,
      );

      _expectFiatLoading(tester, WalletAssetKind.bitcoin, false);
      _expectFiatLoading(tester, WalletAssetKind.usdt, true);
      expect(find.text('125 USDT'), findsOneWidget);
      expect(find.text('USD estimate unavailable'), findsNothing);
      expect(find.text('Retry fiat quote'), findsNothing);

      includeUsdt = true;
      final recovery = harness.container
          .read(bitcoinMarketViewModelProvider.notifier)
          .retry();
      await tester.runAsync(() => recovery);
      await tester.pump();

      expect(find.text(r'≈ $125.00'), findsOneWidget);
      _expectFiatLoading(tester, WalletAssetKind.usdt, false);

      failRequests = true;
      final failedRefresh = harness.container
          .read(bitcoinMarketViewModelProvider.notifier)
          .retry();
      await tester.runAsync(() => failedRefresh);
      await tester.pump();

      expect(
        harness.container
            .read(bitcoinMarketViewModelProvider)
            .requireValue
            .refreshFailure,
        isNotNull,
      );
      expect(find.text(r'≈ $1.00'), findsOneWidget);
      expect(find.text(r'≈ $125.00'), findsOneWidget);
      _expectFiatLoading(tester, WalletAssetKind.bitcoin, false);
      _expectFiatLoading(tester, WalletAssetKind.usdt, false);
      expect(find.text('Retry fiat quote'), findsNothing);
      expect(harness.toasts.messages, isEmpty);
    },
  );

  testWidgets('Home advances through independent asset quote expiries', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 11, 12);
    Future<void> advanceTwoSeconds() async {
      // Keep the injected wall clock aligned with timer callbacks. A single
      // large pump would make a callback at 1s observe 2s and could fire its
      // newly scheduled timer inside that same pump while the clock stays 2s.
      for (var quarter = 0; quarter < 8; quarter += 1) {
        clockNow = clockNow.add(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

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
    var marketRequestCount = 0;
    final engine = FakeWalletEngine()
      ..balances[WalletAsset.bitcoin.id] = _bitcoinBalance()
      ..balances[usdt.id] = _usdtBalance(usdt);
    final httpClient = _marketClientWithAssetTimestamps(
      now: clockNow,
      bitcoinObservedAt: bitcoinObservedAt,
      usdtObservedAt: usdtObservedAt,
      onRequest: () => marketRequestCount += 1,
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
      () => find.text(r'≈ $125.00').evaluate().isNotEmpty,
    );
    expect(find.text(r'≈ $1.00'), findsOneWidget);
    _expectFiatLoading(tester, WalletAssetKind.bitcoin, false);
    _expectFiatLoading(tester, WalletAssetKind.usdt, false);
    expect(find.text('Retry fiat quote'), findsNothing);

    await advanceTwoSeconds();
    expect(find.text(r'≈ $1.00'), findsOneWidget);
    _expectFiatLoading(tester, WalletAssetKind.bitcoin, false);
    _expectFiatLoading(tester, WalletAssetKind.usdt, true);
    expect(find.text('USD estimate unavailable'), findsNothing);
    expect(find.text('Retry fiat quote'), findsNothing);
    await advanceTwoSeconds();
    await _pumpUntil(
      tester,
      () =>
          find.bySemanticsLabel('Bitcoin price loading.').evaluate().isNotEmpty,
    );
    expect(find.text(r'≈ $1.00'), findsNothing);
    _expectFiatLoading(tester, WalletAssetKind.bitcoin, true);
    _expectFiatLoading(tester, WalletAssetKind.usdt, true);
    expect(find.text('USD estimate unavailable'), findsNothing);
    expect(find.text('Retry fiat quote'), findsNothing);
    expect(find.text('Market quote expired'), findsNothing);
    expect(
      tester
          .widgetList<CandleChart>(find.byType(CandleChart))
          .single
          .isSkeleton,
      isTrue,
    );
    await _pumpUntil(tester, () => marketRequestCount > 2);
  });

  testWidgets('Home owns one cross-control navigation command', (tester) async {
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
        GoRoute(
          path: RoutePaths.receive,
          builder: (context, state) => const Text('Receive target selector'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);

    final send = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Send'),
    );
    final receive = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Receive'),
    );
    send.onTap!();
    receive.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Send target selector'), findsOneWidget);
    expect(find.text('Receive target selector'), findsNothing);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('price trends consume dedicated chart color roles', (
    tester,
  ) async {
    await _expectPriceChangeColor(
      tester,
      firstPrice: 99000,
      bitcoinPrice: 100000,
      icon: RemixIcons.arrow_up_line,
      expectedColor: const Color(0xFF123456),
    );
    await _expectPriceChangeColor(
      tester,
      firstPrice: 101000,
      bitcoinPrice: 100000,
      icon: RemixIcons.arrow_down_line,
      expectedColor: const Color(0xFF654321),
    );
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
      () =>
          find.bySemanticsLabel('Bitcoin price loading.').evaluate().isNotEmpty,
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
        r'Bitcoin price $100,000.00 USD. up 1.01% over 24 hours.';
    await _pumpUntil(
      tester,
      () => find.bySemanticsLabel(loadedLabel).evaluate().isNotEmpty,
    );

    expect(tester.getSize(find.byType(PriceCard)), loadingSize);
    final percentage = find.byWidgetPredicate(
      (widget) => widget is NumericText && widget.text == '1.01%',
    );
    expect(percentage, findsOneWidget);
    final headline = find.byWidgetPredicate(
      (widget) => widget is NumericText && widget.text == r'$100,000',
    );
    expect(headline, findsOneWidget);
    expect(tester.widget<NumericText>(headline).textAlign, TextAlign.end);
    final headlineFittedBox = find.ancestor(
      of: headline,
      matching: find.byType(FittedBox),
    );
    expect(headlineFittedBox, findsOneWidget);
    expect(
      tester.widget<FittedBox>(headlineFittedBox).alignment,
      Alignment.centerRight,
    );
    final priceCardContext = tester.element(find.byType(PriceCard));
    final headlineParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: headline, matching: find.byType(RichText)),
    );
    final headlineBoxes = headlineParagraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
    final paintedRight = headlineBoxes
        .map(
          (box) =>
              headlineParagraph.localToGlobal(Offset(box.right, box.bottom)).dx,
        )
        .reduce((left, right) => left > right ? left : right);
    final expectedRight =
        tester.getRect(find.byType(PriceCard)).right -
        priceCardContext.spacing.screenPadding;
    expect(
      tester.getRect(headline).right,
      moreOrLessEquals(expectedRight, epsilon: 0.5),
    );
    expect(paintedRight, moreOrLessEquals(expectedRight, epsilon: 0.5));
    final richText = tester.widget<Text>(
      find.descendant(of: percentage, matching: find.byType(Text)),
    );
    final spans = (richText.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['1.01', '%']);
    expect(spans.map((span) => span.style?.fontFamily), [
      'Public Sans',
      'DM Sans',
    ]);
  });

  testWidgets('market refresh is silent and retains confirmed content', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var requestCount = 0;
    final httpClient = ResilientHttpClient(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount > 2) {
          if (requestCount == 4 && !refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await releaseRefresh.future;
          return http.Response('temporarily unavailable', 503);
        }
        if (request.url.path.endsWith('/range')) {
          return _historyResponse(
            now: now,
            firstPrice: 99000,
            lastPrice: 100000,
          );
        }
        return _currentResponse(
          observedAt: now.subtract(const Duration(minutes: 1)),
          bitcoinPrice: 100000,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
      clock: () => now,
    );
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(() {
      if (!releaseRefresh.isCompleted) releaseRefresh.complete();
      httpClient.close();
    });
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(
      tester,
      harness,
      const PriceCard(),
      textScaler: const TextScaler.linear(2),
    );
    const loadedLabel =
        r'Bitcoin price $100,000.00 USD. up 1.01% over 24 hours.';
    await _pumpUntil(
      tester,
      () => find.bySemanticsLabel(loadedLabel).evaluate().isNotEmpty,
    );

    final refresh = harness.container
        .read(bitcoinMarketViewModelProvider.notifier)
        .retry();
    await refreshStarted.future;
    await tester.pump();

    expect(find.bySemanticsLabel(loadedLabel), findsOneWidget);
    expect(find.text('Refreshing market data'), findsNothing);
    expect(
      tester
          .widgetList<AppSkeletonizer>(
            find.descendant(
              of: find.byType(PriceCard),
              matching: find.byType(AppSkeletonizer),
            ),
          )
          .any((widget) => widget.enabled),
      isFalse,
    );

    releaseRefresh.complete();
    await tester.runAsync(() => refresh);
    await tester.pump();
    final failure = harness.container
        .read(bitcoinMarketViewModelProvider)
        .requireValue
        .refreshFailure!;

    expect(find.bySemanticsLabel(loadedLabel), findsOneWidget);
    expect(find.text(failure.userMessage), findsNothing);
    expect(find.byTooltip('Retry market refresh'), findsNothing);
  });

  testWidgets('market header preserves exact basis-point precision', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final httpClient = _marketClient(
      now,
      firstPrice: 100000,
      bitcoinPrice: 100190,
    );
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, const HomeScreen());

    await _pumpUntil(tester, () => find.text('0.19%').evaluate().isNotEmpty);
    expect(
      find.bySemanticsLabel(RegExp(r'up 0\.19% over 24 hours')),
      findsOneWidget,
    );
  });

  testWidgets('market header renders an exact zero change as neutral', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final httpClient = _marketClient(
      now,
      firstPrice: 100000,
      bitcoinPrice: 100000,
    );
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, const HomeScreen());

    const unchangedLabel =
        r'Bitcoin price $100,000.00 USD. unchanged at 0.0% over 24 hours.';
    await _pumpUntil(
      tester,
      () => find.bySemanticsLabel(unchangedLabel).evaluate().isNotEmpty,
    );
    final priceCard = find.byType(PriceCard);
    expect(
      find.descendant(
        of: priceCard,
        matching: find.byIcon(RemixIcons.subtract_line),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: priceCard,
        matching: find.byIcon(RemixIcons.arrow_up_line),
      ),
      findsNothing,
    );
    final percentage = find.byWidgetPredicate(
      (widget) => widget is NumericText && widget.text == '0.0%',
    );
    final percentageWidget = tester.widget<NumericText>(percentage);
    final percentageContext = tester.element(percentage);
    expect(
      percentageWidget.style?.color,
      percentageContext.type.brandMetric.color,
    );
    expect(find.bySemanticsLabel(unchangedLabel), findsOneWidget);
  });

  testWidgets('market header announces falling and silently loads on failure', (
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
        r'Bitcoin price $98,000.00 USD. down 1.01% over 24 hours.';
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
      () =>
          find.bySemanticsLabel('Bitcoin price loading.').evaluate().isNotEmpty,
    );
    final market = unavailableHarness.container
        .read(bitcoinMarketViewModelProvider)
        .requireValue;
    expect(market.snapshot, isNull);
    expect(market.refreshFailure?.kind, AppFailureKind.unavailable);
    expect(find.text(market.refreshFailure!.userMessage), findsNothing);
    expect(find.text("You're offline"), findsNothing);
    expect(
      tester
          .widgetList<CandleChart>(find.byType(CandleChart))
          .single
          .isSkeleton,
      isTrue,
    );
    expect(
      tester
          .widgetList<AppSkeletonizer>(
            find.descendant(
              of: find.byType(PriceCard),
              matching: find.byType(AppSkeletonizer),
            ),
          )
          .every((skeleton) => skeleton.enabled),
      isTrue,
    );
    expect(find.byType(GridLoader), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('offline history replaces only the chart and tap retries', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    var offline = true;
    final httpClient = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          if (offline) throw const SocketException('offline');
          return _historyResponse(
            now: now,
            firstPrice: 99000,
            lastPrice: 100000,
          );
        }
        return _currentResponse(
          observedAt: now.subtract(const Duration(minutes: 1)),
          bitcoinPrice: 100000,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    final harness = await PaymentFlowTestHarness.create(
      clock: () => now,
      httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      const PriceCard(),
      textScaler: const TextScaler.linear(2),
    );
    await _pumpUntil(
      tester,
      () => find.text("You're offline").evaluate().isNotEmpty,
    );

    expect(find.text(r'$100,000'), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Tap to try again'), findsOneWidget);
    expect(
      find.bySemanticsLabel("You're offline. Tap to try again."),
      findsOneWidget,
    );
    expect(find.text('Check your connection and try again.'), findsNothing);
    expect(tester.takeException(), isNull);

    offline = false;
    await tester.tap(find.text('Tap to try again'));
    await _pumpUntil(
      tester,
      () =>
          find.byType(CandleChart).evaluate().isNotEmpty &&
          tester.widget<CandleChart>(find.byType(CandleChart)).isSkeleton ==
              false,
    );

    expect(find.text("You're offline"), findsNothing);
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

  testWidgets('chart preserves integer deltas above double precision', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 14, 12);
    const maximumSignedInteger = 0x7fffffffffffffff;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CandleChart(
            isSkeleton: false,
            data: [
              BitcoinPricePoint(
                timestamp: now.subtract(const Duration(hours: 1)),
                fiatMinorUnits: maximumSignedInteger - 1,
              ),
              BitcoinPricePoint(
                timestamp: now,
                fiatMinorUnits: maximumSignedInteger,
              ),
            ],
          ),
        ),
      ),
    );

    final candleBoxes = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(CandleChart),
            matching: find.byType(SizedBox),
          ),
        )
        .where(
          (box) =>
              (box.width ?? 0) > 0 &&
              (box.height ?? 0) > 0 &&
              box.width != double.infinity,
        )
        .toList(growable: false);

    expect(candleBoxes, hasLength(2));
    expect(
      candleBoxes.last.height,
      greaterThan(candleBoxes.first.height! * 10),
    );
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

Future<void> _expectPriceChangeColor(
  WidgetTester tester, {
  required int firstPrice,
  required int bitcoinPrice,
  required IconData icon,
  required Color expectedColor,
}) async {
  final now = DateTime.utc(2026, 8, 11, 12);
  final httpClient = _marketClient(
    now,
    firstPrice: firstPrice,
    bitcoinPrice: bitcoinPrice,
  );
  final harness = await PaymentFlowTestHarness.create(
    clock: () => now,
    httpClient: httpClient,
  );
  final baseTheme = AppTheme.light();
  final customColors = baseTheme.extension<AsterColors>()!.copyWith(
    chartPositive: const Color(0xFF123456),
    chartNegative: const Color(0xFF654321),
    success: const Color(0xFF00FF00),
    danger: const Color(0xFFFF0000),
  );
  final theme = baseTheme.copyWith(
    extensions: [
      for (final extension in baseTheme.extensions.values)
        if (extension is AsterColors) customColors else extension,
    ],
  );

  try {
    await _pump(tester, harness, Theme(data: theme, child: const PriceCard()));
    await _pumpUntil(tester, () => find.byIcon(icon).evaluate().isNotEmpty);
    expect(tester.widget<Icon>(find.byIcon(icon)).color, expectedColor);
  } finally {
    httpClient.close();
    await _disposeHarness(tester, harness);
  }
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
  int? usdtPrice,
}) {
  return http.Response(
    jsonEncode({
      'bitcoin': {
        'usd': bitcoinPrice,
        'last_updated_at': observedAt.millisecondsSinceEpoch ~/ 1000,
      },
      if (usdtPrice != null)
        'tether': {
          'usd': usdtPrice,
          'last_updated_at': observedAt.millisecondsSinceEpoch ~/ 1000,
        },
    }),
    200,
  );
}

Finder _assetRow(WalletAssetKind kind) => find.byWidgetPredicate(
  (widget) => widget is AssetRow && widget.kind == kind && !widget.loading,
);

void _expectFiatLoading(
  WidgetTester tester,
  WalletAssetKind kind,
  bool expected,
) {
  final skeletons = tester.widgetList<AppSkeletonizer>(
    find.descendant(
      of: _assetRow(kind),
      matching: find.byType(AppSkeletonizer),
    ),
  );
  expect(skeletons.map((widget) => widget.enabled), [
    expected,
    false,
  ], reason: 'Only the fiat value should shimmer for $kind.');
}

ResilientHttpClient _marketClientWithAssetTimestamps({
  required DateTime now,
  required DateTime bitcoinObservedAt,
  required DateTime usdtObservedAt,
  VoidCallback? onRequest,
}) {
  return ResilientHttpClient(
    client: MockClient((request) async {
      onRequest?.call();
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

final class _PendingWalletViewModel extends WalletViewModel {
  _PendingWalletViewModel(this._future);

  final Future<WalletState> _future;

  @override
  Future<WalletState> build() => _future;
}

final class _BlockingVisibilityPreferencesService extends PreferencesService {
  _BlockingVisibilityPreferencesService(
    super.preferences, {
    required this.writeStarted,
    required this.releaseWrite,
  });

  final Completer<void> writeStarted;
  final Completer<void> releaseWrite;

  @override
  Future<void> setBool(String key, bool value) async {
    if (key == 'aster.settings.v1.balances_visible') {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await releaseWrite.future;
    }
    return super.setBool(key, value);
  }
}
