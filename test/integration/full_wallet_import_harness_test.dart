import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/wallet_selection_screen.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../integration_test/support/full_wallet_import_transfer.dart';
import '../../integration_test/support/full_wallet_qa.dart';
import '../../integration_test/support/full_wallet_rgb_setup.dart';
import '../../integration_test/support/full_wallet_test_guard.dart';
import '../support/onboarding_harness.dart';

void main() {
  testWidgets(
    'selection waits for owned ModalRoute removal across real WalletVM router refresh',
    (tester) async {
      final transport = ResilientHttpClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'bitcoin': {
                'usd': 65000,
                'last_updated_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
              'prices': <Object>[],
            }),
            200,
          ),
        ),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final h = await OnboardingTestHarness.create(httpClient: transport);
      addTearDown(transport.close);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final closing = h.dispose();
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        await closing;
      });
      final first = (await h.repository.createFromMnemonic(
        mnemonic: validTestMnemonic,
        name: 'First',
      ) as AppSuccess<WalletRegistry>).value;
      await h.container.read(walletViewModelProvider.future);
      final second = (await h.repository.createFromMnemonic(
        mnemonic: validTestMnemonic,
        name: 'Second',
      ) as AppSuccess<WalletRegistry>).value;
      h.container
          .read(walletViewModelProvider.notifier)
          .adoptCommittedRegistry(second);
      final firstId = first.activeWalletId!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: ref.watch(appRouterProvider),
              builder: (context, child) => AsterFeedbackScope(
                haptics: h.haptics,
                toasts: h.toasts,
                child: child!,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      final router = h.container.read(appRouterProvider);
      router.go('/receive/bitcoin-onchain');
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      final gate = Completer<void>();
      h.engines[2].openPersistedGate = gate;
      var lockedFrames = 0;
      var releaseStarted = false;
      final subscription = h.container.listen(walletViewModelProvider, (
        _,
        next,
      ) {
        if (!releaseStarted && next.value?.switchingWalletId != null) {
          releaseStarted = true;
          unawaited(() async {
            await WidgetsBinding.instance.endOfFrame;
            lockedFrames += 1;
            await WidgetsBinding.instance.endOfFrame;
            lockedFrames += 1;
            gate.complete();
          }());
        }
      });
      addTearDown(subscription.close);
      await qualifyWalletSelectionUi(
        tester: tester,
        router: router,
        walletRow: find.byKey(ValueKey('wallet-$firstId')),
        selector: find.byType(WalletSelectionScreen),
        committed: () =>
            h.container.read(walletViewModelProvider).value?.activeWallet?.id ==
                firstId &&
            h.container
                    .read(walletViewModelProvider)
                    .value
                    ?.switchingWalletId ==
                null,
      );
      final current = h.container.read(walletViewModelProvider).value;
      expect(lockedFrames, 2);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/receive/bitcoin-onchain',
      );
      expect(current?.activeWallet?.id, firstId);
      expect(find.byType(WalletSelectionScreen), findsNothing);
    },
  );
  testWidgets(
    'uncaught async callback remains latched after pending exception is cleared',
    (tester) async {
      final latch = FullWalletQaFrameworkErrorLatch();
      var normalHandlerCalls = 0;
      final previous = FlutterError.onError!;
      FlutterError.onError = (details) {
        latch.notice();
        normalHandlerCalls += 1;
        previous(details);
      };
      try {
        runZonedGuarded<void>(
          () {
            unawaited(
              Future<void>.microtask(
                () => throw StateError('public asynchronous fixture'),
              ),
            );
          },
          (error, stack) {
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack),
            );
          },
        );
        await tester.pump();
        expect(normalHandlerCalls, 1);
        expect(tester.takeException(), isA<StateError>());
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = previous;
      }
      var financialDispatches = 0;
      final control = FullWalletQaControl(
        runId: 'public-latched-error',
        controlUrl: 'http://127.0.0.1:29671',
        beforeFinancialDispatch: () {
          latch.requireHealthy(tester);
          financialDispatches += 1;
        },
      );
      addTearDown(control.close);
      await expectLater(
        control.request('fund_requested', {
          'address': 'public fixture',
          'amount_sats': 1,
        }),
        throwsA(
          isA<FullWalletQaFailure>().having(
            (error) => error.code,
            'code',
            'qa_framework_async_error',
          ),
        ),
      );
      expect(financialDispatches, 0);
      expect(
        () => latch.requireHealthy(tester),
        throwsA(isA<FullWalletQaFailure>()),
      );
    },
  );

  testWidgets(
    'wallet selection waits for delayed route pop after wallet commit',
    (tester) async {
      var committed = false;
      var callbackCompleted = false;
      const selectorKey = ValueKey('public-wallet-selector');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: RoutePaths.walletSelectionLocation,
            builder: (context, _) => Scaffold(
              key: selectorKey,
              body: TextButton(
                onPressed: () async {
                  committed = true;
                  await WidgetsBinding.instance.endOfFrame;
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (!context.mounted) return;
                  context.pop();
                  callbackCompleted = true;
                },
                child: const Text('Select existing wallet'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await qualifyWalletSelectionUi(
        tester: tester,
        router: router,
        walletRow: find.text('Select existing wallet'),
        selector: find.byKey(selectorKey),
        committed: () => committed,
      );
      expect(committed, isTrue);
      expect(callbackCompleted, isTrue);
      expect(router.canPop(), isFalse);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  WalletActivity transfer(
    WalletActivityStatus status, {
    int units = 1000000,
    WalletActivityDirection direction = WalletActivityDirection.sent,
  }) {
    final asset = WalletAsset.rgbUsdt(
      assetId: 'rgb:public-fixture',
      precision: 6,
    );
    return WalletActivity(
      id: 'activity-${'1' * 64}',
      source: WalletActivitySource.rgbTransfer,
      operation: direction == WalletActivityDirection.sent
          ? WalletActivityOperation.rgbSend
          : WalletActivityOperation.rgbReceive,
      asset: asset,
      rail: PaymentRail.onchain,
      direction: direction,
      status: status,
      amount: WalletAmount.onchain(assetId: asset.id, units: units),
      transferIndex: 1,
      txid: '3' * 64,
    );
  }

  test(
    'original RGB checkpoint admits native ACK and confirmation waiting states',
    () {
      for (final status in [
        WalletActivityStatus.pending,
        WalletActivityStatus.waitingCounterparty,
        WalletActivityStatus.waitingSafeHeight,
        WalletActivityStatus.waitingBroadcast,
        WalletActivityStatus.waitingConfirmations,
        WalletActivityStatus.succeeded,
      ]) {
        expect(
          () => requireQaOriginalTransferCheckpoint(
            identityMatches: true,
            matches: [transfer(status)],
            amountUnits: 1000000,
          ),
          returnsNormally,
        );
      }
    },
  );

  test('original RGB checkpoint rejects terminal and unrelated states with public diagnostics', () {
    for (final status in [
      WalletActivityStatus.failed,
      WalletActivityStatus.cancelled,
      WalletActivityStatus.expired,
      WalletActivityStatus.claimable,
      WalletActivityStatus.claiming,
    ]) {
      expect(
        () => requireQaOriginalTransferCheckpoint(
          identityMatches: true,
          matches: [transfer(status)],
          amountUnits: 1000000,
        ),
        throwsA(
          isA<FullWalletQaFailure>()
              .having(
                (failure) => failure.diagnostics.single['status'],
                'public status',
                status.name,
              )
              .having(
                (failure) => failure.diagnostics.single['status_admitted'],
                'status_admitted',
                false,
              ),
        ),
      );
    }
  });

  test('original RGB checkpoint retains exact identity, unique direction and amount guards', () {
    for (final fixture in [
      (false, [transfer(WalletActivityStatus.waitingCounterparty)]),
      (true, <WalletActivity>[]),
      (
        true,
        [
          transfer(WalletActivityStatus.waitingCounterparty),
          transfer(WalletActivityStatus.waitingCounterparty),
        ],
      ),
      (true, [transfer(WalletActivityStatus.waitingCounterparty, units: 1)]),
      (
        true,
        [
          transfer(
            WalletActivityStatus.waitingCounterparty,
            direction: WalletActivityDirection.received,
          ),
        ],
      ),
    ]) {
      expect(
        () => requireQaOriginalTransferCheckpoint(
          identityMatches: fixture.$1,
          matches: fixture.$2,
          amountUnits: 1000000,
        ),
        throwsA(isA<FullWalletQaFailure>()),
      );
    }
  });

  testWidgets('wallet selection has the production pop-owned back stack', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: RoutePaths.walletSelectionLocation,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Select existing wallet'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    unawaited(pushQaWalletSelector(router));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);
    await tester.tap(find.text('Select existing wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending framework error stops the next financial command', (
    tester,
  ) async {
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('public fixture failure')),
    );
    var dispatched = false;
    final control = FullWalletQaControl(
      runId: 'public-guard-test',
      controlUrl: 'http://127.0.0.1:29671',
      beforeFinancialDispatch: () {
        requireQaFrameworkHealthy(tester);
        dispatched = true;
      },
    );
    addTearDown(control.close);
    await expectLater(
      control.request('fund_requested', {
        'address': 'public fixture',
        'amount_sats': 1,
      }),
      throwsA(
        isA<FullWalletQaFailure>().having(
          (value) => value.code,
          'code',
          'qa_framework_async_error',
        ),
      ),
    );
    expect(dispatched, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('witness receive rejects retained loading data and blind decoding', () {
    final route = PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: 'rgb:public-fixture', precision: 6),
      rail: PaymentRail.onchain,
    );
    final state = ReceiveFlowState(
      route: route,
      bitcoinUnit: BitcoinUnit.sats,
      request: WalletReceiveRequest(
        route: route,
        encodedRequest: 'public-invoice',
        displayValue: 'public-invoice',
      ),
      amountText: '',
      amountInput: const WalletAmountInputCodec().parse(
        text: '',
        route: route,
        bitcoinUnit: BitcoinUnit.sats,
      ),
    );
    final data = AsyncData(state);
    expect(qaWitnessReceiveReady(data), isTrue);
    expect(
      qaWitnessReceiveReady(
        AsyncData(
          state.copyWith(operation: ReceiveFlowOperation.generatingRequest),
        ),
      ),
      isFalse,
    );
    expect(
      qaWitnessReceiveReady(
        AsyncData(
          state.copyWith(
            request: WalletReceiveRequest(
              route: route,
              encodedRequest: 'public-expired-invoice',
              displayValue: 'public-expired-invoice',
              expiresAt: DateTime.utc(2020),
            ),
          ),
        ),
      ),
      isFalse,
    );
    final previousError = AsyncError<ReceiveFlowState>(
      StateError('public-fixture'),
      StackTrace.empty,
    );
    expect(
      qaWitnessReceiveReady(
        // Error-with-previous-data must never qualify a retained invoice.
        // ignore: invalid_use_of_internal_member
        previousError.copyWithPrevious(data),
      ),
      isFalse,
    );
    expect(
      qaWitnessReceiveReady(
        // Reproduce Riverpod's retained-data loading state at the boundary.
        // ignore: invalid_use_of_internal_member
        const AsyncLoading<ReceiveFlowState>().copyWithPrevious(data),
      ),
      isFalse,
    );
    WalletPaymentPreview preview(RgbRecipientType? type) =>
        WalletPaymentPreview(
          route: route,
          encodedDestination: 'public-invoice',
          displayDestination: 'public-invoice',
          rgbRecipientType: type,
        );
    expect(
      () => requireQaWitnessPreview(preview(RgbRecipientType.witness)),
      returnsNormally,
    );
    expect(
      () => requireQaWitnessPreview(preview(RgbRecipientType.blind)),
      throwsA(isA<FullWalletQaFailure>()),
    );
    expect(
      () => requireQaWitnessPreview(preview(null)),
      throwsA(isA<FullWalletQaFailure>()),
    );
    // Old blind checkpoints stay readable without reserving another invoice.
    expect(
      () => requireQaBlindPreview(preview(RgbRecipientType.blind)),
      returnsNormally,
    );
    expect(
      () => requireQaBlindPreview(preview(RgbRecipientType.witness)),
      throwsA(isA<FullWalletQaFailure>()),
    );
  });

  testWidgets(
    'import Continue dismisses an obstructing input keyboard before one tap',
    (tester) async {
      var taps = 0;
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: _ObstructedContinue(
            onContinue: () => taps += 1,
            onFocusChanged: (focused) => tester.view.viewInsets =
                FakeViewPadding(bottom: focused ? 320 : 0),
          ),
        ),
      );
      // This public marker is not a mnemonic and never reaches wallet APIs.
      await tester.enterText(
        find.byKey(const ValueKey('public-input-fixture')),
        'public input',
      );
      await tester.pump();
      final button = find.widgetWithText(CustomButton, 'Continue');
      expect(button, findsOneWidget);
      expect(button.hitTestable(), findsNothing);
      expect(tester.view.viewInsets.bottom, 320);

      await qualifyImportContinueUi(tester);

      expect(taps, 1);
      expect(tester.view.viewInsets.bottom, 0);
      expect(button.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _ObstructedContinue extends StatefulWidget {
  const _ObstructedContinue({
    required this.onContinue,
    required this.onFocusChanged,
  });
  final VoidCallback onContinue;
  final ValueChanged<bool> onFocusChanged;
  @override
  State<_ObstructedContinue> createState() => _ObstructedContinueState();
}

class _ObstructedContinueState extends State<_ObstructedContinue> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  void _changed() {
    widget.onFocusChanged(_focus.hasFocus);
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    body: Stack(
      children: [
        Column(
          children: [
            TextField(
              key: const ValueKey('public-input-fixture'),
              focusNode: _focus,
            ),
            const Spacer(),
            CustomButton(text: 'Continue', onTap: widget.onContinue),
          ],
        ),
        if (_focus.hasFocus)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 320,
            child: ColoredBox(color: Colors.grey),
          ),
      ],
    ),
  );
}
