import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

const _bitcoinRoute = PaymentRoute(
  asset: WalletAsset.bitcoin,
  rail: PaymentRail.onchain,
);
const _bitcoinDestination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
final _now = DateTime.utc(2026, 10, 16, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (target, input, exact, iconAsset) in [
    (
      WalletPaymentTarget.bitcoinOnchain,
      '0.000001',
      '0.000001 BTC',
      'assets/icons/tokens/btc.svg',
    ),
    (
      WalletPaymentTarget.usdtOnchain,
      '1.000001',
      '1.000001 USDT',
      'assets/icons/tokens/usdt.svg',
    ),
  ]) {
    for (final nativeDelay in [Duration.zero, const Duration(seconds: 3)]) {
      testWidgets(
        '${target.name} accepted after ${nativeDelay.inSeconds}s stays on exact success until Continue',
        (tester) async {
          final engine = _engine()..sendPaymentGate = Completer<void>();
          final harness = await _harness(tester, engine);
          final provider = sendFlowViewModelProvider(target);
          final subscription = harness.container.listen(provider, (_, _) {});
          addTearDown(subscription.close);
          await tester.runAsync(() => harness.container.read(provider.future));
          final notifier = harness.container.read(provider.notifier);
          notifier.updateDestination(
            target == WalletPaymentTarget.bitcoinOnchain
                ? _bitcoinDestination
                : 'rgb:synthetic-success-fixture',
          );
          expect(await tester.runAsync(notifier.validateDestination), isTrue);
          notifier.updateAmount(input);
          expect(
            harness.container.read(provider).requireValue.canSubmitAt(_now),
            isTrue,
          );
          final observer = _HomeObserver();
          final router = _router(target, observer: observer);
          addTearDown(router.dispose);
          await _pumpRouter(tester, harness, router);
          unawaited(router.push<void>('/send/${target.slug}/amount'));
          await tester.pumpAndSettle();
          final send = tester
              .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
              .onTap!;
          expect(
            harness.container.read(provider).requireValue.canSubmitAt(_now),
            isTrue,
          );
          final loadingStartedAt = tester.binding.clock.now();
          send();
          send();
          await _pumpUntil(
            tester,
            () =>
                engine.calls.contains('sendPayment:start') ||
                harness.container.read(provider).value?.failure != null ||
                harness.container.read(provider).value?.feeFailure != null,
            diagnostic: () =>
                '${engine.calls}; '
                '${harness.container.read(provider).value?.operation}; '
                '${harness.container.read(provider).value?.failure?.code}; '
                '${harness.container.read(provider).value?.feeFailure?.code}',
          );
          expect(
            engine.calls,
            contains('sendPayment:start'),
            reason: harness.container.read(provider).value?.failure?.code,
          );
          expect(find.byType(SendSuccessView), findsNothing);
          expect(find.text('Payment sent'), findsNothing);
          expect(find.widgetWithText(CustomButton, 'Continue'), findsNothing);

          final loadingButton = tester.widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Send'),
          );
          expect(loadingButton.loading, isTrue);
          expect(loadingButton.enabled, isFalse);
          if (nativeDelay > Duration.zero) await tester.pump(nativeDelay);
          final nativeCompletedAt = tester.binding.clock.now();
          engine.sendPaymentGate!.complete();
          await _pumpUntil(
            tester,
            () => harness.container.read(provider).value?.result != null,
          );
          if (nativeDelay == Duration.zero) {
            // The receipt is real and durable, but its presentation must wait.
            expect(find.byType(SendSuccessView), findsNothing);
            expect(
              tester
                  .widget<CustomButton>(
                    find.widgetWithText(CustomButton, 'Send'),
                  )
                  .loading,
              isTrue,
            );
            send();
            await tester.binding.handlePopRoute();
            await tester.pump();
            expect(find.text('Wallet home'), findsNothing);
            final remaining = loadingStartedAt
                .add(const Duration(seconds: 2))
                .difference(tester.binding.clock.now());
            expect(remaining, greaterThan(const Duration(milliseconds: 1)));
            await tester.pump(remaining - const Duration(milliseconds: 1));
            expect(find.byType(SendSuccessView), findsNothing);
            await tester.pump(const Duration(milliseconds: 1));
          }
          await _pumpUntil(
            tester,
            () => find.byType(SendSuccessView).evaluate().isNotEmpty,
          );
          if (nativeDelay > Duration.zero) {
            // A slow native call has already satisfied the two-second minimum.
            expect(
              tester.binding.clock.now().difference(nativeCompletedAt),
              lessThan(const Duration(seconds: 1)),
            );
          }
          await tester.pumpAndSettle();
          final receipt = harness.container.read(provider).requireValue.result!;
          expect(
            receipt.amount.units,
            target == WalletPaymentTarget.bitcoinOnchain ? 100 : 1000001,
          );
          expect(find.widgetWithText(AmountText, exact), findsOneWidget);
          expect(find.text('Payment sent'), findsOneWidget);
          expect(find.byType(CustomAppBar), findsNothing);
          expect(find.byType(AsterNumericKeypad), findsNothing);
          expect(find.byType(SendCard), findsNothing);
          expect(find.text('Wallet home'), findsNothing);
          expect(
            tester.widget<WalletAssetIcon>(find.byType(WalletAssetIcon)).kind,
            receipt.route.asset.kind,
          );
          final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
          expect((svg.bytesLoader as SvgAssetLoader).assetName, iconAsset);
          expect(harness.toasts.messages, isEmpty);
          expect(
            engine.calls.where((call) => call == 'sendPayment:start'),
            hasLength(1),
          );

          // A terminal receipt cannot be edited or resent. An ordinary rebuild,
          // elapsed time and system Back must not consume the user's Continue.
          notifier.updateAmount('999');
          expect(await notifier.submit(), isFalse);
          final walletReload = harness.container
              .read(walletViewModelProvider.notifier)
              .reload();
          harness.container.invalidate(bitcoinMarketViewModelProvider);
          await _pumpUntil(
            tester,
            () => !harness.container.read(walletViewModelProvider).isLoading,
          );
          await walletReload;
          await _pumpRouter(tester, harness, router);
          await tester.pump(const Duration(minutes: 5));
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(harness.container.read(provider).requireValue.result, receipt);
          expect(find.widgetWithText(AmountText, exact), findsOneWidget);
          expect(find.text('Payment sent'), findsOneWidget);
          expect(router.canPop(), isTrue);
          expect(harness.toasts.messages, isEmpty);
          final homeEntries = observer.homeEntries;
          final continueAction = tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, 'Continue'),
              )
              .onTap!;
          continueAction();
          continueAction();
          await tester.pumpAndSettle();
          expect(find.text('Wallet home'), findsOneWidget);
          expect(find.byType(SendSuccessView), findsNothing);
          expect(observer.homeEntries, homeEntries + 1);
          expect(router.canPop(), isFalse);
          expect(
            engine.calls.where((call) => call == 'sendPayment:start'),
            hasLength(1),
          );
          expect(harness.toasts.messages, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (name, error, nativeStatus, mismatchedAmount) in [
    (
      'confirmed rejection',
      const WalletPaymentRejectedBeforeDispatchException(
        AppFailure(
          code: 'wallet_validation',
          kind: AppFailureKind.validation,
          userMessage: 'Check the entered information and try again.',
          retryable: false,
        ),
      ),
      null,
      false,
    ),
    ('timeout', TimeoutException('synthetic timeout'), null, false),
    (
      'unknown outcome',
      const AppFailureException(
        AppFailure(
          code: 'wallet_operation_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Check payment status before trying again.',
          retryable: false,
          outcomeUnknown: true,
        ),
      ),
      null,
      false,
    ),
    ('failed native receipt', null, WalletPaymentStatus.failed, false),
    ('mismatched native amount', null, WalletPaymentStatus.pending, true),
  ]) {
    testWidgets('$name never presents a success or retries the payment', (
      tester,
    ) async {
      final engine = _engine()
        ..sendPaymentGate = Completer<void>()
        ..sendPaymentError = error;
      if (nativeStatus != null) {
        engine.sentPayment = _result(
          _bitcoinRoute,
          mismatchedAmount ? 101 : 100,
          status: nativeStatus,
        );
      }
      final harness = await _harness(tester, engine);
      const target = WalletPaymentTarget.bitcoinOnchain;
      final provider = sendFlowViewModelProvider(target);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await tester.runAsync(() => harness.container.read(provider.future));
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination(_bitcoinDestination);
      expect(await tester.runAsync(notifier.validateDestination), isTrue);
      notifier.updateAmount('0.000001');
      final router = _router(target);
      addTearDown(router.dispose);
      await _pumpRouter(tester, harness, router);
      unawaited(router.push<void>('/send/${target.slug}/amount'));
      await tester.pumpAndSettle();
      final send = tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
          .onTap!;
      send();
      await _pumpUntil(
        tester,
        () => engine.calls.contains('sendPayment:start'),
      );
      expect(find.byType(SendSuccessView), findsNothing);
      engine.sendPaymentGate!.complete();
      await _pumpUntil(
        tester,
        () => harness.container.read(provider).value?.failure != null,
      );
      await tester.pump();
      expect(
        tester
            .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
            .loading,
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(harness.toasts.messages, hasLength(1));
      final feedback = harness.toasts.messages.single;
      send();
      await tester.pump(const Duration(seconds: 10));
      expect(harness.container.read(provider).requireValue.result, isNull);
      expect(find.byType(SendSuccessView), findsNothing);
      expect(find.text('Payment sent'), findsNothing);
      expect(find.widgetWithText(CustomButton, 'Continue'), findsNothing);
      expect(find.byType(SendCard), findsOneWidget);
      expect(find.text('Wallet home'), findsNothing);
      expect(harness.toasts.messages, hasLength(2));
      expect(harness.toasts.messages.last.title, feedback.title);
      expect(harness.toasts.messages.last.message, feedback.message);
      expect(harness.toasts.messages.last.variant, feedback.variant);
      expect(find.text(feedback.message!), findsNothing);
      if (name == 'confirmed rejection') {
        expect(feedback.title, 'Unable to send');
        expect(feedback.variant, ToastVariant.failure);
      } else if (harness.container
          .read(provider)
          .requireValue
          .requiresReconciliation) {
        expect(feedback.title, 'Status unavailable');
        expect(feedback.variant, ToastVariant.warning);
      }
      expect(
        harness.toasts.messages.where(
          (message) => message.variant == ToastVariant.success,
        ),
        isEmpty,
      );
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, result, unit, exact) in [
    (
      'Bitcoin smallest amount',
      _result(_bitcoinRoute, 9),
      BitcoinUnit.bitcoin,
      '0.00000009 BTC',
    ),
    (
      'Bitcoin satoshi unit',
      _result(_bitcoinRoute, 123456789),
      BitcoinUnit.sats,
      '123,456,789 sats',
    ),
    (
      'Tether exact native limit',
      _result(testRgbRoute, WalletAmount.maxNativeUnits),
      BitcoinUnit.bitcoin,
      '9,223,372,036,854.775807 USDT',
    ),
  ]) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 568), 2.0),
    ]) {
      testWidgets('$name remains exact at ${size.width} and ${scale}x', (
        tester,
      ) async {
        _configurePhone(tester, size);
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SendSuccessView(
                result: result,
                bitcoinUnit: unit,
                onContinue: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final amount = find.widgetWithText(AmountText, exact);
        expect(amount, findsOneWidget);
        final amountWidget = tester.widget<AmountText>(amount);
        expect(amountWidget.maxLines, isNull);
        expect(amountWidget.overflow, isNot(TextOverflow.ellipsis));
        expect(amountWidget.textAlign, TextAlign.center);
        expect(find.byType(WalletAssetIcon), findsOneWidget);
        expect(
          tester.getCenter(find.byType(WalletAssetIcon)).dx,
          size.width / 2,
        );
        expect(find.text('Payment sent'), findsOneWidget);
        final continueButton = find.widgetWithText(CustomButton, 'Continue');
        await tester.ensureVisible(continueButton);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(continueButton).bottom,
          lessThanOrEqualTo(size.height - 34),
        );
        expect(tester.getRect(continueButton).top, greaterThanOrEqualTo(44));
        expect(tester, meetsGuideline(androidTapTargetGuideline));
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

FakeWalletEngine _engine() => FakeWalletEngine()
  ..balance = _bitcoinBalance(100000)
  ..balances[testRgbRoute.asset.id] = testRgbBalance(2000000)
  ..feeEstimate = WalletFeeRateEstimate(
    targetBlocks: 6,
    satsPerVbyte: 1,
    observedAt: _now,
  )
  ..decodedInvoice = WalletPaymentPreview(
    route: testRgbRoute,
    encodedDestination: 'rgb:synthetic-success-fixture',
    displayDestination: 'rgb:synthetic-success-fixture',
  );

Future<PaymentFlowTestHarness> _harness(
  WidgetTester tester,
  FakeWalletEngine engine,
) async {
  final transport = ResilientHttpClient(
    client: MockClient((_) async => http.Response('{}', 503)),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
  addTearDown(transport.close);
  final harness = await PaymentFlowTestHarness.create(
    engine: engine,
    services: testRgbServices,
    clock: () => _now,
    httpClient: transport,
  );
  addTearDown(() async {
    if (engine.sendPaymentGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    final disposal = harness.dispose();
    for (var frame = 0; frame < 3; frame += 1) {
      await tester.pump();
    }
    await disposal;
  });
  return harness;
}

GoRouter _router(WalletPaymentTarget target, {_HomeObserver? observer}) =>
    GoRouter(
      initialLocation: RoutePaths.home,
      observers: [?observer],
      routes: [
        GoRoute(
          path: RoutePaths.home,
          name: 'test-home',
          builder: (_, _) => const Scaffold(body: Text('Wallet home')),
        ),
        GoRoute(
          path: RoutePaths.sendAmount,
          builder: (_, _) => SendAmountScreen(target: target),
        ),
      ],
    );

Future<void> _pumpRouter(
  WidgetTester tester,
  PaymentFlowTestHarness harness,
  GoRouter router,
) {
  _configurePhone(tester, const Size(390, 844));
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

void _configurePhone(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  String Function()? diagnostic,
}) async {
  for (var frame = 0; frame < 200; frame += 1) {
    if (ready()) return;
    // Native-shaped repository work can inherit the real async zone used
    // while preparing the fixture. Yield it as well as rendering frames.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for Send state. ${diagnostic?.call() ?? ''}');
}

WalletSendResult _result(
  PaymentRoute route,
  int units, {
  WalletPaymentStatus status = WalletPaymentStatus.pending,
}) => WalletSendResult(
  route: route,
  amount: WalletAmount.onchain(assetId: route.asset.id, units: units),
  referenceId: 'b' * 64,
  status: status,
  batchTransferIndex: route.asset.kind == WalletAssetKind.usdt ? 1 : null,
);

WalletBalance _bitcoinBalance(int units) {
  WalletAmount onchain(int value) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: value);
  final noLightning = WalletAmount.lightning(
    assetId: WalletAsset.bitcoin.id,
    units: 0,
  );
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(units),
    onchainFuture: onchain(units),
    onchainSpendable: onchain(units),
    onchainLocked: onchain(0),
    lightningOwned: noLightning,
    lightningSpendable: noLightning,
    lightningReceivable: noLightning,
  );
}

final class _HomeObserver extends NavigatorObserver {
  var homeEntries = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'test-home') homeEntries += 1;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute?.settings.name == 'test-home') homeEntries += 1;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.settings.name == 'test-home') homeEntries += 1;
  }
}
