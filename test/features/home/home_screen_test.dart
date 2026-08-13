import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/screens/screens.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
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
    expect(find.text(r'$1.00 estimated'), findsOneWidget);
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

ResilientHttpClient _marketClient(DateTime now) {
  final observed = now.subtract(const Duration(minutes: 1));
  return ResilientHttpClient(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/range')) {
        return http.Response(
          jsonEncode({
            'prices': [
              [
                now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
                99000,
              ],
              [observed.millisecondsSinceEpoch, 100000],
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 100000,
            'last_updated_at': observed.millisecondsSinceEpoch ~/ 1000,
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
