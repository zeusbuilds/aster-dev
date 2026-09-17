import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/screens/screens.dart';
import 'package:aster/features/market/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/models/models.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/scan/data/services/scan_session_contract.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/screens/screens.dart';
import 'package:aster/features/scan/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/shell/presentation/screens/screens.dart';
import 'package:aster/features/swap/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/pages.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'onboarding_harness.dart';
import 'payment_flow_harness.dart';
import 'scan_fakes.dart';
import 'wallet_fakes.dart';

const visualCatalogBoundary = ValueKey('visual-catalog-boundary');
typedef VisualCapture = Future<void> Function(WidgetTester tester, String name);

final _now = DateTime.utc(2026, 9, 9, 12);
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  indexerUrl: 'tcp://127.0.0.1:51001',
  rgbTransportProxy: 'http://127.0.0.1:3100',
  usdtAsset: RgbAssetConfiguration(contractId: 'catalog-usdt', precision: 6),
);
final _usdt = WalletAsset.rgbUsdt(assetId: 'catalog-usdt', precision: 6);
const _failure = AppFailure(
  code: 'visual_fixture_unavailable',
  kind: AppFailureKind.unavailable,
  userMessage: 'Wallet services are temporarily unavailable. Please try again.',
  retryable: true,
);
const _destination = 'bcrt1qzyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3lgth5g';

/// Preloaded real catalog data avoids process-wide asset futures surviving a
/// widget-test fake-async zone. No production bundle behavior is overridden.
final class _CatalogAssets extends CachingAssetBundle {
  _CatalogAssets(this.assets);
  final Map<String, ByteData> assets;

  @override
  Future<ByteData> load(String key) async => assets[key]!;
}

WalletAmount _amount({
  required WalletAssetId assetId,
  required PaymentRail rail,
  required int units,
}) => rail == PaymentRail.onchain
    ? WalletAmount.onchain(assetId: assetId, units: units)
    : WalletAmount.lightning(assetId: assetId, units: units);

