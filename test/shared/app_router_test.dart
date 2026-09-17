import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/presentation/models/models.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/features/shell/presentation/widgets/bottom_nav.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/pages.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:aster/shared/theme/aster_page_transitions.dart';
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

    expect(_location(router), RoutePaths.home);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('the removed skeleton location recovers to canonical Home', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/skeleton';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), '/skeleton');
    expect(find.text('Route Error'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    await tester.tap(find.text('Go to Home'));
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.home);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('the orphan Market location cannot bypass the app shell', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/market';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), '/market');
    expect(find.text('Route Error'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    await tester.tap(find.text('Go to Home'));
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.home);
    expect(find.byType(BottomNav), findsOneWidget);
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
    expect(_location(router), RoutePaths.home);
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

  testWidgets('a direct Settings child Back returns to Settings', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '${RoutePaths.settings}/${RoutePaths.walletSelection}';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);
    expect(
      _location(router),
      '${RoutePaths.settings}/${RoutePaths.walletSelection}',
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.settings);
  });

  testWidgets('a direct network child Back returns to Advanced Settings', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '${RoutePaths.advancedSettingsLocation}/${RoutePaths.networkConfiguration}';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);
    expect(
      _location(router),
      '${RoutePaths.advancedSettingsLocation}/${RoutePaths.networkConfiguration}',
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.advancedSettingsLocation);
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

    expect(_location(router), RoutePaths.home);
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

  testWidgets('white onboarding pages cover the retained welcome mesh', (
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
    expect(transitionTheme, AppTheme.light().pageTransitionsTheme);
    final importScaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(OnboardingImportWalletScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(importScaffold.backgroundColor, importContext.colorScheme.surface);
    expect(
      tester
          .widget<Text>(find.text('Import with recovery phrase'))
          .style!
          .color,
      importContext.colorScheme.onSurface,
    );
    expect(
      transitionTheme.builders[TargetPlatform.iOS],
      isA<AsterCupertinoPageTransitionsBuilder>(),
    );
    expect(find.byType(DecoratedBoxTransition), findsNothing);

    router.pop();
    await _pumpFrames(tester);
    await importRoute;
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
  });

  testWidgets('iOS keeps edge-swipe pop without painting an edge shadow', (
    tester,
  ) async {
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);

    final router = await _pumpRouter(
      tester,
      harness,
      platform: TargetPlatform.iOS,
    );
    final importRoute = router.push<void>(RoutePaths.onboardingImportWallet);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(DecoratedBoxTransition), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OnboardingImportWalletScreen), findsOneWidget);

    await tester.dragFrom(
      const Offset(1, 400),
      const Offset(330, 0),
      touchSlopX: 0,
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(_location(router), RoutePaths.onboardingWelcome);
    unawaited(importRoute);
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
              ?.canContinue ==
          true,
    );
    onboarding.updateWalletName('Imported wallet');

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
    expect(_location(currentRouter), RoutePaths.home);
  });

  testWidgets(
    'create onboarding confirms backup and persists the chosen name',
    (tester) async {
      final (harness, transport) = await _createHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));
      await harness.container.read(walletViewModelProvider.future);
      final router = await _pumpRouter(tester, harness);

      router.go(RoutePaths.onboardingCreateWallet);
      await _pumpFrames(tester);
      await _completeCreateWalletFlow(
        tester,
        harness,
        walletName: 'Everyday wallet',
      );

      final wallet = harness.container
          .read(walletViewModelProvider)
          .requireValue;
      expect(_location(router), RoutePaths.home);
      expect(wallet.wallets, hasLength(1));
      expect(wallet.activeWallet?.name, 'Everyday wallet');
    },
  );

  testWidgets('wallet selector adds and activates a separately named wallet', (
    tester,
  ) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final initialWallet = harness.container
        .read(walletViewModelProvider)
        .requireValue
        .activeWallet!;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const _WalletSelectorLauncher(),
        ),
        GoRoute(
          path: '/wallet-selector',
          name: RouteNames.walletSelection,
          builder: (context, state) => const WalletSelectionScreen(),
          routes: [
            GoRoute(
              path: RoutePaths.addWallet,
              name: RouteNames.addWallet,
              builder: (context, state) => const OnboardingCreateWalletScreen(
                origin: WalletCreationOrigin.walletSelector,
              ),
              routes: [
                GoRoute(
                  path: RoutePaths.confirmRecovery,
                  name: RouteNames.addWalletQuiz,
                  builder: (context, state) => const CreateWalletQuizScreen(
                    origin: WalletCreationOrigin.walletSelector,
                  ),
                  routes: [
                    GoRoute(
                      path: RoutePaths.nameWallet,
                      name: RouteNames.addWalletName,
                      builder: (context, state) =>
                          const WalletNameScreen.create(
                            origin: WalletCreationOrigin.walletSelector,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
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
    await _pumpFrames(tester);

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Open wallets'))
        .onTap!();
    await _pumpFrames(tester);
    expect(
      harness.toasts.messages,
      isEmpty,
      reason: harness.toasts.messages
          .map((message) => '${message.title}: ${message.message}')
          .join('\n'),
    );
    expect(find.byType(WalletSelectionScreen), findsOneWidget);
    expect(find.text('Select Wallet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add wallet'));
    await _pumpFrames(tester);
    expect(find.text('Your 12-word recovery phrase'), findsOneWidget);

    await _completeCreateWalletFlow(
      tester,
      harness,
      walletName: 'Travel wallet',
    );
    await tester.pump(const Duration(seconds: 2));

    final wallet = harness.container.read(walletViewModelProvider).requireValue;
    expect(_location(router), '/');
    expect(wallet.wallets, hasLength(2));
    expect(wallet.wallets, contains(initialWallet));
    expect(wallet.activeWallet?.name, 'Travel wallet');
    expect(wallet.activeWallet?.id, isNot(initialWallet.id));
    expect(harness.engines[1].provisionedMnemonic, validTestMnemonic);

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Open wallets'))
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WalletSelectionScreen), findsOneWidget);
    expect(find.text('Travel wallet'), findsOneWidget);
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

Future<void> _completeCreateWalletFlow(
  WidgetTester tester,
  OnboardingTestHarness harness, {
  required String walletName,
}) async {
  await _pumpUntil(
    tester,
    () => find.text('Your 12-word recovery phrase').evaluate().isNotEmpty,
  );
  final phraseContinue = find.descendant(
    of: find.byType(OnboardingCreateWalletScreen),
    matching: find.widgetWithText(CustomButton, 'Continue'),
  );
  await tester.ensureVisible(phraseContinue);
  await tester.tap(phraseContinue);
  await _pumpFrames(tester);

  expect(find.text('Check your backup'), findsOneWidget);
  for (var index = 0; index < 4; index += 1) {
    final question = harness.container
        .read(createWalletViewModelProvider)
        .requireValue
        .currentQuestion!;
    await tester.tap(
      find.descendant(
        of: find.byType(CreateWalletQuizScreen),
        matching: find.text(question.expectedWord),
      ),
    );
    await tester.pump();
  }
  expect(find.text('Recovery phrase confirmed'), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byType(CreateWalletQuizScreen),
      matching: find.widgetWithText(CustomButton, 'Continue'),
    ),
  );
  await _pumpFrames(tester);

  expect(find.text('Name your wallet'), findsOneWidget);
  await tester.enterText(
    find.byKey(const ValueKey('wallet-name-field')),
    walletName,
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(CustomButton, 'Create Wallet'));
  await _pumpUntil(
    tester,
    () =>
        harness.container
            .read(walletViewModelProvider)
            .value
            ?.activeWallet
            ?.name ==
        walletName,
  );
  await _pumpFrames(tester);
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  OnboardingTestHarness harness, {
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: _RouterApp(harness: harness, platform: platform),
    ),
  );
  await _pumpFrames(tester);
  return harness.container.read(appRouterProvider);
}

final class _WalletSelectorLauncher extends StatelessWidget {
  const _WalletSelectorLauncher();

  @override
  Widget build(BuildContext context) {
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          return Scaffold(
            body: Center(
              child: CustomButton(
                text: 'Open wallets',
                enabled: !navigation.inFlight,
                onTap: () => unawaited(
                  navigation.run(
                    command: () =>
                        context.pushNamed<void>(RouteNames.walletSelection),
                    failureTitle: 'Wallet selector could not open',
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _RouterApp extends ConsumerWidget {
  const _RouterApp({required this.harness, this.platform});

  final OnboardingTestHarness harness;
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: AppTheme.light().copyWith(platform: platform),
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
