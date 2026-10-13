import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/screens/screens.dart';
import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/presentation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Swap exposes four typed targets and no fabricated execution', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create(
      services: const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: RgbAssetConfiguration(
          contractId: 'deployment-owned-contract',
          precision: 6,
        ),
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, textScaler: const TextScaler.linear(2));
    await _pumpUntil(
      tester,
      () => find
          .text('Swap execution is not available in this build.')
          .evaluate()
          .isNotEmpty,
    );

    expect(find.text('SideSwap service fee'), findsNothing);
    expect(find.text('Conversion rate'), findsNothing);
    expect(find.text(r'$160,000'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(CustomButton, 'Swap unavailable'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final action = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Swap unavailable'),
    );
    expect(action.enabled, isFalse);

    await tester.ensureVisible(find.text('Bitcoin · On-chain'));
    await tester.tap(find.text('Bitcoin · On-chain'));
    await tester.pumpAndSettle();
    expect(find.byType(AssetSelectorSheet), findsOneWidget);
    expect(find.text('Select payment option'), findsOneWidget);
    expect(find.text('Select Network'), findsNothing);
    final selected = tester.getSemantics(
      find.bySemanticsLabel('Bitcoin, On-chain'),
    );
    expect(selected.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(
      selected.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      false,
    );
    expect(find.text('Bitcoin'), findsNWidgets(2));
    // At 2x text the last row is lazy-built only after scrolling.
    expect(find.text('Coming later'), findsOneWidget);
    final lightning = tester.getSemantics(
      find.bySemanticsLabel('Bitcoin, Lightning'),
    );
    expect(lightning.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(
      lightning.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.text('Coming later').first);
    await tester.pumpAndSettle();

    expect(find.byType(AssetSelectorSheet), findsOneWidget);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('USDT, RGB Lightning'),
      120,
      scrollable: find.descendant(
        of: find.byType(AssetSelectorSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('USDT, RGB Lightning'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('Swap loading exposes one truthful live node', (tester) async {
    final gate = Completer<List<WalletPaymentCapability>>();
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        walletPaymentCapabilitiesProvider.overrideWith((ref) => gate.future),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AsterFeedbackScope(
          haptics: haptics,
          toasts: RecordingToastPresentationService(),
          child: MaterialApp(theme: AppTheme.light(), home: const SwapScreen()),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Loading swap options'), findsOneWidget);
    expect(find.bySemanticsLabel('Bitcoin, On-chain'), findsNothing);
  });

  testWidgets('Swap failure is live and preserves an eligible retry', (
    tester,
  ) async {
    const failure = AppFailure(
      code: 'swap_options_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Swap options are temporarily unavailable.',
      retryable: true,
    );
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletPaymentCapabilitiesProvider.overrideWith(
          (ref) => Future.error(
            const AppFailureException(failure),
            StackTrace.empty,
          ),
        ),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AsterFeedbackScope(
          haptics: haptics,
          toasts: RecordingToastPresentationService(),
          child: MaterialApp(theme: AppTheme.light(), home: const SwapScreen()),
        ),
      ),
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
}

Future<void> _pump(
  WidgetTester tester,
  PaymentFlowTestHarness harness, {
  TextScaler? textScaler,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) {
          final content = AsterFeedbackScope(
            haptics: harness.haptics,
            toasts: harness.toasts,
            child: child!,
          );
          return textScaler == null
              ? content
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: content,
                );
        },
        home: const SwapScreen(),
      ),
    ),
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var frame = 0; frame < 200; frame += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for Swap UI state.');
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
