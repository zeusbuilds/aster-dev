import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/domain/validation/validation.dart';
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

  testWidgets(
    'L1 Send explicitly reviews output preparation and never auto-sends',
    (tester) async {
      final now = DateTime.utc(2026, 11, 7);
      final store = _SendSetupStore();
      final engine = _SendSetupEngine()
        ..balances[testRgbRoute.asset.id] = testRgbBalance(2000000)
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:witness',
          displayDestination: 'rgb:witness',
          rgbRecipientType: RgbRecipientType.witness,
        )
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 1,
          observedAt: now,
          source: WalletFeeRateSource.localRegtestPolicy,
        );
      final transport = ResilientHttpClient(
        client: MockClient((_) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      // Only the presentation policy is mocked. The actual L1 factory remains
      // closed; an isolated fake runtime exercises the existing real journal.
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        services: testRgbServices,
        rgbSetupStore: store,
        presentationServices: const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          backend: WalletBackend.rgbL1,
        ),
        clock: () => now,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      const target = WalletPaymentTarget.usdtOnchain;
      final provider = sendFlowViewModelProvider(target);
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: target),
      );
      await _pumpUntil(tester, () => harness.container.read(provider).hasValue);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('rgb:witness');
      final validated = notifier.validateDestination();
      await _pumpFrames(tester);
      expect(await validated, isTrue);
      notifier.updateAmount('1');
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: target),
      );
      final send = find.widgetWithText(CustomButton, 'Send');
      await _pumpUntil(tester, () => send.evaluate().isNotEmpty);
      await tester.tap(send);
      await _pumpUntil(
        tester,
        () => find.text('Prepare wallet for USDT?').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('total fee cap is unavailable'),
        findsOneWidget,
      );
      expect(engine.setupDispatches, 0);
      expect(engine.sentPaymentCommand, isNull);
      await tester.tap(find.widgetWithText(CustomButton, 'Cancel'));
      await _pumpFrames(tester);
      expect(engine.setupDispatches, 0);
      await tester.tap(send);
      await _pumpUntil(
        tester,
        () => find.text('Prepare wallet for USDT?').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(CustomButton, 'Prepare'));
      await _pumpUntil(tester, () => engine.setupDispatches == 1);
      await _pumpFrames(tester);
      expect(engine.sentPaymentCommand, isNull);
      expect(harness.toasts.messages.single.title, 'Preparation pending');
      // The durable marker survives subsequent taps. Only a status read occurs.
      await tester.tap(send);
      await _pumpFrames(tester);
      expect(engine.setupDispatches, 1);
      expect(find.text('Prepare wallet for USDT?'), findsNothing);
      expect(engine.sentPaymentCommand, isNull);
    },
  );

  testWidgets('Paste reads once quietly and recovers after clipboard failure', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final gate = Completer<void>();
    harness.clipboard
      ..readGate = gate
      ..readFailure = const AppFailure(
        code: 'clipboard_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Clipboard could not be read.',
        retryable: true,
      );
    const target = WalletPaymentTarget.bitcoinOnchain;
    final provider = sendFlowViewModelProvider(target);
    await _pumpWidget(tester, harness, const SendAddressScreen(target: target));
    final paste = find.widgetWithText(CustomButton, 'Paste');
    await _pumpUntil(
      tester,
      () => paste.evaluate().any(
        (element) => (element.widget as CustomButton).onTap != null,
      ),
    );
    final original = tester.widget<CustomButton>(paste);
    final before = tester.getRect(paste);
    original.onTap!();
    original.onTap!();
    await tester.pump();
    expect(tester.widget<CustomButton>(paste).loading, false);
    expect(tester.widget<CustomButton>(paste).enabled, true);
    expect(tester.getRect(paste), before);
    expect(
      harness.container.read(provider).requireValue.operation,
      SendFlowOperation.readingClipboard,
    );
    final semantics = tester.getSemantics(find.bySemanticsLabel('Paste'));
    expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(
      semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      false,
    );
    await tester.tap(paste, warnIfMissed: false);
    expect(harness.toasts.messages, isEmpty);
    gate.complete();
    await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.title, 'Could not paste');
    expect(find.text('Clipboard could not be read.'), findsNothing);

    harness.clipboard
      ..readFailure = null
      ..text = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    await tester.tap(paste);
    await _pumpUntil(
      tester,
      () => find.widgetWithText(CustomButton, 'Clear').evaluate().isNotEmpty,
    );
    expect(
      harness.container.read(provider).requireValue.destination,
      'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
    );
    expect(harness.toasts.messages, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final (name, screen) in [
    ('Send', const SendScreen()),
    ('Receive', const ReceiveScreen()),
  ]) {
    testWidgets(
      '$name lists on-chain assets first and scrolls to bottom edge',
      (tester) async {
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final harness = await PaymentFlowTestHarness.create(
          services: testRgbServices,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        await _pumpWidget(tester, harness, screen);
        await tester.pumpAndSettle();

        final tiles = tester.widgetList<PaymentTargetTile>(
          find.byType(PaymentTargetTile),
        );
        expect(tiles.map((tile) => tile.capability.target), [
          WalletPaymentTarget.bitcoinOnchain,
          WalletPaymentTarget.usdtOnchain,
          WalletPaymentTarget.bitcoinLightning,
          WalletPaymentTarget.usdtLightning,
        ]);
        for (final target in [
          WalletPaymentTarget.bitcoinLightning,
          WalletPaymentTarget.usdtLightning,
        ]) {
          final tile = find.byWidgetPredicate(
            (widget) =>
                widget is PaymentTargetTile &&
                widget.capability.target == target,
          );
          final semantics = tester.getSemantics(tile);
          expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
          expect(
            semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          await tester.tap(tile);
        }
        expect(harness.haptics.intents, isEmpty);
        final list = find.byType(ListView);
        expect(tester.getRect(list).bottom, 844);
        expect(
          tester
              .widget<ListView>(list)
              .padding!
              .resolve(TextDirection.ltr)
              .bottom,
          greaterThan(34),
        );
      },
    );
  }

  testWidgets(
    'a changed fee updates within one Send action and requires another tap',
    (tester) async {
      final now = DateTime.utc(2026, 10, 15);
      WalletFeeRateEstimate rate(int value) => WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: value,
        observedAt: now,
      );
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance(1000)
        ..feeEstimate = rate(3);
      final transport = ResilientHttpClient(
        client: MockClient((request) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
      );
      await _pumpUntil(tester, () => harness.container.read(provider).hasValue);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      final validation = notifier.validateDestination();
      await _pumpFrames(tester);
      expect(await validation, isTrue);
      notifier.updateAmount('0.00000001');
      await _pumpFrames(tester);
      engine.feeEstimate = rate(4);
      await tester.ensureVisible(find.widgetWithText(CustomButton, 'Send'));
      await _pumpFrames(tester);
      await tester.tap(find.widgetWithText(CustomButton, 'Send'));
      await _pumpUntil(
        tester,
        () =>
            harness.container.read(provider).value?.failure?.code ==
            walletFeeUpdatedReviewFailure.code,
      );
      expect(
        find.text(
          'The fee changed. Review the updated rate before sending again.',
        ),
        findsNothing,
      );
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.variant, ToastVariant.warning);
      expect(harness.toasts.messages.single.title, 'Review network fee');
      expect(
        harness.toasts.messages.single.message,
        'The fee is updated. Review it and send again.',
      );
      expect(
        tester
            .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
            .enabled,
        isTrue,
      );
      expect(find.text('Refresh fee'), findsNothing);
      expect(find.text('Refresh balance'), findsNothing);
      expect(engine.calls, isNot(contains('sendPayment:start')));
      final readsAfterAction = engine.calls
          .where((call) => call == 'estimateFeeRate')
          .length;
      await tester.pump(const Duration(seconds: 20));
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsAfterAction),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(find.text('4 sats/vbyte'), findsOneWidget);
      expect(
        tester
            .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
            .enabled,
        isTrue,
      );
      final accepted = notifier.submit();
      await _pumpFrames(tester);
      expect(await accepted, isTrue);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(engine.sentPaymentCommand!.feeRate!.satsPerVbyte, 4);
    },
  );

  testWidgets(
    'stale fees never retry on timers, route return or foreground resume',
    (tester) async {
      var now = DateTime.utc(2026, 10, 16);
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance(1000)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final transport = ResilientHttpClient(
        client: MockClient((request) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      const target = WalletPaymentTarget.bitcoinOnchain;
      final provider = sendFlowViewModelProvider(target);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await tester.runAsync(() => harness.container.read(provider.future));
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await tester.runAsync(notifier.validateDestination), isTrue);
      notifier.updateAmount('0.00000001');
      final router = GoRouter(
        initialLocation: '/send/bitcoin-onchain/amount',
        routes: [
          GoRoute(
            path: RoutePaths.sendAmount,
            builder: (_, _) => const SendAmountScreen(target: target),
          ),
          GoRoute(
            path: '/covered',
            builder: (_, _) => const Scaffold(body: Text('Covered')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pumpRouter(tester, harness, router);
      await _pumpUntil(
        tester,
        () => find.byType(SendCard).evaluate().isNotEmpty,
      );
      await _pumpFrames(tester);
      final readsBefore = engine.calls
          .where((call) => call == 'estimateFeeRate')
          .length;
      engine.feeEstimateError = TimeoutException('temporary fee outage');
      unawaited(router.push<void>('/covered'));
      await tester.pumpAndSettle();
      now = now.add(
        WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
      );
      await tester.pump(
        WalletFeeRateEstimate.maximumAge + const Duration(seconds: 3),
      );
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore),
      );
      router.pop();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 10));
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore),
      );
      final lifecycle = harness.container.read(
        walletLifecycleViewModelProvider.notifier,
      );
      await lifecycle.handle(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore),
      );
      await lifecycle.handle(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 5));
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore),
      );
      expect(harness.toasts.messages, isEmpty);
      expect(find.text('Unavailable'), findsOneWidget);
      final send = find.widgetWithText(CustomButton, 'Send');
      expect(tester.widget<CustomButton>(send).enabled, isTrue);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pumpUntil(
        tester,
        () => harness.container.read(provider).value?.feeFailure != null,
      );
      await _pumpFrames(tester);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore + 1),
      );
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Network fee unavailable');
      await tester.pump(const Duration(minutes: 5));
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBefore + 1),
      );
      expect(harness.toasts.messages, hasLength(1));
      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(find.text('Refresh fee'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'witness send discloses and binds the additional recipient Bitcoin output',
    (tester) async {
      final now = DateTime.utc(2026, 10, 15);
      final engine = FakeWalletEngine()
        ..balances[testRgbRoute.asset.id] = testRgbBalance(2000000)
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:witness',
          displayDestination: 'rgb:witness',
          rgbRecipientType: RgbRecipientType.witness,
        )
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 1,
          observedAt: now,
          source: WalletFeeRateSource.localRegtestPolicy,
        );
      final transport = ResilientHttpClient(
        client: MockClient((request) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        services: testRgbServices,
        clock: () => now,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.usdtOnchain,
      );
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: WalletPaymentTarget.usdtOnchain),
      );
      await _pumpUntil(tester, () => harness.container.read(provider).hasValue);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('rgb:witness');
      final validation = notifier.validateDestination();
      await _pumpFrames(tester);
      expect(await validation, isTrue);
      notifier.updateAmount('1');
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: WalletPaymentTarget.usdtOnchain),
      );
      await _pumpUntil(
        tester,
        () => find.text('Recipient Bitcoin output').evaluate().isNotEmpty,
      );
      expect(find.text('1,000 sats'), findsOneWidget);
      expect(
        find.textContaining(
          'Sends 1,000 sats to recipient in addition to network fee',
        ),
        findsNothing,
      );
      expect(engine.sentPaymentCommand, isNull);
      final submission = notifier.submit();
      await _pumpFrames(tester);
      expect(await submission, isTrue);
      expect(
        engine.sentPaymentCommand?.rgbRecipientType,
        RgbRecipientType.witness,
      );
      expect(engine.sentPaymentCommand?.witnessBitcoinAmountSats, 1000);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );

  testWidgets('Send displays the local regtest fee policy honestly', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 15);
    final engine = FakeWalletEngine()
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 1,
        observedAt: now,
        source: WalletFeeRateSource.localRegtestPolicy,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
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
      () => find.text('Local test fee rate').evaluate().isNotEmpty,
    );
    expect(find.text('Network fee rate'), findsNothing);
    expect(find.text('1 sats/vbyte'), findsOneWidget);
    await _pumpFrames(tester);
  });

  testWidgets(
    'Max fills available BTC and Send warns to leave its network fee',
    (tester) async {
      final now = DateTime.utc(2026, 10, 16);
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance(1000)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final transport = ResilientHttpClient(
        client: MockClient((request) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      const target = WalletPaymentTarget.bitcoinOnchain;
      final provider = sendFlowViewModelProvider(target);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await tester.runAsync(() => harness.container.read(provider.future));
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await tester.runAsync(notifier.validateDestination), isTrue);
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: target),
      );
      await _pumpUntil(
        tester,
        () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
      );
      final readsBeforeMax = engine.calls.length;
      await tester.tap(find.widgetWithText(CustomButton, 'Max'));
      await _pumpFrames(tester);

      expect(
        harness.container.read(provider).requireValue.amountInput.units,
        1000,
      );
      expect(
        tester.widget<WalletAmountEntry>(find.byType(WalletAmountEntry)).value,
        '0.00001',
      );
      expect(engine.calls, hasLength(readsBeforeMax));
      expect(harness.toasts.messages, isEmpty);
      final card = find.byType(SendCard);
      expect(
        find.descendant(of: card, matching: find.text('On-chain')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Address')),
        findsNothing,
      );
      final details = tester
          .widgetList<DetailRow>(find.byType(DetailRow))
          .toList();
      expect(details.map((row) => row.title), ['Network fee rate']);
      expect(
        find.bySemanticsLabel('Address, mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn'),
        findsOneWidget,
      );
      expect(find.textContaining('quote unavailable'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(CustomButton, 'Send'));
      await tester.tap(find.widgetWithText(CustomButton, 'Send'));
      await _pumpFrames(tester);

      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(engine.sentPaymentCommand, isNull);
      expect(harness.toasts.messages, hasLength(1));
      final feedback = harness.toasts.messages.single;
      expect(feedback.title, 'Check amount');
      expect(feedback.variant, ToastVariant.warning);
      expect(
        feedback.message,
        'Leave some BTC for the network fee. Lower the amount and try again.',
      );
      expect(find.text(feedback.message!), findsNothing);
      expect(harness.haptics.intents, isNot(contains(HapticIntent.error)));
      expect(harness.haptics.intents, contains(HapticIntent.warning));

      // A deliberate attempt after editing must explain the same fee
      // requirement again. Automatic rebuilds must remain deduplicated.
      notifier.updateAmount('0.000009');
      await _pumpFrames(tester);
      await tester.ensureVisible(find.widgetWithText(CustomButton, 'Max'));
      await tester.tap(find.widgetWithText(CustomButton, 'Max'));
      await _pumpFrames(tester);
      expect(
        harness.container.read(provider).requireValue.amountInput.units,
        1000,
      );
      await tester.ensureVisible(find.widgetWithText(CustomButton, 'Send'));
      await tester.tap(find.widgetWithText(CustomButton, 'Send'));
      await _pumpFrames(tester);
      expect(harness.toasts.messages, hasLength(2));
      expect(harness.toasts.messages.last.title, feedback.title);
      expect(harness.toasts.messages.last.message, feedback.message);
      expect(harness.toasts.messages.last.variant, ToastVariant.warning);
      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(engine.sentPaymentCommand, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(harness.toasts.messages, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Send selector exposes four targets and routes by stable slug', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
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
    expect(find.textContaining('Not configured'), findsOneWidget);
    expect(find.textContaining('Coming later'), findsNWidgets(2));
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

  testWidgets('leaving Send clears an unconsumed scanned destination', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    harness.container
        .read(sendDestinationHandoffProvider.notifier)
        .stage('lightning:unconsumed');
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: RoutePaths.send,
          name: RouteNames.send,
          builder: (context, state) => const SendScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);

    unawaited(router.pushNamed(RouteNames.send));
    await tester.pumpAndSettle();
    expect(harness.container.read(sendDestinationHandoffProvider), isNotNull);

    router.pop();
    await tester.pumpAndSettle();

    expect(harness.container.read(sendDestinationHandoffProvider), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment target selection supports compact 2x text accessibly', (
    tester,
  ) async {
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));
      await _pumpWidget(
        tester,
        harness,
        const SendScreen(),
        textScaler: const TextScaler.linear(2),
      );
      final selection = find.byType(PaymentTargetSelectionView);
      expect(
        tester.widget<PaymentTargetSelectionView>(selection).capabilities,
        hasLength(4),
      );
      expect(find.bySemanticsLabel('Loading payment options'), findsNothing);

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      final scrollable = find.descendant(
        of: selection,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      final initialOffset = position.pixels;
      expect(position.maxScrollExtent, greaterThan(0));
      final lastTarget = find.byWidgetPredicate(
        (widget) =>
            widget is PaymentTargetTile &&
            widget.capability.target == WalletPaymentTarget.usdtLightning,
      );
      bool lastTargetFullyVisible() {
        if (lastTarget.evaluate().isEmpty) return false;
        final viewport = tester.getRect(scrollable);
        final tile = tester.getRect(lastTarget);
        return tile.top >= viewport.top && tile.bottom <= viewport.bottom;
      }

      expect(lastTargetFullyVisible(), isFalse);
      for (var drag = 0; drag < 5 && !lastTargetFullyVisible(); drag += 1) {
        final beforeDrag = position.pixels;
        await tester.drag(scrollable, const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(beforeDrag));
      }
      expect(position.pixels, greaterThan(initialOffset));
      expect(lastTarget, findsOneWidget);
      expect(lastTargetFullyVisible(), isTrue);
      expect(lastTarget.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
    }
  });

  testWidgets('payment target selection suppresses same-turn route commands', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final navigationGate = Completer<void>();
    var selectionCount = 0;
    final capability = WalletPaymentCapability.available(
      const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
    );
    await _pumpWidget(
      tester,
      harness,
      PaymentTargetSelectionView(
        capabilities: [capability],
        onSelected: (target) async {
          selectionCount += 1;
          await navigationGate.future;
        },
      ),
    );

    final tile = find.byType(PaymentTargetTile);
    final targetTile = tester.widget<PaymentTargetTile>(tile);
    targetTile.onSelected!(capability.target);
    targetTile.onSelected!(capability.target);

    expect(selectionCount, 1);
    expect(harness.haptics.intents, [HapticIntent.selection]);

    await tester.pump();
    expect(
      tester.getSemantics(tile).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );

    navigationGate.complete();
    await tester.pump();
    expect(
      tester.getSemantics(tile).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('payment navigation faults are redacted and release ownership', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final capability = WalletPaymentCapability.available(
      const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
    );
    await _pumpWidget(
      tester,
      harness,
      PaymentTargetSelectionView(
        capabilities: [capability],
        onSelected: (_) => throw const _SecretNavigationError(),
      ),
    );
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    final tile = find.byType(PaymentTargetTile);
    await tester.tap(tile);
    await tester.pump();

    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<AppFailureException>());
    expect(reported.single.exception.toString(), isNot(contains('secret')));
    expect(harness.toasts.messages, hasLength(1));
    expect(
      harness.toasts.messages.single.title,
      'Payment option could not be opened',
    );
    expect(harness.toasts.messages.single.message, isNot(contains('secret')));
    expect(harness.haptics.intents, [
      HapticIntent.selection,
      HapticIntent.error,
    ]);
    expect(
      tester.getSemantics(tile).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('Send destination Done action validates and advances', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final router = GoRouter(
      initialLocation: '/send/bitcoin-onchain/address',
      routes: [
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (context, state) => const SendAddressScreen(
            target: WalletPaymentTarget.bitcoinOnchain,
          ),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (context, state) => const Text('Amount step'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    final destinationFieldFinder = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.enabled == true,
    );
    await _pumpUntil(
      tester,
      () => destinationFieldFinder.evaluate().isNotEmpty,
    );

    final emptyEditable = find.descendant(
      of: destinationFieldFinder,
      matching: find.byType(EditableText),
    );
    tester
        .state<EditableTextState>(emptyEditable)
        .performAction(TextInputAction.done);
    await _pumpFrames(tester);
    expect(destinationFieldFinder, findsOneWidget);

    const address = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    await tester.enterText(destinationFieldFinder, address);
    await tester.pump();
    final destinationField = tester.widget<TextField>(destinationFieldFinder);
    expect(destinationField.textInputAction, TextInputAction.done);
    expect(destinationField.onSubmitted, isNotNull);
    expect(
      harness.container
          .read(sendFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain))
          .requireValue
          .destination,
      address,
    );
    final editable = find.descendant(
      of: destinationFieldFinder,
      matching: find.byType(EditableText),
    );
    tester
        .state<EditableTextState>(editable)
        .performAction(TextInputAction.done);
    await _pumpFrames(tester);
    await _pumpUntil(
      tester,
      () => find.text('Amount step').evaluate().isNotEmpty,
    );

    expect(find.text('Amount step'), findsOneWidget);
  });

  testWidgets('a rejected recipient can be edited and continued once', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;
    final provider = sendFlowViewModelProvider(target);
    final router = GoRouter(
      initialLocation: '/send/bitcoin-onchain/address',
      routes: [
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (_, _) => const SendAddressScreen(target: target),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (_, _) => const Text('Amount step'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    final field = find.byType(TextField);
    await _pumpUntil(
      tester,
      () =>
          field.evaluate().length == 1 &&
          tester.widget<TextField>(field).enabled == true,
    );
    await tester.enterText(field, 'invalid-payment-recipient');
    await tester.pump();
    final continueButton = find.widgetWithText(CustomButton, 'Continue');
    await tester.tap(continueButton);
    await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
    expect(harness.toasts.messages.single.title, 'Check recipient');
    expect(find.text('Amount step'), findsNothing);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(provider).value?.canChangeDestination ==
              true &&
          tester.widget<TextField>(field).enabled == true,
    );
    const address = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    await tester.enterText(field, address);
    await tester.pump();
    expect(harness.container.read(provider).requireValue.destination, address);
    expect(harness.container.read(provider).requireValue.failure, isNull);
    expect(tester.widget<CustomButton>(continueButton).enabled, isTrue);
    await tester.tap(continueButton);
    await _pumpUntil(
      tester,
      () => find.text('Amount step').evaluate().isNotEmpty,
    );
    expect(find.text('Amount step'), findsOneWidget);
    expect(harness.engine.calls, isNot(contains('sendPayment:start')));
  });

  testWidgets('Send destination serializes validation, Scan, and navigation', (
    tester,
  ) async {
    final decodeGate = Completer<void>();
    final route = testRgbRoute;
    final engine = FakeWalletEngine()
      ..decodeInvoiceGate = decodeGate
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'rgb:navigation',
        displayDestination: 'rgb:navigation',
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: testRgbServices,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    final router = GoRouter(
      initialLocation: '/send/usdt-onchain/address',
      routes: [
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (context, state) =>
              const SendAddressScreen(target: WalletPaymentTarget.usdtOnchain),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (context, state) => const Text('Amount step'),
        ),
        GoRoute(
          path: RoutePaths.scan,
          name: RouteNames.scan,
          builder: (context, state) => const Text('Scanner route'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    final destinationField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.enabled == true,
    );
    await _pumpUntil(tester, () => destinationField.evaluate().isNotEmpty);
    await tester.enterText(destinationField, 'rgb:navigation');
    await tester.pump();

    final continueButton = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Continue'),
    );
    final scanButton = tester.widget<AsterIconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AsterIconButton && widget.tooltip.startsWith('Scan '),
      ),
    );
    continueButton.onTap!();
    scanButton.onPressed!();
    await tester.pump();

    expect(engine.calls.where((call) => call == 'decodeInvoice:start'), [
      'decodeInvoice:start',
    ]);
    expect(find.text('Scanner route'), findsNothing);
    expect(harness.haptics.intents, isEmpty);

    decodeGate.complete();
    await _pumpUntil(
      tester,
      () => find.text('Amount step').evaluate().isNotEmpty,
    );
    expect(find.text('Amount step'), findsOneWidget);
    expect(find.text('Scanner route'), findsNothing);
  });

  testWidgets('Send destination is private and bounded before state updates', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const SendAddressScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    final destinationField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.enabled == true,
    );
    await _pumpUntil(tester, () => destinationField.evaluate().isNotEmpty);

    expect(
      tester.widget<TextField>(destinationField).enableIMEPersonalizedLearning,
      isFalse,
    );
    final oversized = 'a' * (WalletProtocolText.maximumEncodedCharacters + 1);
    await tester.enterText(destinationField, oversized);
    await tester.pump();

    final bounded = tester.widget<TextField>(destinationField).controller!.text;
    expect(bounded, hasLength(WalletProtocolText.maximumEncodedCharacters));
    expect(
      harness.container
          .read(sendFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain))
          .requireValue
          .destination,
      bounded,
    );
  });

  testWidgets('send loading surfaces preserve compact 2x geometry', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SendAddressCard.loading(
                  target: WalletPaymentTarget.bitcoinLightning,
                ),
                const SizedBox(height: 16),
                const SendCard.loading(
                  target: WalletPaymentTarget.bitcoinLightning,
                ),
                const SizedBox(height: 16),
                const AsterNumericKeypad.loading(),
              ],
            ),
          ),
        ),
      ),
      size: const Size(320, 700),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final recipientLoading = find.bySemanticsLabel('Loading recipient form');
    final amountLoading = find.bySemanticsLabel('Loading payment amount');
    expect(recipientLoading, findsOneWidget);
    expect(amountLoading, findsOneWidget);
    expect(
      tester.getSemantics(recipientLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      tester.getSemantics(amountLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(find.bySemanticsLabel('1'), findsNothing);
  });

  testWidgets('initial Send failure belongs to the recipient step', (
    tester,
  ) async {
    const failure = AppFailure(
      code: 'send_load_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Send is temporarily unavailable.',
      retryable: true,
    );
    final engine = FakeWalletEngine()
      ..balanceError = const AppFailureException(failure);
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;

    await _pumpWidget(tester, harness, const SendAddressScreen(target: target));
    await _pumpUntil(
      tester,
      () => find.text(failure.userMessage).evaluate().isNotEmpty,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(failure.userMessage))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Retry'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('direct amount entry returns to recipient without extra prose', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;
    final router = GoRouter(
      initialLocation: '/send/${target.slug}/amount',
      routes: [
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (_, _) => const SendAmountScreen(target: target),
        ),
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (_, _) => const SendAddressScreen(target: target),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    await _pumpUntil(
      tester,
      () => find.text('Recipient address').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SendAmountScreen), findsNothing);
    expect(find.text('Enter recipient'), findsNothing);
    expect(
      find.text('Enter and validate a recipient before choosing an amount.'),
      findsNothing,
    );
    expect(harness.engine.sentPaymentCommand, isNull);
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets('Send returns to Recipient when its retained flow fails', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;
    final provider = sendFlowViewModelProvider(target);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    final router = GoRouter(
      initialLocation: '/send/${target.slug}/amount',
      routes: [
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (_, _) => const SendAddressScreen(target: target),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          name: RouteNames.sendAmount,
          builder: (_, _) => const SendAmountScreen(target: target),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    expect(find.byType(SendAmountScreen), findsOneWidget);

    harness.engine.balanceError = StateError('test wallet unavailable');
    harness.container.invalidate(provider);
    await _pumpUntil(
      tester,
      () =>
          router.state.uri.path == RoutePaths.sendAddressFor(target.slug) &&
          find.byType(SendAmountScreen).evaluate().isEmpty,
    );

    expect(find.byType(SendAmountScreen), findsNothing);
    expect(find.byType(SendAddressScreen), findsOneWidget);
    expect(harness.engine.sentPaymentCommand, isNull);
    expect(tester.takeException(), isNull);
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
    await _enterAmount(tester, keypad, [
      '0',
      '.',
      '0',
      '0',
      '0',
      '0',
      '0',
      '1',
    ]);
    await _pumpUntil(
      tester,
      () => find.text('≈ \$0.07 USD').evaluate().isNotEmpty,
    );

    clockNow = clockNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('USD quote unavailable'), findsNothing);
    expect(find.widgetWithText(AmountText, '—'), findsOneWidget);
  });

  testWidgets('late Send state renders an already-stale fee immediately', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 11, 12);
    final balanceGate = Completer<void>();
    final engine = FakeWalletEngine()
      ..balanceGate = balanceGate
      ..balance = _bitcoinBalance(1000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: clockNow,
      );
    final transport = ResilientHttpClient(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'bitcoin': {
              'usd': 65000,
              'last_updated_at': clockNow.millisecondsSinceEpoch ~/ 1000,
            },
          }),
          200,
        ),
      ),
      retryPolicy: RetryPolicy(maxAttempts: 1),
      clock: () => clockNow,
    );
    addTearDown(transport.close);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      httpClient: transport,
      clock: () => clockNow,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;
    final provider = sendFlowViewModelProvider(target);

    await _pumpWidget(tester, harness, const SendAmountScreen(target: target));
    await _pumpUntil(tester, () => engine.calls.contains('balance'));
    clockNow = clockNow.add(
      WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
    );
    balanceGate.complete();
    await _pumpUntil(tester, () => harness.container.read(provider).hasValue);

    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    notifier.updateAmount('0.00000001');
    await _pumpUntil(
      tester,
      () => find.text('Unavailable').evaluate().isNotEmpty,
    );

    expect(
      find.text(
        'A current network fee is required before sending. Go back and reopen this step if it remains unavailable.',
      ),
      findsNothing,
    );
    expect(harness.toasts.messages, isEmpty);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('2 sats/vbyte'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(tester.widget<CustomButton>(sendButton).enabled, isTrue);
  });

  testWidgets('USDT send never presents zero fiat without a Tether quote', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    const assetConfiguration = RgbAssetConfiguration(
      contractId: 'contract-id',
      precision: 2,
      requiresEvmValidation: false,
    );
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: assetConfiguration,
    );
    final asset = WalletAsset.rgbUsdt(
      assetId: assetConfiguration.contractId,
      precision: assetConfiguration.precision,
    );
    final engine = FakeWalletEngine()
      ..balances[asset.id] = _assetBalance(asset, spendable: 10000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
      );
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response('{"prices":[]}', 200);
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
      clock: () => now,
    );
    addTearDown(transport.close);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: services,
      httpClient: transport,
      clock: () => now,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    final provider = sendFlowViewModelProvider(WalletPaymentTarget.usdtOnchain);
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('rgb-destination');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);

    await _pumpWidget(
      tester,
      harness,
      const SendAmountScreen(target: WalletPaymentTarget.usdtOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    await _pumpUntil(
      tester,
      () => find.widgetWithText(AmountText, '—').evaluate().isNotEmpty,
    );

    expect(find.text('USD quote unavailable'), findsNothing);
    expect(find.widgetWithText(AmountText, '—'), findsOneWidget);
    expect(find.text(r'$0.00 USD'), findsNothing);
    expect(find.text('Retry fiat quote'), findsNothing);
    expect(harness.toasts.messages, isEmpty);
    await _pumpFrames(tester);
  });

  testWidgets('Send review keeps details clean and warns once for expiry', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    var clockNow = DateTime.utc(2026, 8, 16, 12);
    final expiresAt = clockNow.add(const Duration(minutes: 1));
    final route = testRgbRoute;
    final engine = FakeWalletEngine()
      ..balance = testRgbBalance(5000)
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'rgb:review',
        displayDestination: 'rgb:review',
        amount: WalletAmount.onchain(assetId: route.asset.id, units: 2000),
        expiresAt: expiresAt,
        recipientLabel: 'Merchant checkout',
        message: 'Invoice 123',
      );
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('{}', 503)),
      retryPolicy: RetryPolicy(maxAttempts: 1),
      clock: () => clockNow,
    );
    addTearDown(transport.close);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      httpClient: transport,
      clock: () => clockNow,
      services: testRgbServices,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.usdtOnchain;
    final provider = sendFlowViewModelProvider(target);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('rgb:review');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);

    clockNow = expiresAt;
    await _pumpWidget(tester, harness, const SendAmountScreen(target: target));
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );

    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 844);
    expect(
      tester.widget<AsterFormBody>(find.byType(AsterFormBody)).bottomPadding,
      greaterThan(34),
    );
    final card = find.byType(SendCard);
    expect(
      find.descendant(of: card, matching: find.text('Recipient')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('rgb:review')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('RGB on-chain')),
      findsNothing,
    );
    expect(find.text('Send USDT'), findsOneWidget);
    expect(find.text('Recipient'), findsNothing);
    expect(find.bySemanticsLabel('Address, rgb:review'), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('On-chain')),
      findsOneWidget,
    );
    expect(find.text('Max'), findsOneWidget);
    expect(
      tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Max'))
          .enabled,
      isFalse,
    );
    await tester.tap(find.widgetWithText(CustomButton, 'Max'));
    expect(
      harness.container.read(provider).requireValue.amountInput.units,
      2000,
    );
    expect(find.textContaining('Max unavailable'), findsNothing);
    expect(find.text('Refresh balance'), findsNothing);
    expect(find.text('Refresh fee'), findsNothing);
    expect(find.text('Payment label'), findsNothing);
    expect(find.text('Merchant checkout'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Invoice 123'), findsNothing);
    expect(
      find.text('This invoice has expired. Enter a new invoice to continue.'),
      findsNothing,
    );
    await _pumpFrames(tester);
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.variant, ToastVariant.warning);
    expect(harness.toasts.messages.single.title, 'Invoice expired');
    expect(
      harness.toasts.messages.single.message,
      'This invoice has expired. Enter a new invoice to continue.',
    );
    await tester.pump(const Duration(seconds: 5));
    expect(harness.toasts.messages, hasLength(1));
    expect(
      tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
          .enabled,
      isFalse,
    );
    subscription.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
  });

  testWidgets('Receive renders real request, copies it, and applies amount', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
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

    expect(find.text('Receive Bitcoin'), findsOneWidget);
    expect(find.text('Bitcoin · On-chain'), findsNothing);
    final list = find.byType(ListView);
    expect(tester.getRect(list).bottom, 844);
    expect(
      tester.widget<ListView>(list).padding!.resolve(TextDirection.ltr).bottom,
      greaterThan(34),
    );

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
    await tester.tap(find.bySemanticsLabel('Close amount editor'));
    await _pumpUntil(
      tester,
      () => find.byType(ReceiveAmountSheet).evaluate().isEmpty,
    );
    await tester.tap(find.text('Set amount').first);
    await _pumpFrames(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AsterNumericKeypad),
        matching: find.text('1'),
      ),
    );
    await tester.pump();
    final gate = Completer<void>();
    harness.engine.createReceiveGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(
                receiveFlowViewModelProvider(
                  WalletPaymentTarget.bitcoinOnchain,
                ),
              )
              .value
              ?.isGenerating ??
          false,
    );
    await tester.pump();
    final close = find.bySemanticsLabel('Close amount editor');
    final closeSemantics = tester.getSemantics(close).getSemanticsData();
    expect(closeSemantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(closeSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(find.byType(ReceiveAmountSheet), findsOneWidget);

    gate.complete();
    await _pumpUntil(
      tester,
      () => find.byType(ReceiveAmountSheet).evaluate().isEmpty,
    );

    expect(harness.engine.createdReceiveAmount?.units, 100000000);
  });

  testWidgets(
    'Receive regeneration blocks stale Back and system pop in its first frame',
    (tester) async {
      final engine = FakeWalletEngine();
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(() => _disposeHarness(tester, harness));
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final router = GoRouter(
        initialLocation: RoutePaths.receive,
        routes: [
          GoRoute(
            path: RoutePaths.receive,
            builder: (context, state) => const Text('Receive root'),
          ),
          GoRoute(
            path: RoutePaths.receiveRequest,
            builder: (context, state) => const ReceiveRequestScreen(
              target: WalletPaymentTarget.bitcoinOnchain,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pumpRouter(tester, harness, router);
      final routeCompletion = router.push<Object?>(
        '/receive/${WalletPaymentTarget.bitcoinOnchain.slug}',
      );
      await _pumpUntil(
        tester,
        () => find.byType(PrettyQrView).evaluate().isNotEmpty,
      );
      await tester.scrollUntilVisible(
        find.text('Generate new request'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      engine.createReceiveGate = Completer<void>();
      final regenerate = tester
          .widgetList<AsterOptionRow>(find.byType(AsterOptionRow))
          .singleWhere((row) => row.title == 'Generate new request');
      final staleBack = tester.widget<AsterIconButton>(
        find.byWidgetPredicate(
          (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
        ),
      );
      final navigation = AsterNavigationScope.of(
        tester.element(find.bySemanticsLabel('Back')),
      );

      regenerate.onTap!();
      expect(navigation.inFlight, isTrue);
      expect(router.canPop(), isTrue);
      staleBack.onPressed!();
      expect(router.canPop(), isTrue);
      await tester.binding.handlePopRoute();
      expect(router.canPop(), isTrue);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => harness.container.read(provider).value?.isGenerating ?? false,
      );

      expect(find.byType(ReceiveRequestScreen), findsOneWidget);
      expect(router.canPop(), isTrue);
      expect(
        engine.calls.where((call) => call == 'createReceiveRequest:start'),
        hasLength(2),
      );

      engine.createReceiveGate!.complete();
      await _pumpUntil(
        tester,
        () => !(harness.container.read(provider).value?.isGenerating ?? true),
      );
      await _pumpUntil(tester, () => !navigation.inFlight);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await routeCompletion;

      expect(find.text('Receive root'), findsOneWidget);
    },
  );

  testWidgets('RGB onchain Receive applies an exact amount to its request', (
    tester,
  ) async {
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:configured-usdt',
        precision: 6,
        requiresEvmValidation: false,
      ),
    );
    final harness = await PaymentFlowTestHarness.create(services: services);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.usdtOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );

    expect(find.byType(PrettyQrView), findsOneWidget);
    expect(harness.engine.createdReceiveAmount, isNull);

    await tester.tap(find.text('Set amount'));
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    await _pumpFrames(tester);
    expect(find.widgetWithText(CustomButton, 'Clear amount'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AsterNumericKeypad),
        matching: find.text('1'),
      ),
    );
    await tester.pump();
    final createButton = find.widgetWithText(CustomButton, 'Set amount');
    expect(tester.widget<CustomButton>(createButton).enabled, isTrue);

    await tester.tap(createButton);
    await _pumpUntil(
      tester,
      () => find.byType(ReceiveAmountSheet).evaluate().isEmpty,
    );

    expect(harness.engine.createdReceiveAmount?.units, 1000000);
    expect(
      harness.engine.calls.where(
        (call) => call == 'createReceiveRequest:start',
      ),
      hasLength(2),
    );
  });

  testWidgets('Receive QR encoder failure is bounded and announced', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      ReceiveRequestQr(
        encodedRequest:
            'a' * (WalletProtocolText.maximumQrPayloadCharacters + 1),
        semanticLabel: 'Bitcoin payment request QR code',
      ),
    );
    await tester.pump();

    expect(find.text('QR unavailable'), findsOneWidget);
    final failure = find.bySemanticsLabel(
      'Payment request QR code unavailable',
    );
    expect(failure, findsOneWidget);
    expect(tester.getSemantics(failure).flagsCollection.isLiveRegion, isTrue);
    expect(find.bySemanticsLabel(RegExp('a{32}')), findsNothing);
  });

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    testWidgets(
      '${target.name} Receive loading matches request layout without actions',
      (tester) async {
        final isRgb = target == WalletPaymentTarget.usdtOnchain;
        final now = DateTime.utc(2026, 11, 7, 12);
        final address = isRgb
            ? 'rgb:loading-geometry-${'abcd' * 45}'
            : 'request-bitcoin-onchain';
        final route = isRgb
            ? testRgbRoute
            : const PaymentRoute(
                asset: WalletAsset.bitcoin,
                rail: PaymentRail.onchain,
              );
        final gate = Completer<void>();
        final engine = FakeWalletEngine()
          ..createReceiveGate = gate
          ..createdReceiveRequest = WalletReceiveRequest(
            route: route,
            encodedRequest: address,
            displayValue: address,
            expiresAt: isRgb ? now.add(const Duration(hours: 1)) : null,
          );
        final harness = await PaymentFlowTestHarness.create(
          engine: engine,
          services: testRgbServices,
          clock: () => now,
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          return _disposeHarness(tester, harness);
        });
        await _pumpWidget(
          tester,
          harness,
          ReceiveRequestScreen(target: target),
        );
        await _pumpUntil(
          tester,
          () => engine.calls.contains('createReceiveRequest:start'),
        );

        expect(
          find.bySemanticsLabel('Loading payment request'),
          findsOneWidget,
        );
        expect(find.byType(PrettyQrView), findsNothing);
        expect(find.text(address), findsNothing);
        expect(find.textContaining('Expires '), findsNothing);
        expect(
          find.bySemanticsLabel(
            RegExp(r'^(Copy|Set amount|Generate new request|Share)$'),
          ),
          findsNothing,
        );

        final skeleton = find.byType(AppSkeletonizer);
        expect(skeleton, findsOneWidget);
        expect(
          find.descendant(of: skeleton, matching: find.byType(Squircle)),
          findsNWidgets(2),
        );
        final placeholder = find.descendant(
          of: skeleton,
          matching: find.byType(AspectRatio),
        );
        expect(tester.getSize(placeholder), const Size(270, 270));

        tester.view.physicalSize = const Size(466, 678);
        const coverPadding = FakeViewPadding(right: 84, bottom: 34);
        tester.view.padding = coverPadding;
        tester.view.viewPadding = coverPadding;
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pump();
        final coverPlaceholder = tester.getRect(placeholder);
        expect(coverPlaceholder.size, const Size(262, 262));

        final addressPlaceholder = find.byKey(
          const ValueKey('receive-loading-address'),
        );
        final expiryPlaceholder = find.byKey(
          const ValueKey('receive-loading-expiry'),
        );
        expect(addressPlaceholder, findsOneWidget);
        expect(expiryPlaceholder, isRgb ? findsOneWidget : findsNothing);
        final addressHeight = tester.getSize(addressPlaceholder).height;
        expect(addressHeight, isRgb ? greaterThan(24) : lessThan(24));
        final loadingTextHeight =
            addressHeight +
            (isRgb ? tester.getSize(expiryPlaceholder).height : 0);
        final copy = find.widgetWithText(CustomButton, 'Copy');
        expect(tester.widget<CustomButton>(copy).onTap, isNull);
        final loadingCopy = tester.getRect(copy);
        const labels = ['Set amount', 'Generate new request', 'Share'];
        Finder action(String label) =>
            find.widgetWithText(AsterOptionRow, label);
        final loadingActions = [
          for (final label in labels) tester.getRect(action(label)),
        ];
        for (final label in labels) {
          expect(tester.widget<AsterOptionRow>(action(label)).onTap, isNull);
        }

        gate.complete();
        final readyQr = find.byType(PrettyQrView);
        await _pumpUntil(tester, () => readyQr.evaluate().isNotEmpty);
        expect(tester.getRect(readyQr), coverPlaceholder);
        expect(skeleton, findsNothing);
        final readyCopy = tester.getRect(copy);
        expect(readyCopy.size, loadingCopy.size);
        expect(readyCopy.left, closeTo(loadingCopy.left, 0.5));
        final readyAddress = isRgb
            ? find.byType(ReceiveRequestAddress)
            : find.text(address);
        final readyExpiry = find.byWidgetPredicate(
          (widget) =>
              widget is NumericText && widget.text.startsWith('Expires '),
        );
        expect(readyExpiry, isRgb ? findsOneWidget : findsNothing);
        // The native result can wrap differently from a generic text bone.
        // That is the only vertical shift the controls should inherit.
        final readyTextHeight =
            tester.getSize(readyAddress).height +
            (isRgb ? tester.getSize(readyExpiry).height : 0);
        expect(
          readyCopy.top - loadingCopy.top,
          closeTo(readyTextHeight - loadingTextHeight, 1),
        );
        for (var index = 0; index < labels.length; index++) {
          final readyRow = tester.getRect(action(labels[index]));
          final loadingRow = loadingActions[index];
          expect(readyRow.size, loadingRow.size);
          expect(readyRow.left, closeTo(loadingRow.left, 0.5));
          expect(
            readyRow.top - readyCopy.bottom,
            closeTo(loadingRow.top - loadingCopy.bottom, 0.5),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Receive expiry timer reschedules until the UTC boundary', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 16, 12);
    final expiresAt = clockNow.add(const Duration(milliseconds: 10));
    final route = testRgbRoute;
    final engine = FakeWalletEngine()
      ..createdReceiveRequest = WalletReceiveRequest(
        route: route,
        encodedRequest: 'rgb:expiring',
        displayValue: 'rgb:expiring',
        expiresAt: expiresAt,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => clockNow,
      services: testRgbServices,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.usdtOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Expired'), findsNothing);
    expect(find.text('Receive USDT'), findsOneWidget);
    expect(find.text('USDT · RGB on-chain'), findsNothing);
    expect(find.textContaining('Expires '), findsOneWidget);

    clockNow = expiresAt;
    await tester.pump(const Duration(milliseconds: 12));

    expect(find.text('Expired'), findsOneWidget);
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.textContaining('Expires '), findsNothing);
    expect(find.text('rgb:expiring'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Expired'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Copy'))
          .enabled,
      isFalse,
    );
  });

  testWidgets('UXA-011 foreground resume removes an expired payment QR', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 9);
    final expiry = now.add(const Duration(hours: 1));
    final engine = FakeWalletEngine()
      ..createdReceiveRequest = WalletReceiveRequest(
        route: testRgbRoute,
        encodedRequest: 'rgb:testexpiry',
        displayValue: 'rgb:testexpiry',
        expiresAt: expiry,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
      services: testRgbServices,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.usdtOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = expiry;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Generate new request'), findsOneWidget);
  });

  testWidgets('initial Receive failure belongs to the request card', (
    tester,
  ) async {
    const failure = AppFailure(
      code: 'receive_load_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Receive is temporarily unavailable.',
      retryable: true,
    );
    final engine = FakeWalletEngine()
      ..createReceiveError = const AppFailureException(failure);
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;

    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: target),
    );
    await _pumpUntil(
      tester,
      () => find.text('Request unavailable').evaluate().isNotEmpty,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Request unavailable'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Retry'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('Receive amount editor supports compact 2x text', (tester) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const Align(
        alignment: Alignment.bottomCenter,
        child: ReceiveAmountSheet(target: WalletPaymentTarget.bitcoinOnchain),
      ),
      size: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );

    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets(
    'Receive unknown generation outcome disables mutation but preserves old QR actions',
    (tester) async {
      final engine = FakeWalletEngine();
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(() => _disposeHarness(tester, harness));
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      await _pumpWidget(
        tester,
        harness,
        const ReceiveRequestScreen(target: WalletPaymentTarget.bitcoinOnchain),
      );
      await _pumpUntil(
        tester,
        () => find.byType(PrettyQrView).evaluate().isNotEmpty,
      );
      engine.createReceiveError = const AppFailureException(
        AppFailure(
          code: 'wallet_operation_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Check wallet status before generating another request.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );
      final regeneration = harness.container
          .read(provider.notifier)
          .regenerate();
      // Keep the action in the widget zone and flush the complete repository
      // queue, including durable-intent gates, before awaiting its result.
      await tester.pump();
      expect(await regeneration, isFalse);

      final copy = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Copy'),
      );
      expect(copy.enabled, isTrue);
      await tester.scrollUntilVisible(
        find.text('Generate new request'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final rows = tester.widgetList<AsterOptionRow>(
        find.byType(AsterOptionRow),
      );
      AsterOptionRow row(String title) =>
          rows.singleWhere((candidate) => candidate.title == title);

      expect(row('Set amount').onTap, isNull);
      expect(row('Generate new request').onTap, isNull);
      expect(row('Share').onTap, isNotNull);
      expect(
        find.text('Check wallet status before generating another request.'),
        findsNothing,
      );
      expect(
        engine.calls.where((call) => call == 'createReceiveRequest:start'),
        hasLength(2),
      );
    },
  );

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
          path: RoutePaths.home,
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
    await _enterAmount(tester, keypad, [
      '0',
      '.',
      '0',
      '0',
      '0',
      '0',
      '0',
      '1',
    ]);
    final initialSend = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Send'),
    );
    final staleBack = tester.widget<AsterIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
      ),
    );
    initialSend.onTap!();
    staleBack.onPressed!();
    await tester.binding.handlePopRoute();
    await tester.pump();
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
    final back = find.bySemanticsLabel('Back');
    final backSemantics = tester.getSemantics(back).getSemanticsData();
    expect(backSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(backSemantics.hasAction(ui.SemanticsAction.tap), isFalse);
    await tester.tap(back);
    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);
    expect(sendButton, findsOneWidget);
    expect(find.text('Wallet home'), findsNothing);
    await tester.ensureVisible(sendButton);
    // Loading deliberately removes the button from hit testing. Dispatch a
    // pointer at its visible bounds to prove it cannot admit a second send.
    await tester.tapAt(tester.getCenter(sendButton));
    await _pumpFrames(tester);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );

    engine.sendPaymentGate!.complete();
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(
      tester,
      () => find.text('Payment sent').evaluate().isNotEmpty,
    );

    expect(find.text('Wallet home'), findsNothing);
    expect(find.byType(AsterNumericKeypad), findsNothing);
    expect(find.byType(SendCard), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.widgetWithText(AmountText, '0.000001 BTC'), findsOneWidget);
    expect(harness.toasts.messages, isEmpty);
    expect(engine.sentPaymentCommand?.amount.units, 100);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);
    expect(find.text('Payment sent'), findsOneWidget);
    final continueAction = tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!;
    continueAction();
    continueAction();
    await _pumpUntil(
      tester,
      () => find.text('Wallet home').evaluate().isNotEmpty,
    );
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets('unknown payment outcome disables every Send route control', (
    tester,
  ) async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('{}', 503)),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.now().toUtc(),
      )
      ..sendPaymentError = const AppFailureException(
        AppFailure(
          code: 'wallet_operation_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage:
              'The wallet did not confirm the operation in time. Check its '
              'status before trying again.',
          retryable: false,
          outcomeUnknown: true,
        ),
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
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    notifier.updateAmount('0.000001');

    await _pumpWidget(
      tester,
      harness,
      const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.widgetWithText(CustomButton, 'Send'));
    await tester.tap(find.widgetWithText(CustomButton, 'Send'));
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(provider).value?.requiresReconciliation ==
          true,
    );
    await _pumpFrames(tester);

    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(tester.widget<CustomButton>(sendButton).enabled, isFalse);
    expect(
      tester
          .widget<AsterNumericKeypad>(find.byType(AsterNumericKeypad))
          .enabled,
      isFalse,
    );
    final refreshBalance = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Refresh balance',
    );
    expect(refreshBalance, findsNothing);
    final retryQuote = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Retry fiat quote',
    );
    expect(retryQuote, findsNothing);
    expect(
      find.text(walletPaymentSubmissionPendingFailure.userMessage),
      findsNothing,
    );
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.title, 'Status unavailable');
    expect(harness.toasts.messages.single.variant, ToastVariant.warning);
    expect(
      harness.toasts.messages.single.message,
      'Check this send in Activity before trying again.',
    );

    await _pumpWidget(
      tester,
      harness,
      const SendAddressScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final continueButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Continue',
    );
    expect(tester.widget<CustomButton>(continueButton).enabled, isFalse);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  testWidgets(
    'a failed Send is announced only by its action, never on remount',
    (tester) async {
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance(1000)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        )
        ..sendPaymentError = const WalletPaymentRejectedBeforeDispatchException(
          AppFailure(
            code: 'payment_temporarily_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'The operation took too long. Try again.',
            retryable: true,
          ),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(() => _disposeHarness(tester, harness));
      const target = WalletPaymentTarget.bitcoinOnchain;
      final provider = sendFlowViewModelProvider(target);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await tester.runAsync(() => harness.container.read(provider.future));
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await tester.runAsync(notifier.validateDestination), isTrue);
      notifier.updateAmount('0.000001');
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: target),
      );
      await _pumpFrames(tester);
      expect(harness.toasts.messages, isEmpty);
      await tester.ensureVisible(find.widgetWithText(CustomButton, 'Send'));
      await tester.tap(find.widgetWithText(CustomButton, 'Send'));
      await _pumpUntil(
        tester,
        () => harness.container.read(provider).value?.failure != null,
      );
      await _pumpFrames(tester);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Unable to send');
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: target),
      );
      await _pumpFrames(tester);
      await tester.pump(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpFrames(tester);
      expect(harness.toasts.messages, hasLength(1));
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(harness.container.read(provider).requireValue.failure, isNotNull);
    },
  );

  testWidgets('terminal fee failure exposes no unsafe direct retry', (
    tester,
  ) async {
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.now().toUtc(),
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    notifier.updateAmount('0.000001');
    engine.feeEstimateError = StateError('terminal fee state');
    expect(await tester.runAsync(notifier.refreshFee), isFalse);
    final failureMessage = harness.container
        .read(provider)
        .requireValue
        .feeFailure!
        .userMessage;

    await _pumpWidget(
      tester,
      harness,
      const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    await _pumpFrames(tester);

    expect(find.text(failureMessage), findsNothing);
    expect(harness.toasts.messages, isEmpty);
    expect(find.text('Refresh fee'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(tester.widget<CustomButton>(sendButton).enabled, isFalse);
  });

  testWidgets('a deferred fee warning is discarded after leaving Send', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 16);
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
      );
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('{}', 503)),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
      httpClient: transport,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinOnchain;
    final provider = sendFlowViewModelProvider(target);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    notifier.updateAmount('0.000001');
    final router = GoRouter(
      initialLocation: RoutePaths.home,
      routes: [
        GoRoute(
          path: RoutePaths.home,
          builder: (_, _) => const Scaffold(body: Text('Wallet home')),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          builder: (_, _) => const SendAmountScreen(target: target),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, harness, router);
    unawaited(router.push<void>('/send/${target.slug}/amount'));
    await tester.pumpAndSettle();
    expect(harness.toasts.messages, isEmpty);

    // A retained read failure schedules presentation for the next frame.
    // Pop first: no feedback from this route may leak onto Home.
    engine.feeEstimateError = StateError('terminal fee state');
    expect(await tester.runAsync(notifier.refreshFee), isFalse);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Wallet home'), findsOneWidget);
    expect(harness.toasts.messages, isEmpty);
    expect(engine.calls, isNot(contains('sendPayment:start')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a retained balance failure never retries or toasts automatically',
    (tester) async {
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance(1000)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        );
      final transport = ResilientHttpClient(
        client: MockClient((request) async => http.Response('{}', 503)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        httpClient: transport,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      await _pumpWidget(
        tester,
        harness,
        const SendAmountScreen(target: WalletPaymentTarget.bitcoinOnchain),
      );
      await _pumpUntil(
        tester,
        () =>
            harness.container.read(provider).hasValue &&
            harness.container.read(walletViewModelProvider).hasValue,
      );
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      final validation = notifier.validateDestination();
      await _pumpFrames(tester);
      expect(await validation, isTrue);
      notifier.updateAmount('0.000001');
      engine.balanceError = TimeoutException('temporary balance timeout');
      final refresh = notifier.refreshBalance();
      await _pumpFrames(tester);
      expect(await refresh, isFalse);
      final failureMessage = harness.container
          .read(provider)
          .requireValue
          .failure!
          .userMessage;

      expect(find.text(failureMessage), findsNothing);
      expect(harness.toasts.messages, isEmpty);
      expect(find.text('Refresh balance'), findsNothing);
      expect(find.text('Refresh fee'), findsNothing);
      engine.balanceError = null;
      final balanceReads = engine.calls
          .where((call) => call == 'balance')
          .length;
      await tester.pump(const Duration(minutes: 1));
      await _pumpFrames(tester);
      expect(
        harness.container.read(provider).requireValue.failure!.userMessage,
        failureMessage,
      );
      expect(
        engine.calls.where((call) => call == 'balance'),
        hasLength(balanceReads),
      );
      expect(harness.toasts.messages, isEmpty);
      expect(
        tester
            .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
            .enabled,
        isFalse,
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
    },
  );
}

final class _SendSetupStore implements RgbWalletSetupStore {
  final documents = <String, String>{};
  @override
  Future<String?> read(String walletId) async => documents[walletId];
  @override
  Future<void> write(String walletId, String document) async {
    documents[walletId] = document;
  }
}

final class _SendSetupEngine extends FakeWalletEngine
    implements RgbSetupWalletEngine {
  int setupDispatches = 0;
  @override
  Future<RgbWalletSetupInventory> rgbSetupInventory() async =>
      RgbWalletSetupInventory(
        freeAllocationCount: 0,
        vanillaSpendableSats: 2000000,
        runtimeFingerprint: 'a' * 64,
        nodePublicKey: 'b' * 64,
        identityKind: RgbSetupIdentityKind.nativeWallet,
      );
  @override
  Future<List<RgbWalletSetupTransaction>> rgbSetupTransactions() async =>
      setupDispatches == 0
      ? []
      : [RgbWalletSetupTransaction(txid: 'c' * 64, confirmed: false)];
  @override
  Future<void> createRgbSetupOutputs(int rate) async {
    setupDispatches++;
  }
}

final class _SecretNavigationError implements Exception {
  const _SecretNavigationError();

  @override
  String toString() => 'secret-payment-destination';
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
  Size size = const Size(390, 844),
  TextScaler? textScaler,
}) {
  _configurePhone(tester, size: size);
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

void _configurePhone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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

Future<void> _enterAmount(
  WidgetTester tester,
  Finder keypad,
  List<String> keys,
) async {
  for (final key in keys) {
    final keyFinder = find.descendant(of: keypad, matching: find.text(key));
    await tester.ensureVisible(keyFinder);
    await tester.pump();
    await tester.tap(keyFinder);
    await tester.pump();
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

WalletBalance _assetBalance(WalletAsset asset, {required int spendable}) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: asset.id, units: units);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(spendable),
    onchainFuture: onchain(spendable),
    onchainSpendable: onchain(spendable),
    onchainLocked: onchain(0),
    lightningOwned: lightning(0),
    lightningSpendable: lightning(0),
    lightningReceivable: lightning(0),
  );
}
