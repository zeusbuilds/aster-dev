import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('import lowercases input and moves page from word four', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());

    final first = find.byKey(const ValueKey('recovery-word-1'));
    await tester.enterText(first, 'ABANDON1');
    await tester.pump();
    expect(tester.widget<TextField>(first).controller!.text, 'abandon');
    final firstFieldSemantics = tester
        .getSemantics(find.bySemanticsLabel('Recovery word 1'))
        .getSemanticsData();
    expect(firstFieldSemantics.hint, 'valid word');
    expect(firstFieldSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(firstFieldSemantics.hasAction(ui.SemanticsAction.setText), isTrue);
    expect(
      find.bySemanticsLabel(RegExp(r'^Recovery word \d+$')),
      findsNWidgets(4),
    );

    for (var index = 1; index < 4; index += 1) {
      await tester.enterText(
        find.byKey(ValueKey('recovery-word-${index + 1}')),
        'abandon',
      );
    }
    final fourth = find.byKey(const ValueKey('recovery-word-4'));
    expect(tester.widget<TextField>(fourth).focusNode!.hasPrimaryFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1));

    final fifth = find.byKey(const ValueKey('recovery-word-5'));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Recovery phrase page')).value,
      '2 of 3',
    );
    expect(tester.widget<TextField>(fifth).focusNode!.hasPrimaryFocus, isTrue);
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('create shows 1-6 and 7-12 and uses the secure copy service', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('6.'), findsOneWidget);
    expect(find.text('7.'), findsOneWidget);
    expect(find.text('12.'), findsOneWidget);
    expect(find.text('abandon'), findsNWidgets(11));
    expect(find.text('about'), findsOneWidget);

    final copy = find.text('Copy recovery phrase');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(harness.clipboardText, validTestMnemonic);
    expect(harness.toasts.messages.single.title, 'Recovery phrase copied');
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
    await _disposeHarness(tester, harness);
  });

  testWidgets('import distributes a normalized 12-word phrase paste', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());

    await tester.enterText(
      find.byKey(const ValueKey('recovery-word-1')),
      validTestMnemonic.toUpperCase(),
    );
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1));

    final twelfth = find.byKey(const ValueKey('recovery-word-12'));
    expect(tester.widget<TextField>(twelfth).controller?.text, 'about');
    expect(
      tester.widget<TextField>(twelfth).textInputAction,
      TextInputAction.done,
    );
    expect(
      tester.widget<TextField>(twelfth).focusNode?.hasPrimaryFocus,
      isTrue,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Recovery phrase page')).value,
      '3 of 3',
    );
    expect(find.text('Recovery phrase is valid'), findsOneWidget);
  });

  testWidgets('import keeps loading on the current screen until commit', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    for (var index = 0; index < validTestMnemonicWords.length; index += 1) {
      notifier.updateWord(index, validTestMnemonicWords[index]);
    }
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    final nativeGate = Completer<void>();
    harness.engine.initializeGate = nativeGate;
    final continueButton = find.bySemanticsLabel('Continue');
    await tester.ensureVisible(continueButton);

    await tester.tap(continueButton);
    await tester.pump();

    expect(find.text('Import with recovery phrase'), findsOneWidget);
    expect(tester.getSemantics(continueButton).value, 'Loading');
    expect(harness.haptics.intents, isEmpty);
    await _pumpUntil(tester, () => harness.engine.calls.contains('initialize'));

    nativeGate.complete();
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(walletViewModelProvider).value?.activeWallet !=
          null,
    );
    expect(harness.haptics.intents, contains(HapticIntent.success));
  });

  for (final scenario in const [
    (name: 'compact scaled phone', size: Size(320, 568), textScale: 2.0),
    (name: 'large phone', size: Size(430, 932), textScale: 1.0),
  ]) {
    testWidgets('onboarding supports ${scenario.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await OnboardingTestHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));
      await harness.container.read(walletViewModelProvider.future);
      final textScaler = TextScaler.linear(scenario.textScale);

      await _pumpScreen(
        tester,
        harness,
        const OnboardingWelcomeScreen(),
        textScaler: textScaler,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      expect(find.bySemanticsLabel('Create Wallet'), findsOneWidget);
      expect(find.bySemanticsLabel('Import Wallet'), findsOneWidget);

      await _pumpScreen(
        tester,
        harness,
        const OnboardingCreateWalletScreen(),
        textScaler: textScaler,
      );
      expect(find.text('12.'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      expect(find.bySemanticsLabel('Continue'), findsOneWidget);

      await _pumpScreen(
        tester,
        harness,
        const OnboardingImportWalletScreen(),
        textScaler: textScaler,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('recovery-word-1'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester, meetsGuideline(textContrastGuideline));
    });
  }
}

Future<void> _disposeHarness(
  WidgetTester tester,
  OnboardingTestHarness harness,
) async {
  final disposal = harness.dispose();
  for (var frame = 0; frame < 3; frame += 1) {
    await tester.pump();
  }
  await disposal;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var frame = 0; frame < 100; frame += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for widget state.');
}

Future<void> _pumpScreen(
  WidgetTester tester,
  OnboardingTestHarness harness,
  Widget screen, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: harness.toasts,
          child: screen,
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 10; frame += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
