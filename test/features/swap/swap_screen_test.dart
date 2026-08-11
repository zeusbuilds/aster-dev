import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/screens/screens.dart';
import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

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
    final action = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Swap unavailable'),
    );
    expect(action.enabled, isFalse);

    await tester.tap(find.text('Bitcoin · On-chain'));
    await tester.pumpAndSettle();
    expect(find.byType(AssetSelectorSheet), findsOneWidget);
    expect(find.text('Bitcoin'), findsNWidgets(2));
    expect(find.text('USDT'), findsNWidgets(2));
    await tester.tap(find.text('Lightning').first);
    await tester.pumpAndSettle();

    expect(find.text('Bitcoin · Lightning'), findsOneWidget);
    expect(harness.haptics.intents, [
      HapticIntent.lightImpact,
      HapticIntent.selection,
    ]);
    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
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
