import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
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

  testWidgets('payment target selection owns one route command at a time', (
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
        capabilities: AsyncData([capability]),
        onSelected: (target) async {
          selectionCount += 1;
          await navigationGate.future;
        },
        onRetry: () {},
      ),
    );

    final tile = find.byType(PaymentTargetTile);
    await tester.tap(tile);
    await tester.tap(tile);
    await tester.pump();

    expect(selectionCount, 1);
    expect(harness.haptics.intents, [HapticIntent.selection]);
    expect(
      tester.getSemantics(tile).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
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
        capabilities: AsyncData([capability]),
        onSelected: (_) => throw const _SecretNavigationError(),
        onRetry: () {},
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

  testWidgets('payment target loading exposes one truthful live node', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      PaymentTargetSelectionView(
        capabilities: const AsyncLoading(),
        onSelected: (_) async {},
        onRetry: () {},
      ),
    );

    expect(find.bySemanticsLabel('Loading payment options'), findsOneWidget);
    expect(find.bySemanticsLabel('Bitcoin on-chain payment'), findsNothing);
    expect(find.bySemanticsLabel('Bitcoin Lightning payment'), findsNothing);
  });

  testWidgets('payment target failure is announced without hiding retry', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    const failure = AppFailure(
      code: 'payment_options_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Payment options are temporarily unavailable.',
      retryable: true,
    );
    await _pumpWidget(
      tester,
      harness,
      PaymentTargetSelectionView(
        capabilities: AsyncError(
          AppFailureException(failure),
          StackTrace.empty,
        ),
        onSelected: (_) async {},
        onRetry: () {},
      ),
    );

    final message = find.bySemanticsLabel(failure.userMessage);
    expect(message, findsOneWidget);
    expect(tester.getSemantics(message).flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Retry'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
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

  testWidgets('Send destination serializes validation, Scan, and navigation', (
    tester,
  ) async {
    final decodeGate = Completer<void>();
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final engine = FakeWalletEngine()
      ..decodeInvoiceGate = decodeGate
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'lnbcrt1navigation',
        displayDestination: 'lnbcrt1navigation',
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));
    final router = GoRouter(
      initialLocation: '/send/bitcoin-lightning/address',
      routes: [
        GoRoute(
          path: RoutePaths.sendAddress,
          name: RouteNames.sendAddress,
          builder: (context, state) => const SendAddressScreen(
            target: WalletPaymentTarget.bitcoinLightning,
          ),
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
    await tester.enterText(destinationField, 'lnbcrt1navigation');
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

  testWidgets('initial Send failures are live on both flow steps', (
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

    await _pumpWidget(tester, harness, const SendAmountScreen(target: target));
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
    await _pumpUntil(
      tester,
      () => find.text('≈ \$0.07 USD').evaluate().isNotEmpty,
    );

    clockNow = clockNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('USD quote unavailable'), findsOneWidget);
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
    await _pumpUntil(
      tester,
      () => find.text('Enter recipient').evaluate().isNotEmpty,
    );

    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);
    notifier.updateAmount('0.00000001');
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );

    expect(
      find.text('Refresh the network fee before sending.'),
      findsOneWidget,
    );
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(tester.widget<CustomButton>(sendButton).enabled, isFalse);
  });

  testWidgets('USDT send never presents zero fiat without a Tether quote', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11, 12);
    const assetConfiguration = RgbAssetConfiguration(
      contractId: 'contract-id',
      precision: 2,
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
      () => find.text('USD quote unavailable').evaluate().isNotEmpty,
    );

    expect(find.text('USD quote unavailable'), findsOneWidget);
    expect(find.text(r'$0.00 USD'), findsNothing);
    expect(find.text('Retry fiat quote'), findsOneWidget);
  });

  testWidgets('Send review explains expiry and preserves payment metadata', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 16, 12);
    final expiresAt = clockNow.add(const Duration(minutes: 1));
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance(1000)
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'lnbcrt1review',
        displayDestination: 'lnbcrt1review',
        amount: WalletAmount.lightning(
          assetId: WalletAsset.bitcoin.id,
          units: 2000,
        ),
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
    );
    addTearDown(() => _disposeHarness(tester, harness));
    const target = WalletPaymentTarget.bitcoinLightning;
    final provider = sendFlowViewModelProvider(target);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await tester.runAsync(() => harness.container.read(provider.future));
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('lnbcrt1review');
    expect(await tester.runAsync(notifier.validateDestination), isTrue);

    clockNow = expiresAt;
    await _pumpWidget(tester, harness, const SendAmountScreen(target: target));
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );

    expect(find.text('Payment label'), findsOneWidget);
    expect(find.text('Merchant checkout'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Invoice 123'), findsOneWidget);
    expect(find.text('This payment request has expired.'), findsOneWidget);
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
    harness.engine.createReceiveGate = Completer<void>();
    final apply = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Set amount'),
    );
    final staleClose = tester.widget<AsterIconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AsterIconButton &&
            widget.tooltip == 'Close amount editor',
      ),
    );
    apply.onTap!();
    staleClose.onPressed!();
    await tester.binding.handlePopRoute();
    await tester.pump();
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
    expect(closeSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(closeSemantics.hasAction(ui.SemanticsAction.tap), isFalse);
    await tester.tapAt(const Offset(8, 8));
    await tester.binding.handlePopRoute();
    await tester.drag(find.byType(ReceiveAmountSheet), const Offset(0, 400));
    await _pumpFrames(tester);
    expect(find.byType(ReceiveAmountSheet), findsOneWidget);

    harness.engine.createReceiveGate!.complete();
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

  testWidgets('RGB Lightning Receive creates its first request from amount', (
    tester,
  ) async {
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:configured-usdt',
        precision: 6,
      ),
    );
    final harness = await PaymentFlowTestHarness.create(services: services);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.usdtLightning),
    );
    await _pumpUntil(
      tester,
      () => find.text('Amount required').evaluate().isNotEmpty,
    );

    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.widgetWithText(CustomButton, 'Copy'), findsNothing);
    expect(find.text('Generate new request'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(harness.engine.calls, isNot(contains('createReceiveRequest:start')));

    await tester.tap(find.text('Set amount'));
    await _pumpUntil(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().isNotEmpty,
    );
    await _pumpFrames(tester);
    final createButton = find.widgetWithText(CustomButton, 'Create request');
    expect(tester.widget<CustomButton>(createButton).enabled, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byType(AsterNumericKeypad),
        matching: find.text('1'),
      ),
    );
    await tester.pump();
    expect(tester.widget<CustomButton>(createButton).enabled, isTrue);

    await tester.tap(createButton);
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );

    expect(harness.engine.createdReceiveAmount?.units, 1000000);
    expect(
      harness.engine.calls.where(
        (call) => call == 'createReceiveRequest:start',
      ),
      hasLength(1),
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

  testWidgets('Receive request loading exposes no fabricated request', (
    tester,
  ) async {
    final engine = FakeWalletEngine()..createReceiveGate = Completer<void>();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.bitcoinOnchain),
    );
    await _pumpUntil(
      tester,
      () => engine.calls.contains('createReceiveRequest:start'),
    );

    expect(find.bySemanticsLabel('Loading payment request'), findsOneWidget);
    expect(find.byType(PrettyQrView), findsNothing);

    engine.createReceiveGate!.complete();
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );
  });

  testWidgets('Receive expiry timer reschedules until the UTC boundary', (
    tester,
  ) async {
    var clockNow = DateTime.utc(2026, 8, 16, 12);
    final expiresAt = clockNow.add(const Duration(milliseconds: 10));
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final engine = FakeWalletEngine()
      ..createdReceiveRequest = WalletReceiveRequest(
        route: route,
        encodedRequest: 'lnbcrt1expiring',
        displayValue: 'lnbcrt1expiring',
        expiresAt: expiresAt,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => clockNow,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpWidget(
      tester,
      harness,
      const ReceiveRequestScreen(target: WalletPaymentTarget.bitcoinLightning),
    );
    await _pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
    );

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('This payment request has expired.'), findsNothing);

    clockNow = expiresAt;
    await tester.pump(const Duration(milliseconds: 12));

    expect(find.text('This payment request has expired.'), findsOneWidget);
    expect(
      tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Copy'))
          .enabled,
      isFalse,
    );
  });

  testWidgets('initial Receive failure is live on request and amount views', (
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
      () => find.text(failure.userMessage).evaluate().isNotEmpty,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(failure.userMessage))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await _pumpWidget(
      tester,
      harness,
      const ReceiveAmountSheet(target: target),
    );
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
      expect(
        await tester.runAsync(
          harness.container.read(provider.notifier).regenerate,
        ),
        isFalse,
      );
      await tester.pump();

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
        findsOneWidget,
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
    for (final digit in ['0', '.', '0', '0', '0', '0', '0', '1']) {
      await tester.tap(find.descendant(of: keypad, matching: find.text(digit)));
      await tester.pump();
    }
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
    expect(await tester.runAsync(notifier.submit), isFalse);
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
    expect(tester.widget<CustomButton>(refreshBalance).enabled, isFalse);
    final retryQuote = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Retry fiat quote',
    );
    expect(retryQuote, findsOneWidget);
    expect(tester.widget<CustomButton>(retryQuote).enabled, isFalse);
    expect(
      find.text(
        'The wallet did not confirm the operation in time. Check its status '
        'before trying again.',
      ),
      findsOneWidget,
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

    expect(find.text(failureMessage), findsOneWidget);
    expect(find.text('Refresh fee'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Send',
    );
    expect(tester.widget<CustomButton>(sendButton).enabled, isFalse);
  });

  testWidgets('balance failure renders beside its own retry control', (
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
    engine.balanceError = TimeoutException('temporary balance timeout');
    expect(await tester.runAsync(notifier.refreshBalance), isFalse);
    final failureMessage = harness.container
        .read(provider)
        .requireValue
        .failure!
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

    expect(
      tester.widget<SendCard>(find.byType(SendCard)).validationMessage,
      isNull,
    );
    expect(find.text(failureMessage), findsOneWidget);
    final refreshBalance = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Refresh balance',
    );
    expect(tester.widget<CustomButton>(refreshBalance).enabled, isTrue);
  });
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
