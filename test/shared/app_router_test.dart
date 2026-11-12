import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/shell/presentation/providers/app_shell_index_provider.dart';
import 'package:aster/features/shell/presentation/widgets/bottom_nav.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/pages.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:aster/shared/theme/aster_page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
    'navigation drops old-route toast queues and late action results',
    (tester) async {
      final (harness, transport) = await _createActiveHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));
      final router = await _pumpRouter(tester, harness);
      final controller = harness.container.read(
        toastControllerProvider.notifier,
      );
      final origin = controller.captureOrigin();
      origin.show(title: 'Old route', variant: ToastVariant.info);
      origin.show(title: 'Queued old route', variant: ToastVariant.failure);
      final selection = router.pushNamed<void>(RouteNames.walletSelection);
      await _pumpFrames(tester);
      expect(harness.container.read(toastControllerProvider).current, isNull);
      expect(harness.container.read(toastControllerProvider).pending, isEmpty);
      expect(
        origin.show(title: 'Late result', variant: ToastVariant.failure),
        isFalse,
      );
      router.pop();
      await selection;
      await _pumpFrames(tester);
      expect(
        origin.show(
          title: 'Previous home visit',
          variant: ToastVariant.failure,
        ),
        isFalse,
      );
    },
  );

  testWidgets('shell tab changes expire old action feedback', (tester) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpRouter(tester, harness);
    final controller = harness.container.read(toastControllerProvider.notifier);
    final origin = controller.captureOrigin();
    origin.show(title: 'Home action', variant: ToastVariant.info);
    harness.container.read(appShellIndexProvider.notifier).setIndex(2);
    await tester.pump();
    expect(harness.container.read(toastControllerProvider).current, isNull);
    expect(
      origin.show(title: 'Late Home action', variant: ToastVariant.failure),
      isFalse,
    );
  });

  testWidgets(
    'wallet metadata refresh preserves feedback owned by the same pushed page',
    (tester) async {
      final (harness, transport) = await _createActiveHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));
      final router = await _pumpRouter(tester, harness);
      unawaited(router.pushNamed<void>(RouteNames.walletSelection));
      await _pumpFrames(tester);
      final controller = harness.container.read(
        toastControllerProvider.notifier,
      );
      final origin = controller.captureOrigin();
      final before = router.state.pageKey;
      final current = harness.container
          .read(walletViewModelProvider)
          .requireValue;
      final active = current.activeWallet!;
      harness.container
          .read(walletViewModelProvider.notifier)
          .adoptCommittedRegistry(
            WalletRegistry(
              profiles: [active.copyWith(name: 'Updated fixture name')],
              activeWalletId: active.id,
            ),
          );
      await _pumpFrames(tester);

      expect(router.state.name, RouteNames.walletSelection);
      expect(router.state.pageKey, before);
      expect(
        origin.show(title: 'Same page result', variant: ToastVariant.info),
        isTrue,
      );
      router.pop();
      await _pumpFrames(tester);
      expect(
        origin.show(title: 'Departed page result', variant: ToastVariant.info),
        isFalse,
      );
    },
  );

  testWidgets(
    'pushing the same URI gives a new feedback owner and returning does not revive it',
    (tester) async {
      final (harness, transport) = await _createActiveHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));
      final router = await _pumpRouter(tester, harness);
      final first = router.pushNamed<void>(RouteNames.walletDetails);
      await _pumpFrames(tester);
      final controller = harness.container.read(
        toastControllerProvider.notifier,
      );
      final origin = controller.captureOrigin();
      final firstPage = router.state.pageKey;
      final uri = router.state.uri;
      final second = router.pushNamed<void>(RouteNames.walletDetails);
      await _pumpFrames(tester);

      expect(router.state.uri, uri);
      expect(router.state.pageKey, isNot(firstPage));
      expect(
        origin.show(title: 'Covered earlier page', variant: ToastVariant.info),
        isFalse,
      );
      router.pop();
      await _pumpFrames(tester);
      await second;
      await _pumpFrames(tester);
      expect(router.state.pageKey, firstPage);
      expect(
        origin.show(title: 'Earlier visit', variant: ToastVariant.info),
        isFalse,
      );
      router.pop();
      await _pumpFrames(tester);
      await first;
      await _pumpFrames(tester);
    },
  );

  testWidgets('query changes expire an earlier page action', (tester) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = await _pumpRouter(tester, harness);
    router.go('${RoutePaths.settings}?review=one');
    await _pumpFrames(tester);
    final controller = harness.container.read(toastControllerProvider.notifier);
    final origin = controller.captureOrigin();
    final pageKey = router.state.pageKey;
    router.go('${RoutePaths.settings}?review=two');
    await _pumpFrames(tester);

    expect(router.state.pageKey, pageKey);
    expect(router.state.uri.queryParameters['review'], 'two');
    expect(
      origin.show(title: 'Earlier query result', variant: ToastVariant.info),
      isFalse,
    );
  });

  for (final useRootNavigator in [false, true]) {
    for (final useBottomSheet in [false, true]) {
      testWidgets(
        'popup clears queued feedback and preserves its parent action (root: $useRootNavigator, sheet: $useBottomSheet)',
        (tester) async {
          final (harness, transport) = await _createHarness();
          addTearDown(transport.close);
          addTearDown(() => _disposeHarness(tester, harness));
          await harness.container.read(walletViewModelProvider.future);
          final router = await _pumpRouter(
            tester,
            harness,
            useRealToasts: true,
          );
          final context = tester.element(find.byType(OnboardingWelcomeScreen));
          final origin = context.toasts;
          origin.show(title: 'Old action', variant: ToastVariant.info);
          origin.show(title: 'Old queued action', variant: ToastVariant.info);
          final location = _location(router);
          late final Future<bool?> decision;
          Widget content(BuildContext popupContext) => TextButton(
            onPressed: () => Navigator.of(popupContext).pop(true),
            child: const Text('Confirm action'),
          );
          if (useBottomSheet) {
            decision = showModalBottomSheet<bool>(
              context: context,
              useRootNavigator: useRootNavigator,
              builder: content,
            );
          } else {
            decision = showDialog<bool>(
              context: context,
              useRootNavigator: useRootNavigator,
              builder: (popupContext) =>
                  AlertDialog(content: content(popupContext)),
            );
          }
          await _pumpFrames(tester);
          expect(_location(router), location);
          expect(
            harness.container.read(toastControllerProvider).current,
            isNull,
          );
          expect(
            harness.container.read(toastControllerProvider).pending,
            isEmpty,
          );
          expect(
            origin.show(title: 'Covered result', variant: ToastVariant.failure),
            isFalse,
          );

          // Popup-owned feedback must not survive the popup's removal either.
          final popupOrigin = tester
              .element(find.text('Confirm action'))
              .toasts;
          expect(
            popupOrigin.show(
              title: 'Popup feedback',
              variant: ToastVariant.info,
            ),
            isTrue,
          );
          await tester.tap(find.text('Confirm action'));
          expect(await decision, isTrue);
          // Report the result when the awaiting action resumes, before waiting
          // for the popup's exit animation to finish.
          expect(
            origin.show(title: 'Confirmed action', variant: ToastVariant.info),
            isTrue,
          );
          expect(
            harness.container.read(toastControllerProvider).current?.title,
            'Confirmed action',
          );
          expect(
            harness.container.read(toastControllerProvider).pending,
            isEmpty,
          );
          await _pumpFrames(tester);
          expect(
            popupOrigin.show(
              title: 'Late popup result',
              variant: ToastVariant.info,
            ),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('wallet selector is one pushed page above Home', (tester) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = await _pumpRouter(tester, harness);
    final walletMatch = router.configuration.findMatch(
      Uri.parse(RoutePaths.walletSelectionLocation),
    );
    expect(walletMatch.isError, isFalse, reason: walletMatch.error?.toString());
    expect(
      (walletMatch.matches.last.route as GoRoute).name,
      RouteNames.walletSelection,
    );

    final selection = router.pushNamed<void>(RouteNames.walletSelection);
    var selectionCompleted = false;
    unawaited(selection.whenComplete(() => selectionCompleted = true));
    await tester.pump();
    expect(selectionCompleted, isFalse);
    await _pumpFrames(tester);

    expect(find.byType(WalletSelectionScreen), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await selection;
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.home);
    expect(find.byType(WalletSelectionScreen), findsNothing);
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('the removed skeleton location recovers to canonical Home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(951, 669);
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/skeleton';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));

    final router = await _pumpRouter(tester, harness);

    expect(_location(router), '/skeleton');
    _expectUnavailablePage(tester);
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
    _expectUnavailablePage(tester);
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

  testWidgets('disabled payment routes return to their own selector', (
    tester,
  ) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = await _pumpRouter(tester, harness);

    final nativeCalls = List.of(harness.engine.calls);
    for (final (location, expected) in [
      ('/send/bitcoin-lightning/address', RoutePaths.send),
      ('/send/usdt-lightning/amount', RoutePaths.send),
      ('/send/usdt-onchain/address', RoutePaths.send),
      ('/receive/bitcoin-lightning', RoutePaths.receive),
      ('/receive/usdt-lightning', RoutePaths.receive),
      ('/receive/usdt-onchain', RoutePaths.receive),
    ]) {
      router.go(location);
      await _pumpFrames(tester);
      expect(_location(router), expected, reason: location);
      expect(find.textContaining('Coming later'), findsNWidgets(2));
    }
    expect(harness.engine.calls, nativeCalls);
  });

  testWidgets('retired preference links return to Settings', (tester) async {
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = await _pumpRouter(tester, harness);

    for (final path in [
      RoutePaths.countrySelection,
      RoutePaths.currencySelection,
    ]) {
      router.go('${RoutePaths.settings}/$path');
      await _pumpFrames(tester);
      expect(_location(router), RoutePaths.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
    }
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

  testWidgets(
    'wallet details opens from Settings and Back preserves Settings',
    (tester) async {
      final (harness, transport) = await _createActiveHarness();
      addTearDown(transport.close);
      addTearDown(() => _disposeHarness(tester, harness));
      final router = await _pumpRouter(tester, harness);
      router.go(RoutePaths.settings);
      await _pumpFrames(tester);

      await tester.tap(find.text('Wallet details'));
      await _pumpFrames(tester);

      expect(
        router.namedLocation(RouteNames.walletDetails),
        '${RoutePaths.settings}/${RoutePaths.walletDetails}',
      );
      expect(find.byType(WalletDetailsScreen), findsOneWidget);
      expect(router.canPop(), isTrue);
      expect(find.text('Primary Wallet'), findsOneWidget);
      expect(find.byType(BottomNav), findsNothing);

      await tester.tap(find.bySemanticsLabel('Back'));
      await _pumpFrames(tester);
      expect(_location(router), RoutePaths.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(WalletDetailsScreen), findsNothing);
    },
  );

  testWidgets('a direct wallet details link has a Settings Back action', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '${RoutePaths.settings}/${RoutePaths.walletDetails}';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createActiveHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = await _pumpRouter(tester, harness);

    expect(find.byType(WalletDetailsScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a wallet details link without a wallet enters onboarding', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '${RoutePaths.settings}/${RoutePaths.walletDetails}';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    final router = await _pumpRouter(tester, harness);

    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.byType(WalletDetailsScreen), findsNothing);
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

  testWidgets('onboarding changes content without changing its route', (
    tester,
  ) async {
    final (harness, transport) = await _createHarness();
    addTearDown(transport.close);
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);

    final router = await _pumpRouter(tester, harness);
    await tester.tap(find.text('Import Wallet'));
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.byType(OnboardingImportWalletScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.text('Built for\nUSDT on Bitcoin'), findsOneWidget);
  });

  testWidgets('onboarding steps retain mesh and replace foreground in place', (
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

    await tester.tap(find.text('Import Wallet'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
    final retainedSnapshot = tester
        .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
        .singleWhere(
          (snapshot) => snapshot.child is OnboardingWelcomeMeshBackground,
        );
    expect(retainedSnapshot.controller, same(backgroundSnapshot.controller));
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
    expect(
      importScaffold.backgroundColor,
      importContext.appColors.transparentSurface,
    );
    expect(
      tester
          .widget<Text>(find.text('Import with recovery phrase'))
          .style!
          .color,
      importContext.appColors.onBrandArt,
    );
    expect(
      transitionTheme.builders[TargetPlatform.iOS],
      isA<AsterCupertinoPageTransitionsBuilder>(),
    );
    expect(find.byType(DecoratedBoxTransition), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
  });

  testWidgets('system Back returns inline without a route edge shadow', (
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
    await tester.tap(find.text('Import Wallet'));
    await _pumpFrames(tester);

    expect(find.byType(DecoratedBoxTransition), findsNothing);
    expect(find.byType(OnboardingImportWalletScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);

    expect(_location(router), RoutePaths.onboardingWelcome);
    expect(find.text('Built for\nUSDT on Bitcoin'), findsOneWidget);
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

    await tester.tap(find.text('Import Wallet'));
    await _pumpFrames(tester);
    expect(_location(router), RoutePaths.onboardingWelcome);
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

      await tester.tap(find.widgetWithText(CustomButton, 'Create Wallet'));
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

  testWidgets('wallet setup creates or imports and returns directly home', (
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
          path: RoutePaths.home,
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
              builder: (context, state) => const AddWalletScreen(),
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
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
    expect(find.byType(OnboardingWelcomeHeader), findsNothing);
    expect(find.byType(OnboardingWelcomeIconGrid), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.text('Multiple wallets,\none Aster'), findsOneWidget);
    expect(
      find.text(
        'Create or import another wallet, then switch between your wallets '
        'whenever you need.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
    );
    await _pumpFrames(tester);
    expect(find.byType(OnboardingImportWalletScreen), findsOneWidget);
    expect(find.text('Import with recovery phrase'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpFrames(tester);
    expect(find.text('Multiple wallets,\none Aster'), findsOneWidget);
    expect(find.byType(OnboardingImportWalletScreen), findsNothing);

    await tester.tap(find.widgetWithText(CustomButton, 'Add New Wallet'));
    await _pumpFrames(tester);
    expect(find.text('Your 12-word recovery phrase'), findsOneWidget);

    await _completeCreateWalletFlow(
      tester,
      harness,
      walletName: 'Travel wallet',
    );
    await tester.pump(const Duration(seconds: 2));

    final wallet = harness.container.read(walletViewModelProvider).requireValue;
    expect(_location(router), RoutePaths.home);
    expect(find.byType(AddWalletScreen), findsNothing);
    expect(find.byType(WalletSelectionScreen), findsNothing);
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

    await tester.tap(find.bySemanticsLabel('Add wallet'));
    await _pumpFrames(tester);
    await tester.tap(
      find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
    );
    await _pumpFrames(tester);
    const importedWords = <String>[
      'legal',
      'winner',
      'thank',
      'year',
      'wave',
      'sausage',
      'worth',
      'useful',
      'legal',
      'winner',
      'thank',
      'yellow',
    ];
    harness.container
        .read(importWalletViewModelProvider.notifier)
        .updateWords(0, importedWords);
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canContinue ==
          true,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(OnboardingImportWalletScreen),
        matching: find.widgetWithText(CustomButton, 'Continue'),
      ),
    );
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('wallet-name-field')),
      'Savings wallet',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(CustomButton, 'Import Wallet'));
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(walletViewModelProvider)
              .value
              ?.activeWallet
              ?.name ==
          'Savings wallet',
    );
    await _pumpFrames(tester);

    final importedRegistry = harness.container
        .read(walletViewModelProvider)
        .requireValue;
    expect(_location(router), RoutePaths.home);
    expect(find.byType(AddWalletScreen), findsNothing);
    expect(find.byType(WalletSelectionScreen), findsNothing);
    expect(importedRegistry.wallets, hasLength(3));
    expect(importedRegistry.activeWallet?.name, 'Savings wallet');
    expect(harness.engines[2].provisionedMnemonic, importedWords.join(' '));
  });
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void _expectUnavailablePage(WidgetTester tester) {
  final page = find.byType(ErrorScreen);
  expect(page, findsOneWidget);
  final scaffold = tester.widget<Scaffold>(
    find.descendant(of: page, matching: find.byType(Scaffold)),
  );
  expect(scaffold.appBar, isNull);
  final systemStyle = tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: page,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      )
      .value;
  expect(systemStyle.statusBarIconBrightness, Brightness.dark);
  expect(systemStyle.statusBarBrightness, Brightness.light);
  expect(find.text('Page unavailable'), findsOneWidget);
  expect(find.text('Route Error'), findsNothing);
  expect(find.text('This page is unavailable.'), findsNothing);
  expect(find.byType(CustomAppBar), findsNothing);
  expect(find.byIcon(Icons.error_outline), findsOneWidget);
  expect(find.widgetWithText(CustomButton, 'Go to Home'), findsOneWidget);

  final centerX =
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
  expect(tester.getCenter(find.byIcon(Icons.error_outline)).dx, centerX);
  expect(tester.getCenter(find.text('Page unavailable')).dx, centerX);
  expect(tester.getCenter(find.text('Go to Home')).dx, centerX);
}

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

  expect(find.text('Verify seed phrase'), findsOneWidget);
  final questions = harness.container
      .read(createWalletViewModelProvider)
      .requireValue
      .questions;
  for (final question in questions) {
    await tester.tap(
      find.descendant(
        of: find.byType(CreateWalletQuizScreen),
        matching: find.byKey(
          ValueKey(
            'quiz-option-${question.wordNumber}-${question.expectedWord}',
          ),
        ),
      ),
    );
    await tester.pump();
  }
  expect(
    harness.container
        .read(createWalletViewModelProvider)
        .requireValue
        .quizComplete,
    isTrue,
  );
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
  bool useRealToasts = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: _RouterApp(
        harness: harness,
        platform: platform,
        useRealToasts: useRealToasts,
      ),
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
  const _RouterApp({
    required this.harness,
    this.platform,
    this.useRealToasts = false,
  });

  final OnboardingTestHarness harness;
  final TargetPlatform? platform;
  final bool useRealToasts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: AppTheme.light().copyWith(platform: platform),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => AsterFeedbackScope(
        haptics: harness.haptics,
        toasts: useRealToasts
            ? ref.read(toastControllerProvider.notifier)
            : harness.toasts,
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
  const frameDuration = Duration(milliseconds: 10);
  const motion = AsterMotion();
  final frameCount =
      motion.onboardingStepTransitionDuration.inMilliseconds ~/
          frameDuration.inMilliseconds +
      4;
  for (var frame = 0; frame < frameCount; frame += 1) {
    await tester.pump(frameDuration);
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
