import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
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

const _bitcoinTarget = WalletPaymentTarget.bitcoinOnchain;
const _validRegtestAddress = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (destination, message) in [
    (
      'not-a-bitcoin-address',
      'Enter a valid Bitcoin address or payment request.',
    ),
    (
      '1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
      'This Bitcoin address belongs to a different network.',
    ),
    (
      'bitcoin:$_validRegtestAddress?amount=invalid',
      'This Bitcoin payment request contains an invalid amount.',
    ),
  ]) {
    testWidgets(
      'rejected recipient stays on address with one warning: $message',
      (tester) async {
        final harness = await _harness(tester);
        final router = await _pumpAppRouter(
          tester,
          harness,
          RoutePaths.sendAddressFor(_bitcoinTarget.slug),
        );
        await _waitForRecipient(tester);
        final initialBalanceReads = harness.engine.calls
            .where((call) => call == 'balance')
            .length;
        await tester.enterText(find.byType(TextField), destination);
        await tester.pump();
        final continueButton = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, 'Continue'),
        );
        continueButton.onTap!();
        continueButton.onTap!();
        await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);

        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.sendAddressFor(_bitcoinTarget.slug),
        );
        expect(find.byType(SendAmountScreen), findsNothing);
        expect(find.byType(SendAddressCard), findsOneWidget);
        expect(find.text(message), findsNothing);
        expect(harness.toasts.messages, hasLength(1));
        expect(harness.toasts.messages.single.title, 'Check recipient');
        expect(harness.toasts.messages.single.message, message);
        expect(harness.toasts.messages.single.variant, ToastVariant.warning);
        expect(harness.engine.sentPaymentCommand, isNull);
        expect(
          harness.engine.calls.where((call) => call == 'balance'),
          hasLength(initialBalanceReads),
        );

        // Correcting the same form clears the rejection and is the only handoff.
        await tester.enterText(find.byType(TextField), _validRegtestAddress);
        await tester.pump();
        await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
        await _pumpUntil(
          tester,
          () => find.byType(SendAmountScreen).evaluate().isNotEmpty,
        );
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .matches
              .last
              .matchedLocation,
          '/send/${_bitcoinTarget.slug}/amount',
        );
        expect(harness.toasts.messages, hasLength(1));
        expect(harness.engine.sentPaymentCommand, isNull);
        expect(
          harness.engine.calls.where((call) => call == 'balance'),
          hasLength(initialBalanceReads + 1),
        );
      },
    );
  }

  testWidgets(
    'direct amount entry redirects before building an amount screen',
    (tester) async {
      final harness = await _harness(tester);
      final router = await _pumpAppRouter(
        tester,
        harness,
        '/send/${_bitcoinTarget.slug}/amount',
      );
      await _waitForRecipient(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.sendAddressFor(_bitcoinTarget.slug),
      );
      expect(find.byType(SendAmountScreen), findsNothing);
      expect(find.text('Enter recipient'), findsNothing);
      expect(find.textContaining('before choosing an amount'), findsNothing);
      expect(harness.toasts.messages, isEmpty);
      expect(harness.engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets(
    'Continue owns one selected-asset balance check before amount entry',
    (tester) async {
      const target = WalletPaymentTarget.usdtOnchain;
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(1000000)
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:recipient-review',
          displayDestination: 'rgb:recipient-review',
        );
      final harness = await _harness(
        tester,
        engine: engine,
        services: testRgbServices,
      );
      await _pumpAppRouter(
        tester,
        harness,
        RoutePaths.sendAddressFor(target.slug),
      );
      await _waitForRecipient(tester);
      final initialBalanceReads = engine.calls
          .where((call) => call == 'balance')
          .length;
      final balanceGate = Completer<void>();
      addTearDown(() {
        if (!balanceGate.isCompleted) balanceGate.complete();
      });
      engine
        ..balanceGate = balanceGate
        ..balance = testRgbBalance(750000);
      await tester.enterText(find.byType(TextField), 'rgb:recipient-review');
      await tester.pump();
      final continueButton = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Continue'),
      );
      continueButton.onTap!();
      continueButton.onTap!();
      await _pumpUntil(
        tester,
        () =>
            engine.calls.where((call) => call == 'balance').length >
            initialBalanceReads,
      );
      await tester.pump();

      expect(
        engine.calls.where((call) => call == 'balance'),
        hasLength(initialBalanceReads + 1),
      );
      expect(engine.requestedBalanceAsset, testRgbRoute.asset);
      expect(find.byType(SendAmountScreen), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final pending = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Continue'),
      );
      expect(pending.loading, isTrue);
      expect(pending.enabled, isFalse);
      expect(harness.toasts.messages, isEmpty);

      balanceGate.complete();
      await _pumpUntil(
        tester,
        () => find.byType(SendAmountScreen).evaluate().isNotEmpty,
      );
      final prepared = harness.container
          .read(sendFlowViewModelProvider(target))
          .requireValue;
      expect(prepared.availableUnits, 750000);
      expect(prepared.balancePreparedForDestination, isTrue);
      expect(harness.toasts.messages, isEmpty);
      expect(engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets(
    'a request expiring during the balance check stays on recipient',
    (tester) async {
      const target = WalletPaymentTarget.usdtOnchain;
      var now = DateTime.utc(2026, 10, 17, 12);
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(1000000)
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:recipient-review',
          displayDestination: 'rgb:recipient-review',
          expiresAt: now.add(const Duration(minutes: 1)),
        );
      final harness = await _harness(
        tester,
        engine: engine,
        services: testRgbServices,
        clock: () => now,
      );
      await _pumpAppRouter(
        tester,
        harness,
        RoutePaths.sendAddressFor(target.slug),
      );
      await _waitForRecipient(tester);
      final initialBalanceReads = engine.calls
          .where((call) => call == 'balance')
          .length;
      final balanceGate = Completer<void>();
      addTearDown(() {
        if (!balanceGate.isCompleted) balanceGate.complete();
      });
      engine.balanceGate = balanceGate;
      await tester.enterText(find.byType(TextField), 'rgb:recipient-review');
      await tester.pump();
      await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
      await _pumpUntil(
        tester,
        () =>
            engine.calls.where((call) => call == 'balance').length >
            initialBalanceReads,
      );
      now = now.add(const Duration(minutes: 2));
      balanceGate.complete();
      await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
      await _waitForRecipient(tester);

      expect(find.byType(SendAmountScreen), findsNothing);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Invoice expired');
      expect(
        harness.toasts.messages.single.message,
        'This invoice has expired. Enter a new invoice to continue.',
      );
      expect(harness.toasts.messages.single.variant, ToastVariant.warning);
      expect(
        harness.container
            .read(sendFlowViewModelProvider(target))
            .requireValue
            .balancePreparedForDestination,
        isFalse,
      );
      expect(engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets(
    'balance failure stays on recipient with one warning and deliberate retry',
    (tester) async {
      final harness = await _harness(tester);
      final engine = harness.engine;
      final router = await _pumpAppRouter(
        tester,
        harness,
        RoutePaths.sendAddressFor(_bitcoinTarget.slug),
      );
      await _waitForRecipient(tester);
      final initialBalanceReads = engine.calls
          .where((call) => call == 'balance')
          .length;
      const balanceFailure = AppFailure(
        code: 'balance_unavailable',
        kind: AppFailureKind.connectivity,
        userMessage: 'Could not check your balance. Try again.',
        retryable: true,
      );
      engine.balanceError = const AppFailureException(balanceFailure);
      await tester.enterText(find.byType(TextField), _validRegtestAddress);
      await tester.pump();
      await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
      await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
      await _waitForRecipient(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.sendAddressFor(_bitcoinTarget.slug),
      );
      expect(find.byType(SendAmountScreen), findsNothing);
      expect(find.text(balanceFailure.userMessage), findsNothing);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Balance unavailable');
      expect(
        harness.toasts.messages.single.message,
        balanceFailure.userMessage,
      );
      expect(harness.toasts.messages.single.variant, ToastVariant.warning);
      final provider = sendFlowViewModelProvider(_bitcoinTarget);
      expect(
        harness.container
            .read(provider)
            .requireValue
            .failureFor(SendFlowOperation.preparingAmount),
        balanceFailure,
      );
      expect(
        harness.container
            .read(provider)
            .requireValue
            .balancePreparedForDestination,
        isFalse,
      );
      expect(
        engine.calls.where((call) => call == 'balance'),
        hasLength(initialBalanceReads + 1),
      );

      // Retained failures do not launch another read or replay feedback.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      expect(
        engine.calls.where((call) => call == 'balance'),
        hasLength(initialBalanceReads + 1),
      );
      expect(harness.toasts.messages, hasLength(1));

      // A direct URL must not bypass the failed recipient Continue.
      router.go('/send/${_bitcoinTarget.slug}/amount');
      await tester.pump();
      await _waitForRecipient(tester);
      expect(find.byType(SendAmountScreen), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.sendAddressFor(_bitcoinTarget.slug),
      );
      expect(harness.toasts.messages, hasLength(1));

      engine.balanceError = null;
      await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
      await _pumpUntil(
        tester,
        () => find.byType(SendAmountScreen).evaluate().isNotEmpty,
      );
      expect(
        engine.calls.where((call) => call == 'balance'),
        hasLength(initialBalanceReads + 2),
      );
      expect(harness.toasts.messages, hasLength(1));
      expect(engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets('a validated recipient alone cannot bypass its balance check', (
    tester,
  ) async {
    final harness = await _harness(tester);
    final provider = sendFlowViewModelProvider(_bitcoinTarget);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination(_validRegtestAddress);
    expect(await notifier.validateDestination(), isTrue);
    expect(
      harness.container
          .read(provider)
          .requireValue
          .balancePreparedForDestination,
      isFalse,
    );
    final initialBalanceReads = harness.engine.calls
        .where((call) => call == 'balance')
        .length;
    final router = await _pumpAppRouter(
      tester,
      harness,
      '/send/${_bitcoinTarget.slug}/amount',
    );
    await _waitForRecipient(tester);

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.sendAddressFor(_bitcoinTarget.slug),
    );
    expect(find.byType(SendAmountScreen), findsNothing);
    expect(
      harness.engine.calls.where((call) => call == 'balance'),
      hasLength(initialBalanceReads),
    );
    expect(harness.toasts.messages, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
  });

  for (final rejected in [false, true]) {
    testWidgets(
      'covered route suppresses late balance ${rejected ? 'failure' : 'success'}',
      (tester) async {
        final harness = await _harness(tester);
        final engine = harness.engine;
        final router = GoRouter(
          initialLocation: RoutePaths.sendAddressFor(_bitcoinTarget.slug),
          routes: [
            GoRoute(
              path: RoutePaths.sendAddress,
              name: RouteNames.sendAddress,
              builder: (_, _) =>
                  const SendAddressScreen(target: _bitcoinTarget),
            ),
            GoRoute(
              path: RoutePaths.sendAmount,
              name: RouteNames.sendAmount,
              builder: (_, _) =>
                  const Scaffold(body: Text('Unexpected amount entry')),
            ),
            GoRoute(
              path: '/covered',
              builder: (_, _) => const Scaffold(body: Text('Covering screen')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await _pumpRouter(tester, harness, router);
        await _waitForRecipient(tester);
        final initialBalanceReads = engine.calls
            .where((call) => call == 'balance')
            .length;
        final balanceGate = Completer<void>();
        addTearDown(() {
          if (!balanceGate.isCompleted) balanceGate.complete();
        });
        engine.balanceGate = balanceGate;
        if (rejected) {
          engine.balanceError = const AppFailureException(
            AppFailure(
              code: 'balance_unavailable',
              kind: AppFailureKind.connectivity,
              userMessage: 'Could not check your balance. Try again.',
              retryable: true,
            ),
          );
        }
        await tester.enterText(find.byType(TextField), _validRegtestAddress);
        await tester.pump();
        await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
        await _pumpUntil(
          tester,
          () =>
              engine.calls.where((call) => call == 'balance').length >
              initialBalanceReads,
        );
        unawaited(router.push<void>('/covered'));
        await _pumpUntil(
          tester,
          () => find.text('Covering screen').evaluate().isNotEmpty,
        );
        balanceGate.complete();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Covering screen'), findsOneWidget);
        expect(find.text('Unexpected amount entry'), findsNothing);
        expect(harness.toasts.messages, isEmpty);
        expect(engine.sentPaymentCommand, isNull);
      },
    );
  }

  testWidgets('an unresolved amount load stays on recipient entry', (
    tester,
  ) async {
    final balanceGate = Completer<void>();
    final engine = FakeWalletEngine()..balanceGate = balanceGate;
    final harness = await _harness(tester, engine: engine);
    final router = await _pumpAppRouter(
      tester,
      harness,
      '/send/${_bitcoinTarget.slug}/amount',
    );
    addTearDown(() {
      if (!balanceGate.isCompleted) balanceGate.complete();
    });
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.sendAddressFor(_bitcoinTarget.slug),
    );
    expect(find.byType(SendAmountScreen), findsNothing);
    balanceGate.complete();
    await _waitForRecipient(tester);
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets('rejected revalidation cannot reuse a previous valid preview', (
    tester,
  ) async {
    const target = WalletPaymentTarget.usdtOnchain;
    final engine = FakeWalletEngine()
      ..balance = testRgbBalance(1000000)
      ..decodedInvoice = WalletPaymentPreview(
        route: testRgbRoute,
        encodedDestination: 'rgb:recipient-review',
        displayDestination: 'rgb:recipient-review',
      );
    final harness = await _harness(
      tester,
      engine: engine,
      services: testRgbServices,
    );
    final provider = sendFlowViewModelProvider(target);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('rgb:recipient-review');
    expect(await notifier.validateDestination(), isTrue);
    engine.decodeInvoiceError = const AppFailureException(
      AppFailure(
        code: 'payment_destination_invalid',
        kind: AppFailureKind.validation,
        userMessage: 'Enter a valid payment destination.',
        retryable: false,
      ),
    );
    expect(await notifier.validateDestination(), isFalse);
    final router = await _pumpAppRouter(
      tester,
      harness,
      '/send/${target.slug}/amount',
    );
    await _waitForRecipient(tester);

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.sendAddressFor(target.slug),
    );
    expect(find.byType(SendAmountScreen), findsNothing);
    expect(find.text('Enter a valid payment destination.'), findsNothing);
    expect(harness.toasts.messages, isEmpty);
    expect(engine.sentPaymentCommand, isNull);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'late recipient validation cannot navigate from a covered route',
    (tester) async {
      const target = WalletPaymentTarget.usdtOnchain;
      final decodeGate = Completer<void>();
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(1000000)
        ..decodeInvoiceGate = decodeGate
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:recipient-review',
          displayDestination: 'rgb:recipient-review',
        );
      final harness = await _harness(
        tester,
        engine: engine,
        services: testRgbServices,
      );
      addTearDown(() {
        if (!decodeGate.isCompleted) decodeGate.complete();
      });
      final router = GoRouter(
        initialLocation: RoutePaths.sendAddressFor(target.slug),
        routes: [
          GoRoute(
            path: RoutePaths.sendAddress,
            name: RouteNames.sendAddress,
            builder: (_, _) => const SendAddressScreen(target: target),
          ),
          GoRoute(
            path: RoutePaths.sendAmount,
            name: RouteNames.sendAmount,
            builder: (_, _) =>
                const Scaffold(body: Text('Unexpected amount entry')),
          ),
          GoRoute(
            path: '/covered',
            builder: (_, _) => const Scaffold(body: Text('Covering screen')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pumpRouter(tester, harness, router);
      await _waitForRecipient(tester);
      await tester.enterText(find.byType(TextField), 'rgb:recipient-review');
      await tester.pump();
      await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
      await _pumpUntil(
        tester,
        () => engine.calls.contains('decodeInvoice:start'),
      );
      unawaited(router.push<void>('/covered'));
      await _pumpUntil(
        tester,
        () => find.text('Covering screen').evaluate().isNotEmpty,
      );
      decodeGate.complete();
      await _pumpUntil(
        tester,
        () => engine.calls.contains('decodeInvoice:end'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Covering screen'), findsOneWidget);
      expect(find.text('Unexpected amount entry'), findsNothing);
      expect(harness.toasts.messages, isEmpty);
      expect(engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets('building the app router does not start Send prerequisites', (
    tester,
  ) async {
    final harness = await _harness(tester);
    await harness.container.read(walletViewModelProvider.future);
    harness.container.read(appRouterProvider);
    await tester.pump();
    for (final target in WalletPaymentTarget.values) {
      expect(
        harness.container.exists(sendFlowViewModelProvider(target)),
        isFalse,
      );
    }
    await tester.pump(const Duration(milliseconds: 1));
  });

  for (final rejected in [false, true]) {
    testWidgets(
      'wallet change suppresses late recipient ${rejected ? 'failure' : 'success'}',
      (tester) async {
        const target = WalletPaymentTarget.usdtOnchain;
        final decodeGate = Completer<void>();
        final engine = FakeWalletEngine()
          ..balance = testRgbBalance(1000000)
          ..decodeInvoiceGate = decodeGate
          ..decodedInvoice = WalletPaymentPreview(
            route: testRgbRoute,
            encodedDestination: 'rgb:recipient-review',
            displayDestination: 'rgb:recipient-review',
          );
        if (rejected) {
          engine.decodeInvoiceError = const AppFailureException(
            AppFailure(
              code: 'payment_destination_invalid',
              kind: AppFailureKind.validation,
              userMessage: 'Enter a valid payment destination.',
              retryable: false,
            ),
          );
        }
        final harness = await _harness(
          tester,
          engine: engine,
          services: testRgbServices,
        );
        addTearDown(() {
          if (!decodeGate.isCompleted) decodeGate.complete();
        });
        final initialWallet = await harness.container.read(
          walletViewModelProvider.future,
        );
        final router = GoRouter(
          initialLocation: RoutePaths.sendAddressFor(target.slug),
          routes: [
            GoRoute(
              path: RoutePaths.sendAddress,
              name: RouteNames.sendAddress,
              builder: (_, _) => const SendAddressScreen(target: target),
            ),
            GoRoute(
              path: RoutePaths.sendAmount,
              name: RouteNames.sendAmount,
              builder: (_, _) =>
                  const Scaffold(body: Text('Unexpected amount entry')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await _pumpRouter(tester, harness, router);
        await _waitForRecipient(tester);
        await tester.enterText(find.byType(TextField), 'rgb:recipient-review');
        await tester.pump();
        await tester.tap(find.widgetWithText(CustomButton, 'Continue'));
        await _pumpUntil(
          tester,
          () => engine.calls.contains('decodeInvoice:start'),
        );
        final nextWallet = WalletProfile(
          id: '22222222222222222222222222222222',
          name: 'Other wallet',
          createdAt: DateTime.utc(2026, 10, 17),
          updatedAt: DateTime.utc(2026, 10, 17),
          environment: BlockchainEnvironment.regtest,
          state: WalletProfileState.ready,
          storageToken: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        );
        // Publish the same identity transition as a committed wallet switch.
        // The test never provisions or opens another native wallet.
        harness.container
            .read(walletViewModelProvider.notifier)
            .adoptCommittedRegistry(
              WalletRegistry(
                profiles: [...initialWallet.wallets, nextWallet],
                activeWalletId: nextWallet.id,
              ),
            );
        decodeGate.complete();
        await _pumpUntil(
          tester,
          () => engine.calls.contains('decodeInvoice:end'),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SendAddressScreen), findsOneWidget);
        expect(find.text('Unexpected amount entry'), findsNothing);
        expect(harness.toasts.messages, isEmpty);
        expect(engine.sentPaymentCommand, isNull);
      },
    );
  }
}

Future<PaymentFlowTestHarness> _harness(
  WidgetTester tester, {
  FakeWalletEngine? engine,
  UtcClock? clock,
  WalletServiceConfiguration services = const WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  ),
}) async {
  final transport = ResilientHttpClient(
    client: MockClient((_) async => http.Response('{}', 503)),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
  final harness = await PaymentFlowTestHarness.create(
    engine: engine,
    services: services,
    httpClient: transport,
    clock: clock,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final disposal = harness.dispose();
    for (var frame = 0; frame < 3; frame += 1) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await disposal;
    transport.close();
  });
  return harness;
}

Future<GoRouter> _pumpAppRouter(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
  String location,
) async {
  await harness.container.read(walletViewModelProvider.future);
  final subscription = harness.container.listen(appRouterProvider, (_, _) {});
  addTearDown(subscription.close);
  final router = harness.container.read(appRouterProvider);
  router.go(location);
  await _pumpRouter(tester, harness, router);
  return router;
}

Future<void> _pumpRouter(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
  GoRouter router,
) async {
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
        builder: (_, child) => AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: harness.toasts,
          child: child!,
        ),
      ),
    ),
  );
}

Future<void> _waitForRecipient(WidgetTester tester) => _pumpUntil(
  tester,
  () => find
      .byWidgetPredicate(
        (widget) => widget is TextField && widget.enabled == true,
      )
      .evaluate()
      .isNotEmpty,
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for recipient navigation.');
}