/// One catalog, shared by host layout assertions and native iOS screenshots.
/// All wallet/market/camera values here are UI fixtures, not payment evidence.
void registerVisualCatalog({required VisualCapture capture}) {
  late Map<String, ByteData> settingsData;
  setUpAll(() async {
    settingsData = {
      for (final path in [
        'assets/data/currencies.json',
        'assets/data/countries.json',
      ])
        path: await rootBundle.load(path),
    };
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('visual catalog: onboarding and recovery', (tester) async {
    _phone(tester);
    final harness = await OnboardingTestHarness.create();
    final toasts = harness.container.read(toastControllerProvider.notifier);
    final router = _router();
    addTearDown(router.dispose);
    Future<void> scene(
      String name,
      Widget screen, {
      List<Override> overrides = const [],
    }) async {
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        OnboardingShell(child: screen),
        overrides: overrides,
      );
      await _shot(tester, capture, '01-onboarding/$name');
    }

    try {
      await scene('welcome', const OnboardingWelcomeScreen());
      await scene('create', const OnboardingCreateWalletScreen());
      await scene(
        'create-submitting',
        const OnboardingCreateWalletScreen(),
        overrides: [
          createWalletViewModelProvider.overrideWith(
            () => _CatalogCreate(submitting: true),
          ),
        ],
      );
      await scene(
        'create-failure',
        const OnboardingCreateWalletScreen(),
        overrides: [
          createWalletViewModelProvider.overrideWith(
            () => _CatalogCreate(failure: _failure),
          ),
        ],
      );
      await scene(
        'create-loading',
        const OnboardingCreateWalletScreen(),
        overrides: [
          createWalletViewModelProvider.overrideWith(
            () => _CatalogCreate(loading: true),
          ),
        ],
      );
      await scene('import-empty', const OnboardingImportWalletScreen());
      await tester.enterText(
        find.byKey(const ValueKey('recovery-word-1')),
        'abandon',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recovery-word-2')),
        'zzzz',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      await _shot(tester, capture, '01-onboarding/import-invalid-word');
      await tester.enterText(
        find.byKey(const ValueKey('recovery-word-1')),
        validTestMnemonic,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      // Full-phrase paste focuses word twelve. Deliberately return to page one.
      for (var page = 3; page > 1; page--) {
        await tester.drag(find.byType(PageView), const Offset(420, 0));
        await _settle(tester);
      }
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Recovery phrase page'))
            .value,
        '1 of 3',
      );
      await _shot(tester, capture, '01-onboarding/import-valid-page-1');
      for (var page = 2; page <= 3; page++) {
        await tester.drag(find.byType(PageView), const Offset(-420, 0));
        await _settle(tester);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Recovery phrase page'))
              .value,
          '$page of 3',
        );
        await _shot(tester, capture, '01-onboarding/import-valid-page-$page');
      }
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        const OnboardingShell(child: OnboardingImportWalletScreen()),
        keyboardInset: 320,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('recovery-word-1')))
            .controller!
            .text,
        'abandon',
      );
      await _shot(
        tester,
        capture,
        '01-onboarding/import-keyboard-inset-layout',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = harness.dispose();
      await tester.pump();
      await disposal;
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('visual catalog: home, settings, selection, swap, scanner', (
    tester,
  ) async {
    _phone(tester);
    final client = _market();
    final harness = await _harness(
      client: client,
      settingsAssets: _CatalogAssets(settingsData),
    );
    final toasts = harness.container.read(toastControllerProvider.notifier);
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(client.close);
    try {
      final scenes = <(String, Widget)>[
        ('00-startup/splash', const SplashScreen()),
        ('00-startup/wallet-access', const WalletAccessScreen()),
        ('00-startup/route-error', const ErrorScreen()),
        ('02-home/home', const AppShellScreen()),
        ('02-home/market', const MarketScreen()),
        ('08-settings/settings', const SettingsScreen()),
        ('08-settings/wallet-selection', const WalletSelectionScreen()),
        ('08-settings/currency', const CurrencySelectionScreen()),
        ('08-settings/region', const CountrySelectionScreen()),
        ('08-settings/bitcoin-unit', const BitcoinUnitSelectionScreen()),
        ('08-settings/advanced', const AdvancedSettingsScreen()),
        ('08-settings/network', const NetworkConfigurationScreen()),
        ('03-send/select', const SendScreen()),
        ('04-receive/select', const ReceiveScreen()),
        ('05-swap/swap', const SwapScreen()),
      ];
      for (final (name, screen) in scenes) {
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          screen,
          overrides: screen is AppShellScreen
              ? [
                  scanSessionProvider(ScanPurpose.sendLauncher)
                      .overrideWith((ref) {
                        final session = FakeScanSession();
                        ref.onDispose(() => unawaited(session.close()));
                        return session;
                      }),
                  scanViewModelProvider(ScanPurpose.sendLauncher)
                      .overrideWith(ScanViewModel.new),
                ]
              : const [],
        );
        await _shot(tester, capture, name);
        if (screen is SettingsScreen ||
            screen is NetworkConfigurationScreen ||
            screen is MarketScreen) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -650),
          );
          await _settle(tester);
          await _shot(tester, capture, '$name-scrolled');
        }
        if (screen is AppShellScreen) {
          await tester.tap(find.byTooltip('Hide balances'));
          await _settle(tester);
          await _shot(tester, capture, '02-home/home-hidden');
          await tester.tap(find.byTooltip('Show balances'));
          await _settle(tester);
          for (final (tab, name) in [
            ('scan', '07-scan/shell'),
            ('market', '02-home/market-shell'),
            ('settings', '08-settings/settings-shell'),
          ]) {
            final destination = find.byKey(ValueKey('bottom-nav-$tab'));
            await tester.tap(destination);
            await _settle(tester);
            expect(
              tester.getSemantics(destination).flagsCollection.isSelected,
              Tristate.isTrue,
            );
            await _shot(tester, capture, name);
          }
          await tester.tap(find.byKey(const ValueKey('bottom-nav-home')));
          await _settle(tester);
        }
        if (screen is SwapScreen) {
          await tester.tap(find.text('Bitcoin · On-chain'));
          await _settle(tester);
          await _shot(tester, capture, '05-swap/select-from');
          Navigator.of(tester.element(find.text('Select payment option')))
              .pop();
          await _settle(tester);
        }
      }
      for (final unavailable in [false, true]) {
        final session = FakeScanSession();
        if (unavailable) {
          session.current = const ScanSessionSnapshot(failure: _failure);
        }
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          const ScanScreen(purpose: ScanPurpose.destinationPicker),
          overrides: [
            scanSessionProvider(ScanPurpose.destinationPicker)
                .overrideWith((ref) => session),
            scanViewModelProvider(ScanPurpose.destinationPicker)
                .overrideWith(ScanViewModel.new),
          ],
        );
        if (unavailable) {
          session.replaceSnapshot(const ScanSessionSnapshot(failure: _failure));
          await _settle(tester);
          expect(find.text(_failure.userMessage), findsOneWidget);
        }
        await _shot(
          tester,
          capture,
          '07-scan/${unavailable ? 'unavailable' : 'ready'}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
      }
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        const SettingsScreen(),
      );
      for (final variant in ToastVariant.values) {
        toasts.show(
          title: '${variant.name} feedback',
          message: 'Aster keeps the current screen in place.',
          variant: variant,
        );
        await _settle(tester);
        await _shot(tester, capture, '09-feedback/${variant.name}');
        toasts.dismissCurrent();
        await _settle(tester);
      }
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        WalletUnavailableScreen(
          failure: _failure,
          title: 'Wallet access unavailable',
          retrying: false,
          onRetry: () {},
        ),
      );
      await _shot(tester, capture, '00-startup/wallet-unavailable');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = harness.dispose();
      await tester.pump();
      await disposal;
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('visual catalog: all send and receive rails', (tester) async {
    _phone(tester);
    final client = _market();
    final harness = await _harness(
      client: client,
      settingsAssets: _CatalogAssets(settingsData),
    );
    final toasts = harness.container.read(toastControllerProvider.notifier);
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(client.close);
    try {
      for (final target in WalletPaymentTarget.values) {
        for (final mode in [
          'address-empty',
          'address-ready',
          'amount',
          'submitting',
        ]) {
          final address = mode.startsWith('address');
          await _mount(
            tester,
            harness.container,
            toasts,
            router,
            address
                ? SendAddressScreen(target: target)
                : SendAmountScreen(target: target),
            overrides: [
              sendFlowViewModelProvider(target)
                  .overrideWith(() => _CatalogSend(mode)),
            ],
          );
          final scoped = ProviderScope.containerOf(
            tester.element(
              find.byType(address ? SendAddressScreen : SendAmountScreen),
            ),
          );
          await tester.runAsync(
            () => scoped
                .read(sendFlowViewModelProvider(target).future)
                .timeout(const Duration(seconds: 3)),
          );
          await _settle(tester);
          await _shot(tester, capture, '03-send/${target.slug}-$mode');
        }
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          ReceiveRequestScreen(target: target),
          overrides: [
            receiveFlowViewModelProvider(target)
                .overrideWith(() => _CatalogReceive('request')),
          ],
        );
        await _shot(tester, capture, '04-receive/${target.slug}-request');
        final amountButton = find.text('Set amount');
        await tester.ensureVisible(amountButton);
        await tester.tap(amountButton);
        await _settle(tester);
        expect(find.byType(ReceiveAmountSheet), findsOneWidget);
        await _shot(tester, capture, '04-receive/${target.slug}-amount-sheet');
      }
      for (final mode in ['loading', 'failure', 'invalid', 'expired']) {
        const target = WalletPaymentTarget.bitcoinLightning;
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          SendAmountScreen(target: target),
          overrides: [
            sendFlowViewModelProvider(target)
                .overrideWith(() => _CatalogSend(mode)),
          ],
        );
        await _shot(tester, capture, '03-send/$mode');
      }
      for (final mode in ['loading', 'failure', 'expired', 'generating']) {
        const target = WalletPaymentTarget.bitcoinLightning;
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          ReceiveRequestScreen(target: target),
          overrides: [
            receiveFlowViewModelProvider(target)
                .overrideWith(() => _CatalogReceive(mode)),
          ],
        );
        await _shot(tester, capture, '04-receive/$mode');
      }
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        const ReceiveRequestScreen(target: WalletPaymentTarget.usdtLightning),
      );
      await _shot(tester, capture, '04-receive/usdt-lightning-amount-required');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = harness.dispose();
      await tester.pump();
      await disposal;
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('visual catalog: activity, transaction details, compact layouts', (
    tester,
  ) async {
    _phone(tester);
    final client = _market();
    final engine = _engine();
    final harness = await _harness(
      client: client,
      engine: engine,
      settingsAssets: _CatalogAssets(settingsData),
    );
    final toasts = harness.container.read(toastControllerProvider.notifier);
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(client.close);
    try {
      for (final asset in [WalletAsset.bitcoin, _usdt]) {
        engine.activities = _activities(asset);
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          TransactionListScreen(assetKind: asset.kind),
          overrides: [
            activityViewModelProvider(asset.kind)
                .overrideWith(ActivityViewModel.new),
          ],
        );
        await _shot(tester, capture, '06-activity/${asset.kind.name}');
        for (final activity in engine.activities.take(2)) {
          await _mount(
            tester,
            harness.container,
            toasts,
            router,
            TransactionDetailsScreen(
              assetKind: asset.kind,
              activityId: activity.id,
            ),
          );
          await _shot(
            tester,
            capture,
            '06-activity/${asset.kind.name}-${activity.rail.name}-details',
          );
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -550),
          );
          await _settle(tester);
          await _shot(
            tester,
            capture,
            '06-activity/${asset.kind.name}-${activity.rail.name}-details-scrolled',
          );
        }
      }
      engine.activities = [];
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
        overrides: [
          activityViewModelProvider(WalletAssetKind.bitcoin)
              .overrideWith(ActivityViewModel.new),
        ],
      );
      expect(find.textContaining('No '), findsWidgets);
      expect(find.text('Received'), findsNothing);
      await _shot(tester, capture, '06-activity/empty');
      engine.activityError = const AppFailureException(_failure);
      await _mount(
        tester,
        harness.container,
        toasts,
        router,
        const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
        overrides: [
          activityViewModelProvider(WalletAssetKind.bitcoin)
              .overrideWith(ActivityViewModel.new),
        ],
      );
      expect(find.text(_failure.userMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await _shot(tester, capture, '06-activity/failure');
      engine.activityError = null;
      if (tester.binding is AutomatedTestWidgetsFlutterBinding) {
        tester.view.physicalSize = const Size(320, 568);
      }
      for (final (name, screen) in <(String, Widget)>[
        ('home', const HomeScreen()),
        ('send-selection', const SendScreen()),
        ('swap', const SwapScreen()),
        ('settings', const SettingsScreen()),
      ]) {
        await _mount(
          tester,
          harness.container,
          toasts,
          router,
          screen,
          textScale: 2,
        );
        await _shot(tester, capture, '10-accessibility/$name-2x');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -650));
        await _settle(tester);
        await _shot(tester, capture, '10-accessibility/$name-2x-scrolled');
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = harness.dispose();
      await tester.pump();
      await disposal;
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}

