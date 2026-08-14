import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/features/skeleton/presentation/widgets/bottom_nav.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/onboarding_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold wallet deep link fails closed into onboarding', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        RoutePaths.send;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.text('Built for\nUSDT on Bitcoin'), findsOneWidget);
  });

  testWidgets('a persisted active wallet enters the wallet shell on launch', (
    tester,
  ) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), RoutePaths.skeleton);
  });

  testWidgets('an invalid payment target slug returns to target selection', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/send/not-a-payment-target/address';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), RoutePaths.send);
    expect(find.text('Send'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.skeleton);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('a direct Send destination Back returns to target selection', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/send/bitcoin-onchain/address';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);
    expect(_location(router), '/send/bitcoin-onchain/address');

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.send);
  });

  testWidgets('an invalid Activity asset slug returns to the wallet shell', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/transactions/not-an-asset';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), RoutePaths.skeleton);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('a malformed Activity ID returns to the matching asset list', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/transactions/bitcoin/not-an-opaque-id';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), '/transactions/bitcoin');
    expect(find.text('Bitcoin Activity'), findsOneWidget);
  });

  testWidgets(
    'a valid opaque Activity deep link resolves without route extra',
    (tester) async {
      final activityId = 'activity-${'a' * 64}';
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/transactions/bitcoin/$activityId';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final (harness, transport) = await _createActiveHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));

      final router = await _pumpRouter(tester, harness);

      expect(_location(router), '/transactions/bitcoin/$activityId');
      expect(find.text('Transaction details'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await _pumpFrames(tester);
      expect(_location(router), '/transactions/bitcoin');
    },
  );

  testWidgets('a direct onboarding deep link has a safe Back destination', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        RoutePaths.onboardingImportWallet;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);

    final router = await _pumpRouter(tester, harness);
    expect(_location(router), RoutePaths.onboardingImportWallet);
    await tester.tap(find.text('Back'));
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.onboardingWelcome);
  });

  testWidgets('onboarding routes retain one shared mesh background', (
    tester,
  ) async {
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);

    final router = await _pumpRouter(tester, harness);
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
    final backgroundSnapshot = tester
        .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
        .singleWhere(
          (snapshot) => snapshot.child is OnboardingWelcomeMeshBackground,
        );
    expect(backgroundSnapshot.autoresize, isTrue);
    expect(backgroundSnapshot.controller.allowSnapshotting, isTrue);
    expect(
      backgroundSnapshot.painter,
      isA<OnboardingBackgroundSnapshotPainter>(),
    );
    expect(
      (backgroundSnapshot.painter as OnboardingBackgroundSnapshotPainter)
          .hasPaintedSnapshot,
      isTrue,
    );

    final importRoute = router.push<void>(RoutePaths.onboardingImportWallet);
    await _pumpFrames(tester);
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
    final importContext = tester.element(
      find.byType(OnboardingImportWalletScreen),
    );
    final transitionTheme = Theme.of(importContext).pageTransitionsTheme;
    final androidTransition = transitionTheme.builders[TargetPlatform.android];
    expect(
      androidTransition,
      isA<PredictiveBackFullscreenPageTransitionsBuilder>(),
    );
    expect(
      (androidTransition! as PredictiveBackFullscreenPageTransitionsBuilder)
          .fallbackColor,
      importContext.appColors.transparentSurface,
    );
    expect(
      transitionTheme.builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );

    router.pop();
    await _pumpFrames(tester);
    await importRoute;
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
  });

  testWidgets('confirmed onboarding refreshes the real router to wallet root', (
    tester,
  ) async {
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    final router = await _pumpRouter(tester, harness);
    expect(_location(router), RoutePaths.onboardingWelcome);

    router.go(RoutePaths.onboardingImportWallet);
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.onboardingImportWallet);
    await harness.container.read(importWalletViewModelProvider.future);
    final onboarding = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    onboarding.updateWords(0, validTestMnemonicWords);
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );

    expect(await onboarding.submit(), isTrue);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(walletViewModelProvider).value?.activeWallet !=
          null,
    );
    await _pumpFrames(tester);
    final currentRouter = harness.container.read(appRouterProvider);

    expect(currentRouter, same(router));
    expect(_location(currentRouter), RoutePaths.skeleton);
  });
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

Future<(OnboardingTestHarness, ResilientHttpClient)> _createHarness() async {
  final transport = ResilientHttpClient(
    client: MockClient((request) async {
      final now = DateTime.now().toUtc();
      if (request.url.path.endsWith('/range')) {
        return http.Response(
          jsonEncode({
            'prices': [
              [
                now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
                64000,
              ],
              [
                now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
                65000,
              ],
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 65000,
            'last_updated_at': now.millisecondsSinceEpoch ~/ 1000,
          },
        }),
        200,
      );
    }),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
  final harness = await OnboardingTestHarness.create(httpClient: transport);
  return (harness, transport);
}

Future<(OnboardingTestHarness, ResilientHttpClient)>
_createActiveHarness() async {
  final (harness, transport) = await _createHarness();
  final provision = await harness.repository.createFromMnemonic(
    mnemonic: validTestMnemonic,
    name: 'Primary Wallet',
  );
  expect(provision, isA<AppSuccess<WalletRegistry>>());
  await harness.container.read(walletViewModelProvider.future);
  return (harness, transport);
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  OnboardingTestHarness harness,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: _RouterApp(harness: harness),
    ),
  );
  await _pumpFrames(tester);
  return harness.container.read(appRouterProvider);
}

final class _RouterApp extends ConsumerWidget {
  const _RouterApp({required this.harness});

  final OnboardingTestHarness harness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => AsterFeedbackScope(
        haptics: harness.haptics,
        toasts: harness.toasts,
        child: child!,
      ),
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var frame = 0; frame < 100; frame += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for router state.');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _disposeHarness(
  WidgetTester tester,
  OnboardingTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final disposal = harness.dispose();
  for (var frame = 0; frame < 3; frame += 1) {
    await tester.pump();
  }
  await disposal;
}
