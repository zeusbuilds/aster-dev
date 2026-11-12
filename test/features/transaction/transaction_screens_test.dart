import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:aster/features/transaction/presentation/models/models.dart';
import 'package:aster/features/transaction/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
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

  testWidgets('identifier and explorer handoffs stay quiet and single-owned', (
    tester,
  ) async {
    final harness = await _harness();
    addTearDown(() => _disposeHarness(tester, harness));
    final clipboard = _PendingClipboard();
    final externalUris = _PendingExternalUris();
    final record = _onchainActivity();
    final container = ProviderContainer(
      parent: harness.container,
      overrides: [
        clipboardServiceProvider.overrideWithValue(clipboard),
        externalUriServiceProvider.overrideWithValue(externalUris),
        transactionDetailsActionsViewModelProvider(
          record.id,
          record.txid,
        ).overrideWith(TransactionDetailsActionsViewModel.new),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await tester.pump();
    });
    await _pump(
      tester,
      harness,
      TransactionDetailsScreen(
        assetKind: WalletAssetKind.bitcoin,
        activityId: record.id,
      ),
      container: container,
    );
    final copy = find.byTooltip('Copy Transaction ID');
    await _pumpUntil(tester, () => copy.evaluate().isNotEmpty);
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    final copyWidget = find.byWidgetPredicate(
      (widget) =>
          widget is AsterIconButton && widget.tooltip == 'Copy Transaction ID',
    );
    final beforeCopy = tester.widget<AsterIconButton>(copyWidget);
    final copyRect = tester.getRect(copyWidget);
    beforeCopy.onPressed!();
    beforeCopy.onPressed!();
    await tester.pump();
    expect(clipboard.writes, 1);
    expect(tester.widget<AsterIconButton>(copyWidget).icon, beforeCopy.icon);
    expect(tester.widget<AsterIconButton>(copyWidget).loading, false);
    expect(tester.getRect(copyWidget), copyRect);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Copy Transaction ID'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      false,
    );
    await tester.tap(copy, warnIfMissed: false);
    expect(clipboard.writes, 1);
    clipboard.result.complete(const AppResult.success(null));
    await tester.pumpAndSettle();
    expect(harness.toasts.messages.single.title, 'Transaction ID copied');

    final explorer = find.widgetWithText(CustomButton, 'View in explorer');
    await tester.ensureVisible(explorer);
    await tester.pumpAndSettle();
    final explorerRect = tester.getRect(explorer);
    final open = tester.widget<CustomButton>(explorer).onTap!;
    open();
    open();
    await tester.pump();
    expect(externalUris.opens, 1);
    expect(tester.widget<CustomButton>(explorer).loading, false);
    expect(tester.widget<CustomButton>(explorer).enabled, true);
    expect(tester.getRect(explorer), explorerRect);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('View in explorer'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      false,
    );
    await tester.tap(explorer, warnIfMissed: false);
    expect(externalUris.opens, 1);
    externalUris.result.complete(
      const AppResult.failure(
        AppFailure(
          code: 'external_uri_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'The explorer could not open.',
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.toasts.messages.last.title, 'Could not open explorer');
    expect(find.text('The explorer could not open.'), findsNothing);
    externalUris.result = Completer<AppResult<void>>()
      ..complete(const AppResult.success(null));
    await tester.tap(explorer);
    await tester.pumpAndSettle();
    expect(externalUris.opens, 2);
    expect(harness.toasts.messages, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final (unit, amount, fee) in [
    ('btc', '0.05 BTC', '0.00000155 BTC'),
    ('sats', '5,000,000 sats', '155 sats'),
  ]) {
    testWidgets(
      'self transfer uses exact reviewed $unit amount on Activity and details',
      (tester) async {
        final native = WalletActivity(
          id: 'activity-${'f' * 64}',
          source: WalletActivitySource.bitcoinTransaction,
          operation: WalletActivityOperation.bitcoinSelfTransfer,
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
          direction: WalletActivityDirection.internal,
          status: WalletActivityStatus.succeeded,
          fee: WalletAmount.onchain(
            assetId: WalletAsset.bitcoin.id,
            units: 155,
          ),
          occurredAt: DateTime.utc(2026, 8, 11, 10),
          confirmedAt: DateTime.utc(2026, 8, 11, 10),
          confirmationHeight: 100,
          txid: 'f' * 64,
        );
        final record = native.withReviewedAmount(
          WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 5000000),
        );
        final engine = FakeWalletEngine()..activities = [record];
        final harness = await _harness(
          engine: engine,
          preferenceValues: {'aster.settings.v1.bitcoin_unit': unit},
        );
        addTearDown(() => _disposeHarness(tester, harness));
        await _pump(
          tester,
          harness,
          const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
        );
        await _pumpUntil(
          tester,
          () => find.text('Transfer to self').evaluate().isNotEmpty,
        );
        expect(find.widgetWithText(AmountText, amount), findsOneWidget);
        expect(find.text('Amount unavailable'), findsNothing);
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Transfer to self, on-chain, ${RegExp.escape(amount)}, Completed',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Sent'), findsNothing);

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
          () => find.text('Network fee').evaluate().isNotEmpty,
        );
        expect(find.text('Transfer to self'), findsWidgets);
        expect(find.widgetWithText(AmountText, amount), findsWidgets);
        expect(find.widgetWithText(AmountText, fee), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Bitcoin, Transfer to self, $amount, Completed',
          ),
          findsOneWidget,
        );
        expect(find.text('Amount unavailable'), findsNothing);
        expect(find.text('-$amount'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Activity retains an accepted receipt before native history catches up',
    (tester) async {
      final now = DateTime.now().toUtc();
      final engine = FakeWalletEngine()
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final harness = await _harness(engine: engine, clock: () => now);
      addTearDown(() => _disposeHarness(tester, harness));
      final result = await harness.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 1,
        reviewedFeeRate: engine.feeEstimate,
      );
      expect(result, isA<AppSuccess<WalletSendResult>>());
      await _pump(
        tester,
        harness,
        const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
        textScaler: const TextScaler.linear(2),
      );
      await _pumpUntil(
        tester,
        () => find.textContaining('Submitted').evaluate().isNotEmpty,
      );
      expect(find.text('Previous send submitted'), findsNothing);
      expect(find.text('b' * 64), findsNothing);
      expect(find.text('Check payment status'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Activity exposes unknown submission and checks status without sending',
    (tester) async {
      final now = DateTime.now().toUtc();
      final engine = FakeWalletEngine()
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        )
        ..sendPaymentError = StateError('Lost native response');
      final harness = await _harness(engine: engine, clock: () => now);
      addTearDown(() => _disposeHarness(tester, harness));
      await harness.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 1,
        reviewedFeeRate: engine.feeEstimate,
      );
      await _pump(
        tester,
        harness,
        const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
      );
      await _pumpUntil(
        tester,
        () => find.textContaining('Status unavailable').evaluate().isNotEmpty,
      );
      expect(find.text('Payment status needs checking'), findsNothing);
      expect(find.text('Check payment status'), findsNothing);
      final feed = harness.container
          .read(activityViewModelProvider(WalletAssetKind.bitcoin))
          .requireValue
          .feed;
      final display = PaymentSubmissionDisplay(feed.paymentSubmission!);
      await _pump(
        tester,
        harness,
        TransactionDetailsScreen(
          assetKind: WalletAssetKind.bitcoin,
          activityId: display.id,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Check status').evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text('Check status'));
      await tester.tap(find.text('Check status'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => !harness.container
            .read(activityViewModelProvider(WalletAssetKind.bitcoin))
            .requireValue
            .refreshing,
      );
      expect(find.text('Payment status needs checking'), findsNothing);
      expect(find.text('Status unavailable'), findsWidgets);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an accepted receipt repair stays reachable from matching completed native history',
    (tester) async {
      final now = DateTime.now().toUtc();
      final native = WalletActivity(
        id: 'activity-${'c' * 64}',
        txid: 'b' * 64,
        source: WalletActivitySource.bitcoinTransaction,
        operation: WalletActivityOperation.bitcoinSend,
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
        direction: WalletActivityDirection.sent,
        status: WalletActivityStatus.succeeded,
        amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 1),
        occurredAt: now,
        confirmationHeight: 100,
        confirmedAt: now,
      );
      final engine = FakeWalletEngine()
        ..activities = [native]
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final harness = await _harness(engine: engine, clock: () => now);
      addTearDown(() => _disposeHarness(tester, harness));
      final journal =
          harness.repository.paymentJournalStore!
              as MemoryWalletPaymentJournalStore;
      journal.receiptWriteError = StateError('Receipt store unavailable');
      final result = await harness.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 1,
        reviewedFeeRate: engine.feeEstimate,
      );
      expect(result, isA<AppSuccess<WalletSendResult>>());
      await _pump(
        tester,
        harness,
        const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
      );
      await _pumpUntil(tester, () => find.text('Sent').evaluate().isNotEmpty);
      expect(find.byType(PaymentSubmissionItem), findsNothing);
      expect(find.text('Sent'), findsOneWidget);
      await _pump(
        tester,
        harness,
        TransactionDetailsScreen(
          assetKind: WalletAssetKind.bitcoin,
          activityId: native.id,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Completed').evaluate().isNotEmpty,
      );
      expect(find.text('Completed'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Check status'), 300);
      expect(find.text('Check status'), findsOneWidget);
      final saved = harness.container
          .read(activityViewModelProvider(WalletAssetKind.bitcoin))
          .requireValue
          .feed
          .paymentSubmission!;
      await _pump(
        tester,
        harness,
        TransactionDetailsScreen(
          assetKind: WalletAssetKind.bitcoin,
          activityId: PaymentSubmissionDisplay(saved).id,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Completed').evaluate().isNotEmpty,
      );
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Submitted'), findsNothing);
      await tester.scrollUntilVisible(find.text('Saving pending'), 200);
      expect(find.text('Saving pending'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Check status'), 300);
      await tester.tap(find.text('Check status'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => !harness.container
            .read(activityViewModelProvider(WalletAssetKind.bitcoin))
            .requireValue
            .refreshing,
      );
      expect(find.text('Check status'), findsOneWidget);
      expect(harness.toasts.messages.last.title, 'Payment submitted');
      expect(engine.paymentOperations.dispatchCount, 1);
      journal.receiptWriteError = null;
      await tester.tap(find.text('Check status'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('Check status').evaluate().isEmpty,
      );
      expect(find.text('Completed'), findsWidgets);
      expect(engine.paymentOperations.dispatchCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UXA-013 details retain content through refresh, failure and recovery',
    (tester) async {
      final pending = WalletActivity(
        id: 'activity-${'a' * 64}',
        txid: 'a' * 64,
        source: WalletActivitySource.bitcoinTransaction,
        operation: WalletActivityOperation.bitcoinReceive,
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
        direction: WalletActivityDirection.received,
        status: WalletActivityStatus.pending,
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 100,
        ),
      );
      final gate = Completer<void>();
      final engine = FakeWalletEngine()
        ..activities = [pending]
        ..syncGate = gate;
      final harness = await _harness(engine: engine);
      addTearDown(() => _disposeHarness(tester, harness));
      await _pump(
        tester,
        harness,
        TransactionDetailsScreen(
          assetKind: WalletAssetKind.bitcoin,
          activityId: pending.id,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Pending').evaluate().isNotEmpty,
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byTooltip('Refresh transaction'), findsNothing);
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      final refreshing = refresh();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      const failure = AppFailure(
        code: 'test_offline',
        kind: AppFailureKind.connectivity,
        userMessage: 'Network unavailable. Try again.',
        retryable: true,
      );
      engine.syncError = AppFailureException(failure);
      gate.complete();
      await refreshing;
      await tester.pump();
      await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
      expect(find.text(failure.userMessage), findsNothing);
      expect(find.text('Received'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        harness.container
            .read(activityViewModelProvider(WalletAssetKind.bitcoin))
            .requireValue
            .refreshing,
        isFalse,
      );
      engine.syncError = null;
      engine.activities = [_onchainActivity()];
      await refresh();
      await _pumpUntil(
        tester,
        () => find.text('Completed').evaluate().isNotEmpty,
      );
      expect(find.text(failure.userMessage), findsNothing);
      expect(engine.calls.where((call) => call == 'sync'), hasLength(2));
    },
  );

  testWidgets('Activity renders exact cross-rail records and privacy state', (
    tester,
  ) async {
    final harness = await _harness(
      preferenceValues: const {'aster.settings.v1.bitcoin_unit': 'sats'},
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
    await tester.tap(find.byType(TransactionItem).first);
    await tester.pumpAndSettle();

    expect(find.text('Details ${_lightningActivity().id}'), findsOneWidget);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Details ${_lightningActivity().id}'), findsNothing);
    expect(find.byType(TransactionItem), findsNWidgets(2));
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

  testWidgets('Activity and details scroll beneath the bottom system inset', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final harness = await _harness();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(
      tester,
      harness,
      const TransactionListScreen(assetKind: WalletAssetKind.bitcoin),
    );
    await _pumpUntil(
      tester,
      () => find.byType(TransactionItem).evaluate().length == 2,
    );
    final activityScroll = find.byType(CustomScrollView);
    expect(tester.getRect(activityScroll).bottom, 844);
    final activityPosition = tester
        .state<ScrollableState>(
          find
              .descendant(of: activityScroll, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    activityPosition.jumpTo(activityPosition.maxScrollExtent);
    await tester.pump();
    final bottomPadding = tester
        .widgetList<SizedBox>(
          find.descendant(of: activityScroll, matching: find.byType(SizedBox)),
        )
        .where(
          (box) =>
              box.height == 34 + tester.element(activityScroll).spacing.xxl,
        );
    expect(bottomPadding, isNotEmpty);

    await _pump(
      tester,
      harness,
      TransactionDetailsScreen(
        assetKind: WalletAssetKind.bitcoin,
        activityId: _onchainActivity().id,
      ),
    );
    await _pumpUntil(tester, () => find.text('Received').evaluate().isNotEmpty);
    final detailsScroll = find.byType(CustomScrollView);
    expect(tester.getRect(detailsScroll).bottom, 844);
    final padding = tester
        .widget<SliverPadding>(
          find
              .descendant(
                of: detailsScroll,
                matching: find.byType(SliverPadding),
              )
              .first,
        )
        .padding
        .resolve(TextDirection.ltr);
    expect(padding.bottom, 34 + tester.element(detailsScroll).spacing.xxl);
    expect(find.byTooltip('Refresh transaction'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Details exposes available data, copy, and explorer actions', (
    tester,
  ) async {
    final harness = await _harness(
      preferenceValues: const {'aster.settings.v1.bitcoin_unit': 'sats'},
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
    final amountRow = find.ancestor(
      of: find.text('Amount'),
      matching: find.byType(TransactionDetailRow),
    );
    expect(
      find.descendant(of: amountRow, matching: find.byType(AmountText)),
      findsOneWidget,
    );
    final confirmationsRow = find.ancestor(
      of: find.text('Confirmations'),
      matching: find.byType(TransactionDetailRow),
    );
    expect(
      find.descendant(of: confirmationsRow, matching: find.byType(NumericText)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: confirmationsRow, matching: find.byType(AmountText)),
      findsNothing,
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
      asymmetricViewport: true,
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
    expect(
      tester
          .getCenter(find.text('This transaction is no longer available.'))
          .dx,
      951 / 2,
    );
    expect(tester.getCenter(retry).dx, 951 / 2);
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
      asymmetricViewport: true,
    );
    await _pumpUntil(
      tester,
      () => find.text(failure.userMessage).evaluate().isNotEmpty,
    );

    final message = find.bySemanticsLabel(failure.userMessage);
    expect(tester.getCenter(find.text(failure.userMessage)).dx, 951 / 2);
    expect(tester.getCenter(find.text('Retry')).dx, 951 / 2);
    expect(tester.getSemantics(message).flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Retry'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('Activity refresh retries a failed Settings dependency first', (
    tester,
  ) async {
    const failure = AppFailure(
      code: 'settings_temporarily_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Settings are temporarily unavailable.',
      retryable: true,
    );
    final harness = await _harness();
    addTearDown(() => _disposeHarness(tester, harness));
    final settingsViewModel = _InitiallyFailingSettingsViewModel(failure);
    _configurePhone(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
          overrides: [
            settingsViewModelProvider.overrideWith(() => settingsViewModel),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AsterFeedbackScope(
              haptics: harness.haptics,
              toasts: harness.toasts,
              child: const TransactionListScreen(
                assetKind: WalletAssetKind.bitcoin,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(failure.userMessage).evaluate().isNotEmpty,
    );
    expect(
      harness.engine.calls.where((call) => call == 'activity'),
      hasLength(1),
    );
    expect(harness.engine.calls, isNot(contains('sync')));

    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await indicator.onRefresh();
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.byType(TransactionItem).evaluate().length == 2,
    );

    expect(harness.engine.calls, isNot(contains('sync')));
    expect(
      harness.engine.calls.where((call) => call == 'activity'),
      hasLength(1),
    );
    expect(settingsViewModel.retryAttempts, 1);
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
    expect(
      find.byKey(const ValueKey('activity-loading-balance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-loading-heading')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'activity-loading-item-',
            ),
      ),
      findsNWidgets(4),
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

void _useAsymmetricViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(951, 669);
  tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
  addTearDown(tester.view.reset);
}

final class _InitiallyFailingSettingsViewModel extends SettingsViewModel {
  _InitiallyFailingSettingsViewModel(this.failure);

  final AppFailure failure;
  var retryAttempts = 0;

  @override
  Future<SettingsState> build() {
    return Future<SettingsState>.error(
      AppFailureException(failure),
      StackTrace.current,
    );
  }

  @override
  Future<void> retry() async {
    retryAttempts += 1;
    state = AsyncData(
      SettingsState(
        snapshot: SettingsSnapshot(
          preferences: AppPreferences.defaults,
          currencies: [
            FiatCurrency(
              name: 'United States Dollar',
              symbol: r'$',
              code: 'USD',
              countryCode: 'US',
            ),
          ],
          regions: [Region(name: 'United States', code: 'US')],
        ),
      ),
    );
  }
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
  ProviderContainer? container,
  bool asymmetricViewport = false,
}) {
  if (asymmetricViewport) {
    _useAsymmetricViewport(tester);
  } else {
    _configurePhone(tester);
  }
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container ?? harness.container,
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

final class _PendingClipboard implements ClipboardService {
  final result = Completer<AppResult<void>>();
  var writes = 0;

  @override
  Future<AppResult<String?>> readText() async => const AppResult.success(null);

  @override
  Future<AppResult<void>> writeText(String text) {
    writes += 1;
    return result.future;
  }
}

final class _PendingExternalUris implements ExternalUriService {
  var result = Completer<AppResult<void>>();
  var opens = 0;

  @override
  Future<AppResult<void>> open(Uri uri) {
    opens += 1;
    return result.future;
  }
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