void _phone(WidgetTester tester) {
  if (tester.binding is! AutomatedTestWidgetsFlutterBinding) return;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 912);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
  ],
);

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  ToastController toasts,
  GoRouter router,
  Widget screen, {
  List<Override> overrides = const [],
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  toasts.dismissCurrent();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: screen,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return RepaintBoundary(
              key: visualCatalogBoundary,
              child: MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: true,
                  padding: EdgeInsets.only(
                    top: 62,
                    bottom: keyboardInset > 0 ? 0 : 34,
                  ),
                  viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
                  viewInsets: EdgeInsets.only(bottom: keyboardInset),
                ),
                child: InheritedGoRouter(
                  goRouter: router,
                  child: AsterFeedbackScope(
                    haptics: const NoopHapticFeedbackService(),
                    toasts: toasts,
                    child: ToastHost(child: child!),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shot(
  WidgetTester tester,
  VisualCapture capture,
  String name,
) async {
  expect(find.byKey(visualCatalogBoundary), findsOneWidget, reason: name);
  expect(tester.takeException(), isNull, reason: name);
  await capture(tester, name);
}

Future<PaymentFlowTestHarness> _harness({
  required ResilientHttpClient client,
  FakeWalletEngine? engine,
  required AssetBundle settingsAssets,
}) => PaymentFlowTestHarness.create(
  engine: engine ?? _engine(),
  httpClient: client,
  services: _services,
  clock: () => _now,
  settingsAssets: settingsAssets,
  preferenceValues: const {'aster.settings.v1.bitcoin_unit': 'sats'},
);

ResilientHttpClient _market() => ResilientHttpClient(
  client: MockClient(
    (request) async => http.Response(
      jsonEncode(
        request.url.path.endsWith('/range')
            ? {
                'prices': [
                  for (var index = 0; index <= 24; index++)
                    [
                      _now
                          .subtract(Duration(hours: 24 - index, minutes: 1))
                          .millisecondsSinceEpoch,
                      78000 + index * 38 + (index % 3) * 65,
                    ],
                ],
              }
            : {
                'bitcoin': {
                  'usd': 78918,
                  'last_updated_at': _now.millisecondsSinceEpoch ~/ 1000,
                },
                'tether': {
                  'usd': 1,
                  'last_updated_at': _now.millisecondsSinceEpoch ~/ 1000,
                },
              },
      ),
      200,
    ),
  ),
  retryPolicy: RetryPolicy(maxAttempts: 1),
);

FakeWalletEngine _engine() => FakeWalletEngine()
  ..balances[WalletAsset.bitcoin.id] = _balance(WalletAsset.bitcoin)
  ..balances[_usdt.id] = _balance(_usdt)
  ..feeEstimate = WalletFeeRateEstimate(
    targetBlocks: 6,
    satsPerVbyte: 2,
    observedAt: _now,
  )
  ..networkStatus = WalletNetworkStatus(
    environment: BlockchainEnvironment.regtest,
    blockHeight: 245,
    nodePublicKey: '02${'1' * 64}',
    channelCount: 2,
    usableChannelCount: 2,
    peerCount: 1,
  );

WalletBalance _balance(WalletAsset asset) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: asset.id, units: units);
  final btc = asset.kind == WalletAssetKind.bitcoin;
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(btc ? 1800000 : 1250000000),
    onchainFuture: onchain(btc ? 1800000 : 1250000000),
    onchainSpendable: onchain(btc ? 1750000 : 1200000000),
    onchainLocked: onchain(btc ? 50000 : 50000000),
    lightningOwned: lightning(btc ? 700000000 : 250000000),
    lightningSpendable: lightning(btc ? 650000000 : 240000000),
    lightningReceivable: lightning(btc ? 200000000 : 500000000),
  );
}

