import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/market/data/data.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Send selector exposes four targets and routes by stable slug', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final capabilitySubscription = harness.container.listen(
      walletPaymentCapabilitiesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(capabilitySubscription.close);
    await tester.runAsync(
      () => harness.container.read(walletPaymentCapabilitiesProvider.future),
    );
    final router = GoRouter(
      initialLocation: RoutePaths.send,
      routes: [
        GoRoute(
          path: RoutePaths.send,
          name: RouteNames.send,
          builder: (context, state) => const SendScreen(),
        ),
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (context, state) =>
              Text(state.pathParameters[RoutePaths.paymentTargetParameter]!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    await _pumpUntil(
      tester,
      () => find.byType(PaymentTargetTile).evaluate().length == 4,
    );

    expect(
      router.namedLocation(
        RouteNames.sendAddress,
        pathParameters: const {
          RoutePaths.paymentTargetParameter: 'bitcoin-onchain',
        },
      ),
      '/send/bitcoin-onchain/address',
    );
    expect(find.textContaining('Not configured'), findsNWidgets(2));
    final usdtOnchain = find.byWidgetPredicate(
      (widget) =>
          widget is PaymentTargetTile &&
          widget.capability.target == WalletPaymentTarget.usdtOnchain,
    );
    expect(
      tester.getSemantics(usdtOnchain).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      find.descendant(
        of: usdtOnchain,
        matching: find.byIcon(MingCuteIcons.mgc_right_line),
      ),
      findsNothing,
    );
    await tester.tap(usdtOnchain);
    expect(harness.haptics.intents, isEmpty);
    await tester.tap(find.text('On-chain'));
    await tester.pumpAndSettle();

    expect(harness.haptics.intents, contains(HapticIntent.selection));
    expect(find.text('bitcoin-onchain'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('payment target selection supports compact 2x text accessibly', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const SendScreen(),
      textScaler: const TextScaler.linear(2),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PaymentTargetTile).evaluate().length == 4,
    );

    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('direct amount deep link fails closed without a recipient', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.text('Enter recipient').evaluate().isNotEmpty,
    );

    expect(
      find.text('Enter and validate a recipient before choosing an amount.'),
      findsOneWidget,
    );
    expect(harness.engine.sentPaymentCommand, isNull);
  });

  testWidgets('send removes a USD quote at its exact freshness boundary', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 11, 12);
    final observedAt = clockNow.subtract(
      BitcoinMarketSnapshot.maximumCurrentAge - const Duration(seconds: 1),
    );
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            jsonEncode({
              'prices': [
                [
                  clockNow
                      .subtract(const Duration(minutes: 10))
                      .millisecondsSinceEpoch,
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
              'last_updated_at': observedAt.millisecondsSinceEpoch ~/ 1000,
            },
          }),
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
      clock: () => clockNow,
    );
    addTearDown(transport.close);
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: clockNow,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      httpClient: transport,
      clock: () => clockNow,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);

    await _pumpWidget(
      tester,
      harness,
      const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    final keypad = find.byType(AsterNumericKeypad);
    for (final digit in ['0', '.', '0', '0', '0', '0', '0', '1']) {
      await tester.tap(find.descendant(of: keypad, matching: find.text(digit)));
      await tester.pump();
    }
    await _pumpUntil(tester, () => find.text('≈ \$0.07').evaluate().isNotEmpty);

    clockNow = clockNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('USD quote unavailable'), findsOneWidget);
  });

  testWidgets('Receive renders real request, copies it, and applies amount', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );

    expect(find.text('Direct Peg In'), findsNothing);
    await tester.tap(find.widgetWithText(CustomButton, 'Copy'));
    await _pumpFrames(tester);
    expect(harness.clipboard.text, 'request-bitcoin-onchain');

    await tester.scrollUntilVisible(
      find.text('Generate new request'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Generate new request'), findsOneWidget);
    await tester.tap(find.text('Set amount').first);
    await _pumpFrames(tester);
    expect(find.byType(AsterNumericKeypad), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AsterNumericKeypad),
        matching: find.text('1'),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
    await _pumpUntil(
      tester,
      () => find.byType(ReceiveAmountSheet).evaluate().isEmpty,
    );

    expect(harness.engine.createdReceiveAmount?.units, 100000000);
  });

  testWidgets('Send amount stays loading until one real mutation completes', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            jsonEncode({
              'prices': [
                [
                  now
                      .subtract(const Duration(minutes: 1))
                      .millisecondsSinceEpoch,
                  65000,
                ],
                [now.millisecondsSinceEpoch, 65000],
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
    addTearDown(transport.close);
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..sendPaymentGate = Completer<void>()
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      httpClient: transport,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(provider);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await _pumpUntil(tester, () {
      final state = harness.container.read(provider);
      return state.hasValue || state.hasError;
    });
    expect(
      harness.container.read(provider).hasError,
      isFalse,
      reason: harness.container.read(provider).toString(),
    );
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);

    final router = GoRouter(
      initialLocation: '/send/bitcoin-onchain/amount',
      routes: [
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (context, state) => const SendAmountScreen(
            target: WalletPaymentTarget.bitcoinOnchain,
          ),
        ),
        GoRoute(
          path: RoutePaths.skeleton,
          builder: (context, state) => const Text('Wallet home'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );

    final keypad = find.byType(AsterNumericKeypad);
    for (final digit in ['0', '.', '0', '0', '0', '0', '0', '1']) {
      await tester.tap(find.descendant(of: keypad, matching: find.text(digit)));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(CustomButton, 'Send'));
    await _pumpFrames(tester);

    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(find.text('Wallet home'), findsNothing);
    expect(sendButton, findsOneWidget);
    expect(tester.widget<CustomButton>(sendButton).loading, isTrue);
    expect(find.byType(GridLoader), findsOneWidget);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    await tester.tap(sendButton);
    await _pumpFrames(tester);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );

    engine.sendPaymentGate!.complete();
    await _pumpUntil(
      tester,
      () => find.text('Wallet home').evaluate().isNotEmpty,
    );

    expect(engine.sentPaymentCommand?.amount.units, 100);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(harness.toasts.messages.last.title, 'Payment submitted');
  });
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

Future<void> _pumpWidget(
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
            final scaler = textScaler;
            if (scaler == null) return content;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: content,
            );
          },
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
  fail('Timed out waiting for payment UI state.');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _disposeHarness(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final disposal = harness.dispose();
  for (var frame = 0; frame < 3; frame += 1) {
    await tester.pump();
  }
  await disposal;
}

WalletBalance _bitcoinBalance(int spendable) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(spendable),
    onchainFuture: onchain(spendable),
    onchainSpendable: onchain(spendable),
    onchainLocked: onchain(0),
    lightningOwned: lightning(0),
    lightningSpendable: lightning(0),
    lightningReceivable: lightning(0),
  );
}
