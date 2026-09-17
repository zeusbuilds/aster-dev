import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/presentation/models/models.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesh/mesh.dart';

import '../../support/onboarding_harness.dart';
import '../../support/presentation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    // Contrast must sample the shipped glyphs, not the widget-test Ahem blocks.
    // Large Ahem rectangles distort color clustering over the brand mesh.
    for (final (family, path) in [
      ('DM Sans', 'assets/fonts/DMSans-Variable.ttf'),
      ('Public Sans', 'assets/fonts/PublicSans-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('onboarding status is live without swallowing recovery actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AsterFeedbackScope(
          haptics: const NoopHapticFeedbackService(),
          toasts: ToastController(),
          child: Scaffold(
            body: OnboardingStatusPanel.failure(
              title: 'Wallet setup paused',
              message: 'Wallet services are temporarily unavailable.',
              primaryLabel: 'Retry',
              onPrimary: () {},
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    final status = find.bySemanticsLabel(
      'Wallet setup paused. Wallet services are temporarily unavailable.',
    );
    expect(status, findsOneWidget);
    expect(tester.getSemantics(status).flagsCollection.isLiveRegion, isTrue);
    for (final action in const ['Retry', 'Back']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(action))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
    }
  });

  testWidgets('import lowercases input and moves page from word four', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());

    expect(find.text('Aster'), findsOneWidget);
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
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _expectOnboardingContrast(tester);
  });

  testWidgets('import hydrates a retained validated phrase on remount', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final subscription = harness.container.listen(
      importWalletViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    harness.container
        .read(importWalletViewModelProvider.notifier)
        .updateWords(0, validTestMnemonicWords);
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canContinue ==
          true,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    for (var index = 1; index <= 4; index++) {
      final field = tester.widget<TextField>(
        find.byKey(ValueKey('recovery-word-$index')),
      );
      expect(field.controller!.text, validTestMnemonicWords[index - 1]);
    }
    expect(
      harness.container.read(importWalletViewModelProvider).value!.canContinue,
      isTrue,
    );
  });

  testWidgets('import fields follow copy while only the footer tracks height', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final description = find.text(
      'Enter your 12-word recovery phrase in order.',
    );
    final first = find.byKey(const ValueKey('recovery-word-1'));
    final warning = find.text('Never share your recovery phrase');
    final spacing = tester.element(first).spacing;
    final fieldTop = tester.getTopLeft(first);
    final footerTop = tester.getTopLeft(warning);
    expect(fieldTop.dx, tester.getTopLeft(description).dx);
    expect(
      fieldTop.dy - tester.getBottomLeft(description).dy,
      closeTo(spacing.xxxl, 0.01),
    );
    expect(
      footerTop.dy - tester.getBottomLeft(find.byType(PageView)).dy,
      greaterThan(spacing.sectionGap),
    );

    tester.view.physicalSize += const Offset(0, 120);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first), fieldTop);
    expect(tester.getTopLeft(warning).dy, closeTo(footerTop.dy + 120, 0.01));
  });

  testWidgets('onboarding text action stays plain and blocks loading taps', (
    tester,
  ) async {
    var taps = 0;
    Future<void> pumpAction({required bool loading}) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OnboardingTextAction(
            label: 'Copy recovery phrase',
            icon: Icons.copy,
            loading: loading,
            hapticIntent: null,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await pumpAction(loading: false);
    final button = find.byType(OnboardingTextAction);
    final size = tester.getSize(button);
    expect(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ButtonStyleButton ||
              widget is InkResponse ||
              widget is Material,
        ),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 3);
    final node = tester.getSemantics(button);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    expect(taps, 4);

    await pumpAction(loading: true);
    expect(tester.getSize(button), size);
    expect(
      tester
          .getSemantics(button)
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    expect(
      tester.getSemantics(find.byType(OnboardingTextAction)).value,
      'Loading',
    );
    await tester.tap(button);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 4);
  });

  testWidgets('create shows 1-6 and 7-12 and uses the secure copy service', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());

    expect(find.text('Aster'), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
      AppTheme.light().colorScheme.surface,
    );
    expect(
      tester
          .widget<Text>(find.text('Your 12-word recovery phrase'))
          .style!
          .color,
      AppTheme.light().colorScheme.onSurface,
    );
    expect(
      find.text('Keep this offline and never share it with anyone.'),
      findsOneWidget,
    );

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('6.'), findsOneWidget);
    expect(find.text('7.'), findsOneWidget);
    expect(find.text('12.'), findsOneWidget);
    expect(find.text('••••••'), findsNWidgets(12));
    expect(find.text('abandon'), findsNothing);
    expect(find.text('about'), findsNothing);
    expect(find.bySemanticsLabel('Recovery word 1, hidden'), findsOneWidget);
    expect(find.bySemanticsLabel('1. abandon'), findsNothing);

    final reveal = find.widgetWithText(CustomButton, 'Reveal phrase');
    expect(reveal, findsOneWidget);
    await tester.ensureVisible(reveal);
    await tester.tap(reveal);
    await tester.pump();

    expect(find.text('abandon'), findsNWidgets(11));
    expect(find.text('about'), findsOneWidget);
    expect(find.bySemanticsLabel('1. abandon'), findsOneWidget);
    expect(find.widgetWithText(CustomButton, 'Hide phrase'), findsOneWidget);

    await tester.tap(find.widgetWithText(CustomButton, 'Hide phrase'));
    await tester.pump();
    expect(find.text('abandon'), findsNothing);
    expect(find.bySemanticsLabel('Recovery word 1, hidden'), findsOneWidget);
    await tester.tap(find.widgetWithText(CustomButton, 'Reveal phrase'));
    await tester.pump();

    final copy = find.text('Copy recovery phrase');
    expect(
      find.widgetWithText(CustomButton, 'Copy recovery phrase'),
      findsNothing,
    );
    expect(
      find.widgetWithText(OnboardingTextAction, 'Copy recovery phrase'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OnboardingTextAction>(
            find.widgetWithText(OnboardingTextAction, 'Copy recovery phrase'),
          )
          .size,
      OnboardingTextActionSize.compact,
    );
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(harness.clipboardText, validTestMnemonic);
    expect(harness.toasts.messages.single.title, 'Recovery phrase copied');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('abandon'), findsNothing);
    expect(find.bySemanticsLabel('Recovery word 1, hidden'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _expectOnboardingContrast(tester);
    await _disposeHarness(tester, harness);
  });

  for (final retryable in [true, false]) {
    testWidgets(
      'create ${retryable ? 'shows' : 'hides'} retry for its typed failure',
      (tester) async {
        final harness = await OnboardingTestHarness.create(
          generationError: AppFailureException(
            AppFailure(
              code: retryable
                  ? 'mnemonic_generation_unavailable'
                  : 'mnemonic_generation_disabled',
              kind: retryable
                  ? AppFailureKind.unavailable
                  : AppFailureKind.configuration,
              userMessage: retryable
                  ? 'Recovery phrase generation is temporarily unavailable.'
                  : 'Recovery phrase generation is not configured.',
              retryable: retryable,
            ),
          ),
        );
        addTearDown(() => _disposeHarness(tester, harness));

        await _pumpScreen(
          tester,
          harness,
          const OnboardingCreateWalletScreen(),
        );

        expect(
          find.text(
            retryable
                ? 'Recovery phrase generation is temporarily unavailable.'
                : 'Recovery phrase generation is not configured.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), retryable ? findsOneWidget : findsNothing);
        expect(find.text('Back'), findsOneWidget);
      },
    );
  }

  for (final retryable in [true, false]) {
    testWidgets(
      'import ${retryable ? 'shows' : 'hides'} retry for its typed failure',
      (tester) async {
        final failure = AppFailure(
          code: retryable
              ? 'word_list_temporarily_unavailable'
              : 'word_list_invalid',
          kind: retryable
              ? AppFailureKind.unavailable
              : AppFailureKind.configuration,
          userMessage: retryable
              ? 'Recovery phrase words are temporarily unavailable.'
              : 'Recovery phrase words are not configured.',
          retryable: retryable,
        );

        await tester.pumpWidget(
          ProviderScope(
            retry: applicationProviderRetryPolicy,
            overrides: [
              importWalletViewModelProvider.overrideWith(
                () => _FailingImportWalletViewModel(failure),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: OnboardingShell(
                child: const OnboardingImportWalletScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text(failure.userMessage), findsOneWidget);
        expect(find.text('Retry'), retryable ? findsOneWidget : findsNothing);
        expect(find.text('Back'), findsOneWidget);
      },
    );
  }

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
              ?.canContinue ==
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

  testWidgets('import exposes and completes a retryable phrase check', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create(
      validationError: const AppFailureException(
        AppFailure(
          code: 'checksum_service_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'Phrase checking is temporarily unavailable.',
          retryable: true,
        ),
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());

    await tester.enterText(
      find.byKey(const ValueKey('recovery-word-1')),
      validTestMnemonic,
    );
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.failure
              ?.code ==
          'checksum_service_unavailable',
    );
    await tester.pump();
    expect(find.text('Retry phrase check'), findsOneWidget);

    harness.keyGenerator.validationError = null;
    await tester.tap(find.text('Retry phrase check'));
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canContinue ==
          true,
    );
    await tester.pump();

    expect(find.text('Recovery phrase is valid'), findsOneWidget);
    expect(find.text('Retry phrase check'), findsNothing);
  });

  testWidgets('import presents provisioning failure as Continue retry', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    notifier.updateWords(0, validTestMnemonicWords);
    notifier.updateWalletName('Imported wallet');
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Wallet setup is temporarily unavailable.',
        retryable: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    await tester.pump();

    expect(
      find.text('Wallet setup is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Retry phrase check'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('import freezes phrase input after an unknown setup outcome', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    notifier.updateWords(0, validTestMnemonicWords);
    notifier.updateWalletName('Imported wallet');
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_outcome_unknown',
        kind: AppFailureKind.timeout,
        userMessage: 'Restart before continuing wallet setup.',
        retryable: false,
        outcomeUnknown: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    await tester.pump();

    expect(
      find.text('Restart before continuing wallet setup.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('recovery-word-1')))
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );
  });

  testWidgets('create keeps Copy but disables unknown-outcome provisioning', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    final notifier = harness.container.read(
      createWalletViewModelProvider.notifier,
    );
    _completeCreateWalletSetup(harness, name: 'Daily wallet');
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_outcome_unknown',
        kind: AppFailureKind.timeout,
        userMessage: 'Restart before continuing wallet setup.',
        retryable: false,
        outcomeUnknown: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    await tester.pump();

    expect(
      find.text('Restart before continuing wallet setup.'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Copy recovery phrase'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );
  });

  testWidgets('import freezes navigation after known retained resources', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    notifier.updateWords(0, validTestMnemonicWords);
    notifier.updateWalletName('Imported wallet');
    await _pumpUntil(
      tester,
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_reconciliation_required',
        kind: AppFailureKind.storage,
        userMessage: 'Restart before continuing wallet setup.',
        retryable: false,
        requiresReconciliation: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('recovery-word-1')))
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );
  });

  testWidgets('create preserves copy but freezes known retained navigation', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    final notifier = harness.container.read(
      createWalletViewModelProvider.notifier,
    );
    _completeCreateWalletSetup(harness, name: 'Daily wallet');
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_reconciliation_required',
        kind: AppFailureKind.storage,
        userMessage: 'Restart before continuing wallet setup.',
        retryable: false,
        requiresReconciliation: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    await tester.pump();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Copy recovery phrase'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );
  });

  testWidgets('create quiz verifies fixed words and advances only on success', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    final initial = harness.container
        .read(createWalletViewModelProvider)
        .requireValue;

    await _pumpScreen(tester, harness, const CreateWalletQuizScreen());
    expect(find.text('Aster'), findsNothing);
    expect(find.text('Check your backup'), findsOneWidget);
    expect(
      find.text('Choose each word from the recovery phrase you wrote down.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.widgetWithText(OnboardingTextAction, 'Back'), findsNothing);
    expect(find.byType(AsterDivider), findsNothing);
    expect(find.byType(Squircle), findsNWidgets(4));

    for (var index = 0; index < initial.questions.length; index += 1) {
      final question = initial.questions[index];
      expect(
        find.text(
          'Word ${question.wordNumber} of ${CreateWalletState.wordCount}',
        ),
        findsOneWidget,
      );
      if (index == 0) {
        final incorrect = question.options.firstWhere(
          (option) => option != question.expectedWord,
        );
        await tester.tap(find.text(incorrect));
        await tester.pump();
        expect(
          find.text('That is not word 3. Check your backup and try again.'),
          findsOneWidget,
        );
        expect(
          harness.container
              .read(createWalletViewModelProvider)
              .requireValue
              .confirmedQuestionCount,
          0,
        );
      }
      await tester.tap(find.text(question.expectedWord));
      await tester.pump();
    }

    expect(find.text('Recovery phrase confirmed'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isTrue,
    );
    expect(harness.haptics.intents.first, HapticIntent.error);
    expect(
      harness.haptics.intents.where(
        (intent) => intent == HapticIntent.selection,
      ),
      hasLength(CreateWalletState.quizWordNumbers.length),
    );
  });

  testWidgets('wallet naming requires a valid user-owned name', (tester) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    final notifier = harness.container.read(
      createWalletViewModelProvider.notifier,
    );
    final generated = harness.container
        .read(createWalletViewModelProvider)
        .requireValue;
    for (final question in generated.questions) {
      expect(notifier.selectQuizOption(question.expectedWord), isTrue);
    }

    await _pumpScreen(tester, harness, const WalletNameScreen.create());
    expect(find.text('Aster'), findsNothing);
    expect(find.text('Name your wallet'), findsOneWidget);
    expect(
      find.text('Choose a name that will make this wallet easy to recognize.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.text('Wallet name'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Wallet name')), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('wallet-name-field')),
    );
    expect(nameField.decoration?.labelText, isNull);
    expect(nameField.decoration?.hintText, 'My wallet');

    final submit = find.widgetWithText(CustomButton, 'Create Wallet');
    expect(
      tester.getSemantics(submit).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('wallet-name-field')),
      '   ',
    );
    await tester.pump();
    expect(
      find.text('Use a visible name with up to 64 characters.'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(submit).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('wallet-name-field')),
      'Travel wallet',
    );
    await tester.pump();
    expect(
      tester.getSemantics(submit).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    expect(
      harness.container
          .read(createWalletViewModelProvider)
          .requireValue
          .normalizedWalletName,
      'Travel wallet',
    );
  });

  for (final source in _walletNameTestSources) {
    testWidgets(
      '${source.label} keeps loading on the name screen and blocks stale navigation',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        await harness.container.read(walletViewModelProvider.future);
        await _prepareWalletNameSource(tester, harness, source);
        addTearDown(_keepWalletNameSourceAlive(harness, source));

        final nativeGate = Completer<void>();
        harness.engine.provisionGate = nativeGate;
        final route = await _pumpOnboardingRoute(
          tester,
          harness,
          path: source.testPath,
          screen: source.screen,
        );
        addTearDown(route.router.dispose);

        final submitFinder = find.widgetWithText(
          CustomButton,
          source.submitLabel,
        );
        final submit = tester.widget<CustomButton>(submitFinder);
        final backFinder = find.byType(AsterIconButton);
        final back = tester.widget<AsterIconButton>(backFinder);
        final navigation = AsterNavigationScope.of(tester.element(backFinder));
        final hapticCountBeforeSubmit = harness.haptics.intents.length;
        expect(route.router.canPop(), isTrue);

        submit.onTap!();
        expect(navigation.inFlight, isTrue);
        back.onPressed!();
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(find.text('Name your wallet'), findsOneWidget);
        expect(tester.getSemantics(submitFinder).value, 'Loading');
        expect(route.router.canPop(), isTrue);
        expect(harness.haptics.intents, hasLength(hapticCountBeforeSubmit));
        await _pumpUntil(
          tester,
          () => harness.engine.calls.contains('provision'),
        );

        nativeGate.complete();
        await _pumpUntil(
          tester,
          () =>
              harness.container
                  .read(walletViewModelProvider)
                  .value
                  ?.activeWallet
                  ?.name ==
              source.walletName,
        );
        await _pumpUntil(
          tester,
          () => find.text('Home destination').evaluate().isNotEmpty,
        );
        expect(harness.haptics.intents.last, HapticIntent.success);
      },
    );
  }

  testWidgets('welcome renders the authored mesh without backdrop capture', (
    tester,
  ) async {
    var compositionReadyCount = 0;
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1290, 2796);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OnboardingWelcomeMeshBackground(
            onCompositionReady: () => compositionReadyCount += 1,
          ),
        ),
      ),
    );
    expect(compositionReadyCount, 0);
    await tester.pumpAndSettle();

    final mesh = find.byType(OnboardingWelcomeMeshBackground);
    expect(
      find.descendant(of: mesh, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
    expect(
      find.descendant(of: mesh, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: mesh, matching: find.byType(AsterNoiseTexture)),
      findsOneWidget,
    );
    final gradient = tester.widget<OMeshGradient>(
      find.descendant(of: mesh, matching: find.byType(OMeshGradient)),
    );
    expect(gradient.mesh.width, 4);
    expect(gradient.mesh.height, 4);
    expect(gradient.mesh.vertices, hasLength(16));
    expect(gradient.mesh.colors, hasLength(16));
    final noiseImage = tester.widget<Image>(
      find.descendant(of: mesh, matching: find.byType(Image)),
    );
    expect(noiseImage.image, isA<ResizeImage>());
    expect((noiseImage.image as ResizeImage).width, 1600);
    expect(compositionReadyCount, 1);
    await tester.pump();
    expect(compositionReadyCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome icon tiles avoid redundant backdrop reads', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const OnboardingShell(child: OnboardingWelcomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Aster'), findsOneWidget);
    final grid = find.byType(OnboardingWelcomeIconGrid);
    final filters = find.descendant(
      of: grid,
      matching: find.byType(BackdropFilter),
    );
    expect(filters, findsNothing);
  });

  testWidgets('welcome owns one navigation command across both actions', (
    tester,
  ) async {
    final haptics = RecordingHapticFeedbackService();
    final router = GoRouter(
      initialLocation: RoutePaths.onboardingWelcome,
      routes: [
        GoRoute(
          path: RoutePaths.onboardingWelcome,
          builder: (context, state) => const OnboardingWelcomeScreen(),
        ),
        GoRoute(
          path: RoutePaths.onboardingCreateWallet,
          builder: (context, state) => const Text('Create destination'),
        ),
        GoRoute(
          path: RoutePaths.onboardingImportWallet,
          builder: (context, state) => const Text('Import destination'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => AsterFeedbackScope(
          haptics: haptics,
          toasts: RecordingToastPresentationService(),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();

    final create = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Create Wallet'),
    );
    final import = tester.widget<OnboardingTextAction>(
      find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
    );
    create.onTap!();
    import.onPressed();
    await tester.pumpAndSettle();

    expect(find.text('Create destination'), findsOneWidget);
    expect(find.text('Import destination'), findsNothing);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('onboarding snapshot bounds retained texture density', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 4;
    tester.view.physicalSize = const Size(1560, 3376);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const OnboardingShell(child: SizedBox.expand()),
      ),
    );

    final snapshotMediaQuery = tester
        .widgetList<MediaQuery>(find.byType(MediaQuery))
        .singleWhere((mediaQuery) => mediaQuery.child is SnapshotWidget);
    expect(snapshotMediaQuery.data.devicePixelRatio, 3);
    final snapshot = tester.widget<SnapshotWidget>(
      find.descendant(
        of: find.byType(OnboardingShell),
        matching: find.byType(SnapshotWidget),
      ),
    );
    expect(snapshot.controller.allowSnapshotting, isFalse);
    expect(snapshot.painter, isA<OnboardingBackgroundSnapshotPainter>());
    final snapshotPainter =
        snapshot.painter as OnboardingBackgroundSnapshotPainter;
    expect(snapshotPainter.hasPaintedSnapshot, isFalse);

    await tester.pumpAndSettle();

    expect(snapshot.controller.allowSnapshotting, isTrue);
    expect(snapshotPainter.hasPaintedSnapshot, isTrue);
    expect(snapshotPainter.physicalSize, const Size(1170, 2532));
    expect(snapshotPainter.pixelRatio, 3);
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
      await tester.scrollUntilVisible(
        find.widgetWithText(CustomButton, 'Continue'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Continue'), findsOneWidget);

      await _pumpScreen(
        tester,
        harness,
        const OnboardingImportWalletScreen(),
        textScaler: textScaler,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('recovery-word-1')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('recovery-word-1'))).height,
        greaterThanOrEqualTo(48),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await _expectOnboardingContrast(tester);
    });
  }
}

typedef _WalletNameTestSource = ({
  bool createsWallet,
  String label,
  String testPath,
  Widget screen,
  String submitLabel,
  String walletName,
});

const List<_WalletNameTestSource> _walletNameTestSources = [
  (
    createsWallet: true,
    label: 'create',
    testPath: '/test-create-wallet-name',
    screen: WalletNameScreen.create(),
    submitLabel: 'Create Wallet',
    walletName: 'Daily wallet',
  ),
  (
    createsWallet: false,
    label: 'import',
    testPath: '/test-import-wallet-name',
    screen: WalletNameScreen.import(),
    submitLabel: 'Import Wallet',
    walletName: 'Imported wallet',
  ),
];

Future<void> _prepareWalletNameSource(
  WidgetTester tester,
  OnboardingTestHarness harness,
  _WalletNameTestSource source,
) async {
  if (source.createsWallet) {
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    _completeCreateWalletSetup(harness, name: source.walletName);
    return;
  }

  await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
  final notifier = harness.container.read(
    importWalletViewModelProvider.notifier,
  );
  notifier.updateWords(0, validTestMnemonicWords);
  await _pumpUntil(
    tester,
    () =>
        harness.container
            .read(importWalletViewModelProvider)
            .value
            ?.canContinue ==
        true,
  );
  notifier.updateWalletName(source.walletName);
  expect(
    harness.container
        .read(importWalletViewModelProvider)
        .requireValue
        .canSubmit,
    isTrue,
  );
}

VoidCallback _keepWalletNameSourceAlive(
  OnboardingTestHarness harness,
  _WalletNameTestSource source,
) {
  if (source.createsWallet) {
    final subscription = harness.container.listen(
      createWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return subscription.close;
  }
  final subscription = harness.container.listen(
    importWalletViewModelProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return subscription.close;
}

void _completeCreateWalletSetup(
  OnboardingTestHarness harness, {
  required String name,
}) {
  final notifier = harness.container.read(
    createWalletViewModelProvider.notifier,
  );
  final state = harness.container
      .read(createWalletViewModelProvider)
      .requireValue;
  for (final question in state.questions) {
    expect(notifier.selectQuizOption(question.expectedWord), isTrue);
  }
  notifier.updateWalletName(name);
  expect(
    harness.container
        .read(createWalletViewModelProvider)
        .requireValue
        .canSubmit,
    isTrue,
  );
}

Future<void> _expectOnboardingContrast(WidgetTester tester) async {
  // Recovery routes have an opaque white Scaffold. Measure the actual visible
  // composition, not the welcome mesh retained behind that surface.
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

final class _FailingImportWalletViewModel extends ImportWalletViewModel {
  _FailingImportWalletViewModel(this.failure);

  final AppFailure failure;

  @override
  Future<ImportWalletState> build() {
    return Future.error(AppFailureException(failure), StackTrace.current);
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
  // These mobile screens need a phone viewport; compact/large scenarios above
  // set their own dimensions and exercise scrolling explicitly.
  if (tester.view.physicalSize == const Size(2400, 1800)) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }
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
          child: OnboardingShell(child: screen),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 10; frame += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<({GoRouter router, Future<Object?> completion})> _pumpOnboardingRoute(
  WidgetTester tester,
  OnboardingTestHarness harness, {
  required String path,
  required Widget screen,
}) async {
  final router = GoRouter(
    initialLocation: RoutePaths.onboardingWelcome,
    routes: [
      GoRoute(
        path: RoutePaths.onboardingWelcome,
        builder: (context, state) => const Text('Welcome destination'),
      ),
      GoRoute(
        path: RoutePaths.home,
        builder: (context, state) => const Text('Home destination'),
      ),
      GoRoute(path: path, builder: (context, state) => screen),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: harness.toasts,
          child: OnboardingShell(child: child!),
        ),
      ),
    ),
  );
  final completion = router.push<Object?>(path);
  await _pumpUntil(
    tester,
    () => find.byType(screen.runtimeType).evaluate().isNotEmpty,
  );
  return (router: router, completion: completion);
}