List<WalletActivity> _activities(WalletAsset asset) => [
  for (var index = 0; index < 6; index++)
    WalletActivity(
      id: 'activity-${(index + 1).toString().padLeft(64, '0')}',
      source: index.isOdd
          ? WalletActivitySource.lightningPayment
          : asset.kind == WalletAssetKind.bitcoin
          ? WalletActivitySource.bitcoinTransaction
          : WalletActivitySource.rgbTransfer,
      operation: index.isOdd
          ? WalletActivityOperation.lightningPayment
          : asset.kind == WalletAssetKind.bitcoin
          ? WalletActivityOperation.bitcoinSend
          : WalletActivityOperation.rgbSend,
      asset: asset,
      rail: index.isOdd ? PaymentRail.lightning : PaymentRail.onchain,
      direction: index.isOdd
          ? WalletActivityDirection.received
          : WalletActivityDirection.sent,
      status: index == 0
          ? WalletActivityStatus.pending
          : WalletActivityStatus.succeeded,
      amount: _amount(
        assetId: asset.id,
        rail: index.isOdd ? PaymentRail.lightning : PaymentRail.onchain,
        units: index.isOdd ? 25000000 : 100000,
      ),
      fee: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 120),
      occurredAt: _now.subtract(Duration(hours: index * 8)),
      txid: index.isEven ? 'a' * 64 : null,
      paymentHash: index.isOdd ? 'b' * 64 : null,
      invoice: index.isOdd ? 'lnbcrt-catalog-invoice' : null,
      transferIndex: index.isEven && asset.kind == WalletAssetKind.usdt
          ? index
          : null,
      recipientId: index.isEven && asset.kind == WalletAssetKind.usdt
          ? 'utxob:catalog-recipient'
          : null,
    ),
];

