import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/transaction/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Activity renders exact cross-rail records and privacy state', (
    tester,
  ) async {
    final harness = await _harness(
      preferenceValues: const {'utexo.settings.v1.bitcoin_unit': 'sats'},
    );
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
      textScaler: const TextScaler.linear(2),
    );
    await _pumpUntil(
      tester,
      () => find.text('-1.5 sats').evaluate().isNotEmpty,
    );

    expect(find.text('+100 sats'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byType(TransactionItem), findsNWidgets(2));
    expect(
      find.bySemanticsLabel(RegExp(r'Sent, Lightning, -1\.5 sats, Completed')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('Activity routes to details by opaque ID only', (tester) async {
    final harness = await _harness();
    addTearDown(() => _disposeHarness(tester, harness));
    final router = GoRouter(
      initialLocation: '/transactions/bitcoin',
      routes: [
        GoRoute(
          path: '/transactions/:assetKind',
          name: RouteNames.transactionList,
          builder: (context, state) =>
              const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
        ),
        GoRoute(
          path: '/transactions/:assetKind/:activityId',
          name: RouteNames.transactionDetails,
          builder: (context, state) =>
              Text('Details ${state.pathParameters['activityId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await _pumpRouter(tester, harness, router);
    await _pumpUntil(
      tester,
      () => find.byType(TransactionItem).evaluate().length == 2,
    );
    await tester.tap(find.byType(TransactionItem).first);
    await tester.pumpAndSettle();

    expect(find.text('Details ${_lightningActivity().id}'), findsOneWidget);
    expect(harness.haptics.intents, contains(HapticIntent.lightImpact));
  });

  testWidgets('mounted Activity advances its local calendar at midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 12, 23, 59, 59, 998).toUtc();
    final eventAt = DateTime(2026, 8, 12, 12).toUtc();
    final engine = FakeWalletEngine()
      ..activities = <WalletActivity>[
        WalletActivity(
          id: 'activity-${'c' * 64}',
          source: WalletActivitySource.bitcoinTransaction,
          operation: WalletActivityOperation.bitcoinReceive,
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
          direction: WalletActivityDirection.received,
          status: WalletActivityStatus.succeeded,
          amount: WalletAmount.onchain(
            assetId: WalletAsset.bitcoin.id,
            units: 100,
          ),
          occurredAt: eventAt,
          txid: 'c' * 64,
        ),
      ];
    final harness = await _harness(engine: engine, clock: () => now);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
    );
    await _pumpUntil(tester, () => find.text('Today').evaluate().isNotEmpty);

    now = DateTime(2026, 8, 13, 0, 0, 0, 2).toUtc();
    await tester.pump(const Duration(milliseconds: 5));

    expect(find.text('Today'), findsNothing);
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('Details exposes available data, copy, and explorer actions', (
    tester,
  ) async {
    final harness = await _harness(
      preferenceValues: const {'utexo.settings.v1.bitcoin_unit': 'sats'},
    );
    addTearDown(() => _disposeHarness(tester, harness));
    final record = _onchainActivity();

    await _pump(
      tester,
      harness,
      TransactionDetailsScreen(
        assetKind: WalletAssetKind.bitcoin,
        activityId: record.id,
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('+100 sats').evaluate().isNotEmpty,
    );

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Signet'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'Bitcoin, Received, \+100 sats, Completed'),
      ),
      findsOneWidget,
    );
    final statusRow = find.ancestor(
      of: find.text('Status'),
      matching: find.byType(TransactionDetailRow),
    );
    expect(
      find.descendant(of: statusRow, matching: find.byType(NumericText)),
      findsOneWidget,
    );
    final transactionIdRow = find.ancestor(
      of: find.text('Transaction ID'),
      matching: find.byType(TransactionDetailRow),
    );
    expect(
      find.descendant(of: transactionIdRow, matching: find.byType(NumericText)),
      findsNothing,
    );

    final copy = find.byTooltip('Copy Transaction ID');
    await tester.ensureVisible(copy);
    final copySemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Copy Transaction ID',
    );
    expect(copySemantics, findsOneWidget);
    expect(tester.widget<Semantics>(copySemantics).properties.onTap, isNotNull);
    await tester.scrollUntilVisible(
      copy,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pump();
    expect(harness.clipboard.text, 'a' * 64);
    expect(harness.toasts.messages.last.title, 'Transaction ID copied');

    final explorer = find.widgetWithText(CustomButton, 'View in explorer');
    await tester.ensureVisible(explorer);
    await tester.tap(explorer);
    await tester.pump();
    expect(
      harness.externalUris.openedUri.toString(),
      'https://mempool.space/signet/tx/${'a' * 64}',
    );
  });

  testWidgets('Details fails honestly when an opaque ID is not in the wallet', (
    tester,
  ) async {
    final harness = await _harness();
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      TransactionDetailsScreen(
        assetKind: WalletAssetKind.bitcoin,
        activityId: 'activity-${'f' * 64}',
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .text('This transaction is no longer available.')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.text('This transaction is no longer available.'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel('This transaction is no longer available.'),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.widgetWithText(CustomButton, 'Retry'), findsOneWidget);

    harness.engine.syncGate = Completer<void>();
    final retry = find.widgetWithText(CustomButton, 'Retry');
    await tester.tap(retry);
    await tester.pump();
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).loading,
      isTrue,
    );
    await tester.tap(find.byType(CustomButton));
    expect(harness.engine.calls.where((call) => call == 'sync'), hasLength(1));

    harness.engine.syncGate!.complete();
    await _pumpUntil(
      tester,
      () =>
          find.widgetWithText(CustomButton, 'Retry').evaluate().isNotEmpty &&
          !tester
              .widget<CustomButton>(find.widgetWithText(CustomButton, 'Retry'))
              .loading,
    );
  });

  testWidgets('Activity failure is live and preserves explicit retry', (
    tester,
  ) async {
    const failure = AppFailure(
      code: 'activity_temporarily_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Activity is temporarily unavailable.',
      retryable: true,
    );
    final engine = FakeWalletEngine()
      ..activityError = const AppFailureException(failure);
    final harness = await _harness(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
    );
    await _pumpUntil(
      tester,
      () => find.text(failure.userMessage).evaluate().isNotEmpty,
    );

    final message = find.bySemanticsLabel(failure.userMessage);
    expect(tester.getSemantics(message).flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Retry'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('Activity and details loading expose only truthful live nodes', (
    tester,
  ) async {
    final engine = FakeWalletEngine()..activityGate = Completer<void>();
    final harness = await _harness(engine: engine);
    addTearDown(() => _disposeHarness(tester, harness));

    await _pump(
      tester,
      harness,
      const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
    );
    await _pumpUntil(tester, () => engine.calls.contains('activity'));
    final activityLoading = find.bySemanticsLabel('Loading activity');
    expect(activityLoading, findsOneWidget);
    expect(
      tester.getSemantics(activityLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.bySemanticsLabel(RegExp(r'Sent|Received')), findsNothing);

    await _pump(
      tester,
      harness,
      TransactionDetailsScreen(
        assetKind: WalletAssetKind.bitcoin,
        activityId: _onchainActivity().id,
      ),
    );
    final detailsLoading = find.bySemanticsLabel('Loading transaction details');
    expect(detailsLoading, findsOneWidget);
    expect(
      tester.getSemantics(detailsLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.text('Transaction ID'), findsNothing);

    engine.activityGate!.complete();
  });
}

Future<PaymentFlowTestHarness> _harness({
  Map<String, Object> preferenceValues = const {},
  FakeWalletEngine? engine,
  UtcClock? clock,
}) {
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.signet,
    sdkNetwork: 'utexo',
    explorerBaseUrl: 'https://mempool.space/signet',
  );
  final selectedEngine = engine ?? FakeWalletEngine();
  selectedEngine.balance ??= _bitcoinBalance();
  selectedEngine.networkStatus ??= WalletNetworkStatus(
    environment: BlockchainEnvironment.signet,
    blockHeight: 102,
    nodePublicKey:
        '020000000000000000000000000000000000000000000000000000000000000000',
    channelCount: 0,
    usableChannelCount: 0,
    peerCount: 0,
  );
  if (selectedEngine.activities.isEmpty) {
    selectedEngine.activities = <WalletActivity>[
      _lightningActivity(),
      _onchainActivity(),
    ];
  }
  return PaymentFlowTestHarness.create(
    engine: selectedEngine,
    services: services,
    preferenceValues: preferenceValues,
    clock: clock ?? () => DateTime.utc(2026, 8, 12, 12),
  );
}

WalletActivity _lightningActivity() => WalletActivity(
  id: 'activity-${'b' * 64}',
  source: WalletActivitySource.lightningPayment,
  operation: WalletActivityOperation.lightningPayment,
  asset: WalletAsset.bitcoin,
  rail: PaymentRail.lightning,
  direction: WalletActivityDirection.sent,
  status: WalletActivityStatus.succeeded,
  amount: WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: 1500),
  occurredAt: DateTime.utc(2026, 8, 11, 12),
  paymentHash: 'b' * 64,
  invoice: 'lnbc1testinvoice',
);

WalletActivity _onchainActivity() => WalletActivity(
  id: 'activity-${'a' * 64}',
  source: WalletActivitySource.bitcoinTransaction,
  operation: WalletActivityOperation.bitcoinReceive,
  asset: WalletAsset.bitcoin,
  rail: PaymentRail.onchain,
  direction: WalletActivityDirection.received,
  status: WalletActivityStatus.succeeded,
  amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 100),
  occurredAt: DateTime.utc(2026, 8, 11, 10),
  confirmedAt: DateTime.utc(2026, 8, 11, 10),
  confirmationHeight: 100,
  txid: 'a' * 64,
);

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
  fail('Timed out waiting for Activity UI state.');
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
