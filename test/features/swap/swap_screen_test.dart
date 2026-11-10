import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/screens/screens.dart';
import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/presentation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Swap exposes on-chain assets and no fabricated execution', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final harness = await PaymentFlowTestHarness.create(
      services: const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: RgbAssetConfiguration(
          contractId: 'deployment-owned-contract',
          precision: 6,
          requiresEvmValidation: false,
        ),
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, textScaler: const TextScaler.linear(2));
    await _pumpUntil(
      tester,
      () => find.text('Coming soon').evaluate().isNotEmpty,
    );

    expect(
      find.text('Swap execution is not available in this build.'),
      findsNothing,
    );
    expect(find.text('Swap unavailable'), findsNothing);
    expect(find.text('SideSwap service fee'), findsNothing);
    expect(find.text('Conversion rate'), findsNothing);
    expect(find.text(r'$160,000'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(CustomButton, 'Coming soon'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final action = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Coming soon'),
    );
    expect(action.enabled, isFalse);
    expect(action.onTap, isNull);

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
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('USDT'), findsOneWidget);
    expect(find.text('Coming later'), findsNothing);
    expect(find.bySemanticsLabel('Bitcoin, Lightning'), findsNothing);
    expect(find.bySemanticsLabel('USDT, RGB Lightning'), findsNothing);
    final otherAsset = tester.getSemantics(
      find.bySemanticsLabel('USDT, RGB on-chain'),
    );
    expect(otherAsset.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(
      otherAsset.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.text('Already selected'));
    await tester.pumpAndSettle();
    expect(find.byType(AssetSelectorSheet), findsOneWidget);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
    final sheetList = find.descendant(
      of: find.byType(AssetSelectorSheet),
      matching: find.byType(ListView),
    );
    expect(tester.getRect(sheetList).bottom, 844);
    expect(
      tester
          .widget<ListView>(sheetList)
          .padding!
          .resolve(TextDirection.ltr)
          .bottom,
      greaterThan(34),
    );
    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('Duo cover Swap scrolls through the bottom inset', (
    tester,
  ) async {
    const channel = EventChannel('com.aster.wallet/cover_navigation');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (_, events) =>
            events.success({'width': 466.0, 'height': 678.0}),
      ),
    );
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    const padding = FakeViewPadding(right: 84, bottom: 34);
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final harness = await PaymentFlowTestHarness.create(
      services: testRgbServices,
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pump(tester, harness, viewport: const Size(466, 678));
    final action = find.widgetWithText(CustomButton, 'Coming soon');
    await _pumpUntil(tester, () => action.evaluate().isNotEmpty);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(CustomScrollView)).bottom,
      closeTo(678, 0.5),
    );
    expect(tester.getRect(action).bottom, closeTo(628, 0.5));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
  Size viewport = const Size(390, 844),
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
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