class _CatalogCreate extends CreateWalletViewModel {
  _CatalogCreate({this.submitting = false, this.loading = false, this.failure});
  final bool submitting;
  final bool loading;
  final AppFailure? failure;
  @override
  Future<CreateWalletState> build() async {
    if (loading) return Completer<CreateWalletState>().future;
    return CreateWalletState(
      words: validTestMnemonicWords,
      questions: [
        for (final wordNumber in CreateWalletState.quizWordNumbers)
          RecoveryPhraseQuestion(
            wordNumber: wordNumber,
            expectedWord: validTestMnemonicWords[wordNumber - 1],
            options: [
              validTestMnemonicWords[wordNumber - 1],
              'ability',
              'above',
              'absent',
            ],
          ),
      ],
      submitting: submitting,
      failure: failure,
    );
  }
}

class _CatalogSend extends SendFlowViewModel {
  _CatalogSend(this.mode);
  final String mode;
  @override
  Future<SendFlowState> build(WalletPaymentTarget target) async {
    if (mode == 'loading') return Completer<SendFlowState>().future;
    if (mode == 'failure') throw const AppFailureException(_failure);
    final initial = await super.build(target);
    if (mode == 'address-empty') return initial;
    final destination = target == WalletPaymentTarget.bitcoinOnchain
        ? _destination
        : 'lnbcrt-catalog-payment-request';
    if (mode == 'address-ready') {
      return initial.copyWith(destination: destination);
    }
    final text = mode == 'invalid'
        ? '999999999999'
        : target.assetKind == WalletAssetKind.bitcoin
        ? '25000'
        : '100';
    return initial.copyWith(
      destination: destination,
      preview: WalletPaymentPreview(
        route: initial.route,
        encodedDestination: destination,
        displayDestination: destination,
        expiresAt: mode == 'expired'
            ? _now.subtract(const Duration(minutes: 1))
            : null,
      ),
      amountText: text,
      amountInput: const WalletAmountInputCodec().parse(
        text: text,
        route: initial.route,
        bitcoinUnit: initial.bitcoinUnit,
      ),
      operation: mode == 'submitting' ? SendFlowOperation.submitting : null,
    );
  }
}

