import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/screens/screens.dart';
import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

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

  for (final (label, open, viewport, contentLeft, contentRight) in [
    ('Duo cover', false, const Size(466, 678), 0.0, 382.0),
    ('open Duo landscape', true, const Size(951, 669), 155.5, 795.5),
    ('narrow Duo landscape', true, const Size(700, 500), 30.0, 616.0),
  ]) {
    testWidgets('$label Swap clears only overlapping sheet insets', (
      tester,
    ) async {
      const channel = EventChannel('com.aster.wallet/cover_navigation');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, events) => events.success({
            'width': viewport.width,
            'height': viewport.height,
            if (open) 'inner': true,
          }),
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
      await _pump(tester, harness, viewport: viewport, openDuoLandscape: open);
      final action = find.widgetWithText(CustomButton, 'Coming soon');
      await _pumpUntil(tester, () => action.evaluate().isNotEmpty);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(CustomScrollView)).bottom,
        closeTo(viewport.height, 0.5),
      );
      expect(
        tester.getRect(action).bottom,
        closeTo(viewport.height - 34 - 16, 0.5),
      );

      final bitcoin = find.text('Bitcoin · On-chain');
      await tester.ensureVisible(bitcoin);
      await tester.pumpAndSettle();
      await tester.tap(bitcoin);
      await tester.pumpAndSettle();
      final sheet = find.byType(AssetSelectorSheet);
      final sheetBounds = tester.getRect(sheet);
      expect(sheetBounds.width, closeTo(open ? 640 : 466, 0.5));
      expect(sheetBounds.center.dx, closeTo(viewport.width / 2, 0.5));
      final header = find.descendant(
        of: sheet,
        matching: find.byType(AsterSheetHeader),
      );
      final options = find.descendant(
        of: sheet,
        matching: find.byType(ListView),
      );
      for (final content in [header, options]) {
        final bounds = tester.getRect(content);
        expect(bounds.left, closeTo(contentLeft, 0.5));
        expect(bounds.right, closeTo(contentRight, 0.5));
      }
      final firstIcon = find
          .descendant(of: options, matching: find.byType(WalletAssetIcon))
          .first;
      final selection = find.descendant(
        of: options,
        matching: find.byIcon(Icons.check),
      );
      expect(tester.getRect(firstIcon).left, closeTo(contentLeft + 20, 0.5));
      expect(tester.getRect(selection).right, closeTo(contentRight - 20, 0.5));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

Future<void> _pump(
  WidgetTester tester,
  PaymentFlowTestHarness harness, {
  TextScaler? textScaler,
  Size viewport = const Size(390, 844),
  bool openDuoLandscape = false,
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
            child: openDuoLandscape
                ? AsterDuoLandscapeScope(child: child!)
                : child!,
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