class _CatalogReceive extends ReceiveFlowViewModel {
  _CatalogReceive(this.mode);
  final String mode;
  @override
  Future<ReceiveFlowState> build(WalletPaymentTarget target) async {
    if (mode == 'loading') return Completer<ReceiveFlowState>().future;
    if (mode == 'failure') throw const AppFailureException(_failure);
    final initial = await super.build(target);
    final text = target.assetKind == WalletAssetKind.bitcoin ? '25000' : '100';
    final input = const WalletAmountInputCodec().parse(
      text: text,
      route: initial.route,
      bitcoinUnit: initial.bitcoinUnit,
    );
    final value = target == WalletPaymentTarget.bitcoinOnchain
        ? _destination
        : '${target.rail == PaymentRail.lightning ? 'lnbcrt' : 'rgb'}1${'qpzry9x8gf2tvdw0s3jn54khce6mua7l' * 6}';
    return initial.copyWith(
      request: WalletReceiveRequest(
        route: initial.route,
        encodedRequest: value,
        displayValue: value,
        amount: _amount(
          assetId: initial.route.asset.id,
          rail: initial.route.rail,
          units: input.units!,
        ),
        expiresAt: initial.route.rail == PaymentRail.lightning
            ? _now.add(Duration(minutes: mode == 'expired' ? -1 : 30))
            : null,
      ),
      amountText: text,
      amountInput: input,
      operation: mode == 'generating'
          ? ReceiveFlowOperation.generatingRequest
          : null,
    );
  }
}
