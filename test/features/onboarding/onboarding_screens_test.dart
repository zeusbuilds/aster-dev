import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/features/onboarding/data/repository/repository.dart';
import 'package:aster/features/onboarding/domain/models/models.dart';
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

const _temporaryChecksumFailure = AppFailureException(
  AppFailure(
    code: 'checksum_service_unavailable',
    kind: AppFailureKind.unavailable,
    userMessage: 'Phrase checking is temporarily unavailable.',
    retryable: true,
  ),
);

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

  for (final scenario in [
    (
      label: 'recovery phrase',
      screen: const OnboardingCreateWalletScreen(),
      announcement: 'Generating your recovery phrase...',
      createsWallet: true,
    ),
    (
      label: 'recovery quiz',
      screen: const CreateWalletQuizScreen(),
      announcement: 'Preparing recovery check...',
      createsWallet: true,
    ),
    (
      label: 'import',
      screen: const OnboardingImportWalletScreen(),
      announcement: 'Preparing wallet security...',
      createsWallet: false,
    ),
    (
      label: 'initial create naming',
      screen: const WalletNameScreen.create(),
      announcement: 'Preparing wallet security...',
      createsWallet: true,
    ),
    (
      label: 'initial import naming',
      screen: const WalletNameScreen.import(),
      announcement: 'Preparing wallet security...',
      createsWallet: false,
    ),
  ]) {
    testWidgets(
      'standalone ${scenario.label} defensively loads quietly without a journey',
      (tester) async {
        final assets = await _DictionaryAssetBundle.create(succeeds: true);
        final harness = await OnboardingTestHarness.create(
          onboardingAssets: assets,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        addTearDown(assets.release);
        await _pumpScreen(tester, harness, scenario.screen);

        // Hold a real dependency open across frames: this must verify the
        // loading screen itself rather than a fast initialization that skips it.
        expect(assets.loadCount, 1);
        expect(find.byType(OnboardingStatusPanel), findsOneWidget);
        expect(find.byType(GridLoader), findsOneWidget);
        expect(find.text(scenario.announcement), findsNothing);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(scenario.announcement))
              .label,
          scenario.announcement,
        );
        expect(harness.toasts.messages, isEmpty);
        expect(harness.engine.calls, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(GridLoader), findsOneWidget);
        expect(find.text(scenario.announcement), findsNothing);

        assets.release();
        await _pumpUntil(
          tester,
          () => scenario.createsWallet
              ? harness.container.read(createWalletViewModelProvider).hasValue
              : harness.container.read(importWalletViewModelProvider).hasValue,
        );
        await tester.pump();
        expect(find.byType(GridLoader), findsNothing);
        expect(find.text(scenario.announcement), findsNothing);
        expect(harness.toasts.messages, isEmpty);
      },
    );
  }

  for (final addWallet in [false, true]) {
    testWidgets(
      '${addWallet ? 'add-wallet' : 'initial'} create keeps Welcome button loading '
      'until the real phrase and all later steps are ready',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        final generation = Completer<void>();
        harness.keyGenerator.generationGate = generation;
        addTearDown(() {
          if (!generation.isCompleted) generation.complete();
        });
        final primaryLabel = addWallet ? 'Add New Wallet' : 'Create Wallet';
        await _pumpScreen(
          tester,
          harness,
          addWallet ? const AddWalletScreen() : const OnboardingWelcomeScreen(),
          disableAnimations: true,
        );
        final create = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, primaryLabel),
        );
        final import = tester.widget<OnboardingTextAction>(
          find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
        );
        create.onTap!();
        await _pumpUntil(
          tester,
          () => harness.keyGenerator.generationCount == 1,
        );
        await tester.pump();
        final pending = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, primaryLabel),
        );
        expect(pending.loading, isTrue);
        expect(pending.enabled, isFalse);
        expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsOneWidget);
        create.onTap!();
        import.onPressed();
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(seconds: 1));
        expect(harness.keyGenerator.generationCount, 1);
        expect(find.byType(OnboardingCreateWalletScreen), findsNothing);

        generation.complete();
        await _pumpUntil(
          tester,
          () => find.byType(OnboardingCreateWalletScreen).evaluate().isNotEmpty,
        );
        await tester.pump();
        final prepared = harness.container
            .read(createWalletViewModelProvider)
            .value!;
        final phrase = tester.widget<OnboardingCreateWalletScreen>(
          find.byType(OnboardingCreateWalletScreen),
        );
        expect(find.text('Your 12-word recovery phrase'), findsOneWidget);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsNothing);
        expect(harness.keyGenerator.generationCount, 1);

        phrase.onContinue!();
        await tester.pump();
        expect(find.text('Verify seed phrase'), findsOneWidget);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsNothing);
        expect(
          harness.container.read(createWalletViewModelProvider).value,
          same(prepared),
        );
        final notifier = harness.container.read(
          createWalletViewModelProvider.notifier,
        );
        for (final question in prepared.questions) {
          notifier.selectQuizOption(
            wordNumber: question.wordNumber,
            word: question.expectedWord,
          );
        }
        await tester.pump();
        tester
            .widget<CreateWalletQuizScreen>(find.byType(CreateWalletQuizScreen))
            .onContinue!();
        await tester.pump();
        expect(find.text('Name your wallet'), findsOneWidget);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsNothing);
        expect(harness.keyGenerator.generationCount, 1);
        tester
            .widget<WalletNameScreen>(find.byType(WalletNameScreen))
            .onBack!();
        await tester.pump();
        tester
            .widget<CreateWalletQuizScreen>(find.byType(CreateWalletQuizScreen))
            .onBack!();
        await tester.pump();
        tester
            .widget<OnboardingCreateWalletScreen>(
              find.byType(OnboardingCreateWalletScreen),
            )
            .onBack!();
        await tester.pump();
        await tester.pump();
        expect(find.widgetWithText(CustomButton, primaryLabel), findsOneWidget);
        expect(
          harness.keyGenerator.generationCount,
          1,
          reason: 'Abandoning a phrase must not generate a replacement in the outgoing widget.',
        );
        phrase.onContinue!();
        await tester.pump();
        expect(
          find.byType(CreateWalletQuizScreen),
          findsNothing,
          reason: 'An abandoned phrase callback cannot enter a later step.',
        );
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, primaryLabel),
            )
            .onTap!();
        await _pumpUntil(
          tester,
          () => find.byType(OnboardingCreateWalletScreen).evaluate().isNotEmpty,
        );
        expect(harness.keyGenerator.generationCount, 2);
        expect(
          harness.container.read(createWalletViewModelProvider).value,
          isNot(same(prepared)),
        );
        expect(harness.toasts.messages, isEmpty);
        expect(harness.engine.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'phrase preparation failure belongs to Welcome and a new tap retries once',
    (tester) async {
      final harness = await OnboardingTestHarness.create(
        generationError: const AppFailureException(
          AppFailure(
            code: 'mnemonic_generation_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'Wallet preparation is temporarily unavailable.',
            retryable: true,
          ),
        ),
      );
      addTearDown(() => _disposeHarness(tester, harness));
      await _pumpScreen(
        tester,
        harness,
        const OnboardingWelcomeScreen(),
        disableAnimations: true,
      );
      tester
          .widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Create Wallet'),
          )
          .onTap!();
      await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
      await tester.pump();
      expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
      expect(find.byType(OnboardingStatusPanel), findsNothing);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Wallet setup unavailable');
      expect(
        harness.toasts.messages.single.message,
        'Wallet preparation is temporarily unavailable.',
      );
      expect(harness.keyGenerator.generationCount, 1);
      final retry = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Create Wallet'),
      );
      expect(retry.loading, isFalse);
      expect(retry.enabled, isTrue);
      harness.keyGenerator.generationError = null;
      retry.onTap!();
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingCreateWalletScreen).evaluate().isNotEmpty,
      );
      expect(find.text('Your 12-word recovery phrase'), findsOneWidget);
      expect(find.byType(OnboardingStatusPanel), findsNothing);
      expect(harness.keyGenerator.generationCount, 2);
      expect(harness.toasts.messages, hasLength(1));
    },
  );

  for (final departure in ['background', 'unmount']) {
    testWidgets(
      'phrase preparation completing after $departure cannot show a destination or late toast',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        final generation = Completer<void>();
        harness.keyGenerator.generationGate = generation;
        addTearDown(() {
          if (!generation.isCompleted) generation.complete();
        });
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await _pumpScreen(
          tester,
          harness,
          const OnboardingWelcomeScreen(),
          disableAnimations: true,
        );
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Create Wallet'),
            )
            .onTap!();
        await _pumpUntil(
          tester,
          () => harness.keyGenerator.generationCount == 1,
        );
        if (departure == 'unmount') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        generation.complete();
        for (var index = 0; index < 10; index += 1) {
          await tester.pump();
        }
        expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(harness.keyGenerator.generationCount, 1);
        expect(harness.toasts.messages, isEmpty);
        expect(harness.engine.calls, isEmpty);
        expect(tester.takeException(), isNull);
        if (departure == 'background') {
          final retry = tester.widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Create Wallet'),
          );
          expect(retry.loading, isFalse);
          retry.onTap!();
          await _pumpUntil(
            tester,
            () =>
                find.byType(OnboardingCreateWalletScreen).evaluate().isNotEmpty,
          );
          expect(harness.keyGenerator.generationCount, 2);
        }
      },
    );
  }

  for (final addWallet in [false, true]) {
    testWidgets(
      '${addWallet ? 'add-wallet' : 'initial'} import opens only the ready form '
      'then names the same validated phrase without any loading panel',
      (tester) async {
        final assets = await _DictionaryAssetBundle.create(succeeds: true);
        addTearDown(assets.release);
        final harness = await OnboardingTestHarness.create(
          onboardingAssets: assets,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        final primaryLabel = addWallet ? 'Add New Wallet' : 'Create Wallet';
        await _pumpScreen(
          tester,
          harness,
          addWallet ? const AddWalletScreen() : const OnboardingWelcomeScreen(),
          disableAnimations: true,
        );
        tester
            .widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            )
            .onPressed();
        await _pumpUntil(tester, () => assets.loadCount == 1);
        await tester.pump();
        expect(
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, primaryLabel),
              )
              .loading,
          isTrue,
        );
        expect(
          tester
              .widget<OnboardingTextAction>(
                find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
              )
              .loading,
          isFalse,
        );
        expect(find.byType(OnboardingImportWalletScreen), findsNothing);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        assets.release();
        await _pumpUntil(
          tester,
          () => find.byType(OnboardingImportWalletScreen).evaluate().isNotEmpty,
        );
        final input = tester.widget<OnboardingImportWalletScreen>(
          find.byType(OnboardingImportWalletScreen),
        );
        expect(find.byType(TextField), findsNWidgets(12));
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsNothing);
        // A stale or programmatic Continue cannot bypass checksum validation.
        input.onContinue!();
        await tester.pump();
        expect(find.byType(WalletNameScreen), findsNothing);
        harness.container
            .read(importWalletViewModelProvider.notifier)
            .updateWords(0, validTestMnemonicWords);
        await _pumpUntil(
          tester,
          () =>
              harness.container
                  .read(importWalletViewModelProvider)
                  .value
                  ?.phraseValid ==
              true,
        );
        final validated = harness.container
            .read(importWalletViewModelProvider)
            .value;
        input.onContinue!();
        await tester.pump();
        expect(find.text('Name your wallet'), findsOneWidget);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.byType(GridLoader), findsNothing);
        expect(
          harness.container.read(importWalletViewModelProvider).value,
          same(validated),
        );
        tester
            .widget<WalletNameScreen>(find.byType(WalletNameScreen))
            .onBack!();
        await tester.pump();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'abandon',
        );
        tester
            .widget<OnboardingImportWalletScreen>(
              find.byType(OnboardingImportWalletScreen),
            )
            .onBack!();
        await tester.pump();
        await tester.pump();
        input.onContinue!();
        await tester.pump();
        expect(find.byType(WalletNameScreen), findsNothing);
        tester
            .widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            )
            .onPressed();
        await _pumpUntil(
          tester,
          () => find.byType(OnboardingImportWalletScreen).evaluate().isNotEmpty,
        );
        expect(
          harness.container
              .read(importWalletViewModelProvider)
              .value!
              .words
              .every((word) => word.isEmpty),
          isTrue,
        );
        expect(assets.loadCount, 1);
        expect(harness.keyGenerator.generationCount, 0);
        expect(harness.keyGenerator.validatedMnemonics, hasLength(1));
        expect(harness.toasts.messages, isEmpty);
        expect(harness.engine.calls, isEmpty);
      },
    );
  }

  for (final addWallet in [false, true]) {
    for (final importing in [false, true]) {
      final flow =
          '${addWallet ? 'add-wallet' : 'initial'} '
          '${importing ? 'import' : 'create'}';
      testWidgets('$flow accepts native success before the root gate has '
          'rendered its resumed frame', (tester) async {
        final assets = await _DictionaryAssetBundle.create(succeeds: true);
        // An already available asset must not accidentally introduce a frame
        // that hides the native callback/render-order race.
        assets.release();
        final device = _SetupAuthentication();
        addTearDown(device.close);
        final security = SecurityController(device);
        final harness = await OnboardingTestHarness.create(
          onboardingAssets: assets,
          securityController: security,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        if (addWallet) security.updateWallet('existing-wallet');
        _configureDictionaryPreflightPhone(tester);
        final screen = addWallet
            ? const AddWalletScreen()
            : const OnboardingWelcomeScreen();
        final route = await _pumpOnboardingRoute(
          tester,
          harness,
          path: '/test-root-auth-preflight',
          screen: screen,
          securityAtRoot: true,
        );
        addTearDown(route.router.dispose);
        await tester.pumpAndSettle();
        await _tapSetupAction(
          tester,
          addWallet: addWallet,
          importing: importing,
        );
        await tester.pump();
        expect(device.prompts, 1);
        expect(assets.loadCount, 0);
        expect(harness.keyGenerator.validatedMnemonics, isEmpty);
        final welcome = tester.element(find.byType(screen.runtimeType));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(security.isObscured, isFalse);
        expect(TickerMode.valuesOf(welcome).enabled, isTrue);
        expect(find.byType(SplashScreen), findsNothing);

        // The native resumed event and result can arrive in one platform turn.
        // Deliberately do not render the SecurityGate between these callbacks.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        device.prompt.complete(DeviceAuthenticationResult.authenticated);
        expect(
          TickerMode.valuesOf(welcome).enabled,
          isTrue,
          reason: 'The source stays painted throughout owned authentication.',
        );
        await _pumpUntil(
          tester,
          () => find
              .byType(
                importing
                    ? OnboardingImportWalletScreen
                    : OnboardingCreateWalletScreen,
              )
              .evaluate()
              .isNotEmpty,
        );
        await _pumpOnboardingTransition(tester);
        expect(
          find.byType(
            importing
                ? OnboardingImportWalletScreen
                : OnboardingCreateWalletScreen,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(
            importing
                ? OnboardingCreateWalletScreen
                : OnboardingImportWalletScreen,
          ),
          findsNothing,
        );
        expect(assets.loadCount, 1);
        expect(device.prompts, 1);
        expect(device.sensitiveValues, [true]);
        expect(
          harness.keyGenerator.validatedMnemonics,
          importing ? isEmpty : hasLength(1),
        );
        expect(harness.engine.calls, isEmpty);
        expect(harness.toasts.messages, isEmpty);
      });

      for (final interruption in _SetupAuthInterruption.values) {
        testWidgets('$flow rejects ${interruption.name} before reading any '
            'dictionary or recovery data under the root gate', (tester) async {
          final assets = await _DictionaryAssetBundle.create(succeeds: true);
          assets.release();
          final device = _SetupAuthentication();
          addTearDown(device.close);
          final security = SecurityController(device);
          final harness = await OnboardingTestHarness.create(
            onboardingAssets: assets,
            securityController: security,
          );
          addTearDown(() => _disposeHarness(tester, harness));
          addTearDown(
            () => tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            ),
          );
          if (addWallet) security.updateWallet('existing-wallet');
          _configureDictionaryPreflightPhone(tester);
          final route = await _pumpOnboardingRoute(
            tester,
            harness,
            path: '/test-root-auth-interruption',
            screen: addWallet
                ? const AddWalletScreen()
                : const OnboardingWelcomeScreen(),
            securityAtRoot: true,
          );
          addTearDown(route.router.dispose);
          await tester.pumpAndSettle();
          await _tapSetupAction(
            tester,
            addWallet: addWallet,
            importing: importing,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          if (interruption == _SetupAuthInterruption.background) {
            device.background();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          } else if (interruption == _SetupAuthInterruption.walletChanged) {
            security.updateWallet('different-wallet');
          }
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          device.prompt.complete(
            interruption == _SetupAuthInterruption.cancelled
                ? DeviceAuthenticationResult.cancelled
                : DeviceAuthenticationResult.authenticated,
          );
          await tester.pump();
          await tester.pumpAndSettle();
          expect(
            find.byType(OnboardingCreateWalletScreen, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.byType(OnboardingImportWalletScreen, skipOffstage: false),
            findsNothing,
          );
          expect(assets.loadCount, 0);
          expect(harness.keyGenerator.validatedMnemonics, isEmpty);
          expect(harness.engine.calls, isEmpty);
          expect(device.sensitiveValues, isEmpty);
          expect(device.prompts, 1);
          expect(harness.toasts.messages, isEmpty);
        });
      }
    }
  }

  for (final importing in [false, true]) {
    testWidgets('${importing ? 'import' : 'create'} protects recovery content '
        'from capture without discarding its draft or redoing wallet work', (
      tester,
    ) async {
      final device = _SetupAuthentication();
      addTearDown(device.close);
      final security = SecurityController(device);
      final harness = await OnboardingTestHarness.create(
        securityController: security,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());
      if (importing) {
        tester
            .widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            )
            .onPressed();
      } else {
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Create Wallet'),
            )
            .onTap!();
      }
      await tester.pump();
      expect(device.sensitiveValues, isEmpty);
      device.prompt.complete(DeviceAuthenticationResult.authenticated);
      await _pumpUntil(
        tester,
        () => find
            .byType(
              importing
                  ? OnboardingImportWalletScreen
                  : OnboardingCreateWalletScreen,
            )
            .evaluate()
            .isNotEmpty,
      );
      await _pumpOnboardingTransition(tester);
      expect(device.sensitiveValues, [true]);
      if (importing) {
        await tester.enterText(
          find.byKey(const ValueKey('recovery-word-1')),
          'abandon',
        );
      } else {
        await tester.tap(find.widgetWithText(OnboardingTextAction, 'Reveal'));
      }
      await tester.pumpAndSettle();
      final retained = importing
          ? harness.container.read(importWalletViewModelProvider).value
          : harness.container.read(createWalletViewModelProvider).value;
      final validations = harness.keyGenerator.validatedMnemonics.length;
      device.capture(true);
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('abandon'), findsNothing);
      expect(find.byKey(const ValueKey('recovery-word-1')), findsNothing);
      device.capture(false);
      await tester.pump();
      expect(find.byType(SplashScreen), findsNothing);
      expect(
        identical(
          retained,
          importing
              ? harness.container.read(importWalletViewModelProvider).value
              : harness.container.read(createWalletViewModelProvider).value,
        ),
        isTrue,
      );
      expect(harness.keyGenerator.validatedMnemonics.length, validations);
      expect(harness.engine.calls, isEmpty);
      expect(device.prompts, 1);
      expect(harness.toasts.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(device.sensitiveValues.last, isFalse);
    });

    testWidgets(
      '${importing ? 'import' : 'create'} waits for fresh device auth '
      'without losing preflight to its own native prompt',
      (tester) async {
        final assets = await _DictionaryAssetBundle.create(succeeds: true);
        addTearDown(assets.release);
        final device = _SetupAuthentication();
        addTearDown(device.close);
        final security = SecurityController(device);
        final harness = await OnboardingTestHarness.create(
          onboardingAssets: assets,
          securityController: security,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        _configureDictionaryPreflightPhone(tester);
        final route = await _pumpOnboardingRoute(
          tester,
          harness,
          path: '/test-auth-preflight',
          screen: SecurityGate(
            controller: security,
            child: const OnboardingWelcomeScreen(),
          ),
        );
        addTearDown(route.router.dispose);
        await tester.pumpAndSettle();
        if (importing) {
          tester
              .widget<OnboardingTextAction>(
                find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
              )
              .onPressed();
        } else {
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, 'Create Wallet'),
              )
              .onTap!();
        }
        await tester.pump();
        expect(device.prompts, 1);
        expect(assets.loadCount, 0);
        expect(harness.keyGenerator.validatedMnemonics, isEmpty);
        expect(
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, 'Create Wallet'),
              )
              .loading,
          isTrue,
        );
        expect(
          tester
              .widget<OnboardingTextAction>(
                find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
              )
              .loading,
          isFalse,
        );

        security.handleLifecycle(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        security.handleLifecycle(AppLifecycleState.resumed);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        device.prompt.complete(DeviceAuthenticationResult.authenticated);
        await _pumpUntil(tester, () => assets.loadCount == 1);
        expect(harness.toasts.messages, isEmpty);
        expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
        expect(find.byType(OnboardingImportWalletScreen), findsNothing);
        assets.release();
        await _pumpUntil(
          tester,
          () => find
              .byType(
                importing
                    ? OnboardingImportWalletScreen
                    : OnboardingCreateWalletScreen,
              )
              .evaluate()
              .isNotEmpty,
        );
        await _pumpOnboardingTransition(tester);
        expect(device.prompts, 1);
        expect(assets.loadCount, 1);
        expect(harness.toasts.messages, isEmpty);
      },
    );

    testWidgets('${importing ? 'import' : 'create'} auth cancellation stays '
        'on Welcome without dictionary/phrase work or a toast', (tester) async {
      final assets = await _DictionaryAssetBundle.create(succeeds: true);
      addTearDown(assets.release);
      final device = _SetupAuthentication();
      addTearDown(device.close);
      final harness = await OnboardingTestHarness.create(
        onboardingAssets: assets,
        securityController: SecurityController(device),
      );
      addTearDown(() => _disposeHarness(tester, harness));
      await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());
      if (importing) {
        tester
            .widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            )
            .onPressed();
      } else {
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Create Wallet'),
            )
            .onTap!();
      }
      await tester.pump();
      device.prompt.complete(DeviceAuthenticationResult.cancelled);
      await _pumpUntil(
        tester,
        () => !tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Create Wallet'),
            )
            .loading,
      );
      expect(assets.loadCount, 0);
      expect(harness.engine.calls, isEmpty);
      expect(harness.keyGenerator.validatedMnemonics, isEmpty);
      expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
      expect(find.byType(OnboardingImportWalletScreen), findsNothing);
      expect(harness.toasts.messages, isEmpty);
      expect(harness.security.canAccessWallet, isTrue);
    });
  }

  for (final addWallet in [false, true]) {
    for (final importing in [false, true]) {
      for (final succeeds in [false, true]) {
        testWidgets(
          '${addWallet ? 'add-wallet' : 'initial'} ${importing ? 'import' : 'create'} dictionary preflight ${succeeds ? 'enters once' : 'fails on welcome'}',
          (tester) async {
            final assets = await _DictionaryAssetBundle.create(
              succeeds: succeeds,
            );
            addTearDown(assets.release);
            final harness = await OnboardingTestHarness.create(
              onboardingAssets: assets,
            );
            addTearDown(() => _disposeHarness(tester, harness));
            _configureDictionaryPreflightPhone(tester);
            final route = await _pumpOnboardingRoute(
              tester,
              harness,
              path: '/test-dictionary-preflight',
              screen: addWallet
                  ? const AddWalletScreen()
                  : const OnboardingWelcomeScreen(),
            );
            addTearDown(route.router.dispose);
            final primaryLabel = addWallet ? 'Add New Wallet' : 'Create Wallet';
            await _pumpUntil(
              tester,
              () => find
                  .widgetWithText(CustomButton, primaryLabel)
                  .evaluate()
                  .isNotEmpty,
            );
            final entrance = ModalRoute.of(
              tester.element(find.widgetWithText(CustomButton, primaryLabel)),
            )!;
            await tester.pump(entrance.transitionDuration);
            await tester.pump();
            final primary = tester.widget<CustomButton>(
              find.widgetWithText(CustomButton, primaryLabel),
            );
            final import = tester.widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            );
            final oldBack = addWallet
                ? tester.widget<AsterIconButton>(_dictionaryWelcomeBack())
                : null;
            if (importing) {
              import.onPressed();
            } else {
              primary.onTap!();
            }
            // Direct stale callbacks in the initiating frame must share one intent.
            primary.onTap!();
            import.onPressed();
            // Device-security preflight precedes the dictionary read. The
            // unsecured policy resolves asynchronously without a native prompt.
            await tester.pump();
            expect(
              assets.loadCount,
              1,
              reason:
                  'The first action must acquire the pending dictionary read.',
            );
            oldBack?.onPressed?.call();
            await tester.binding.handlePopRoute();
            await tester.pump();

            expect(entrance.isCurrent, isTrue);
            expect(route.router.canPop(), isTrue);
            expect(find.text('Welcome destination'), findsNothing);
            expect(assets.loadCount, 1);
            final pendingPrimary = tester.widget<CustomButton>(
              find.widgetWithText(CustomButton, primaryLabel),
            );
            expect(pendingPrimary.loading, isTrue);
            expect(pendingPrimary.enabled, isFalse);
            final pendingImport = tester.widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            );
            expect(pendingImport.label, 'Import Wallet');
            expect(pendingImport.loading, isFalse);
            expect(pendingImport.enabled, isFalse);
            if (addWallet) {
              expect(
                tester
                    .widget<AsterIconButton>(_dictionaryWelcomeBack())
                    .onPressed,
                isNull,
              );
            }
            expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
            expect(find.byType(OnboardingImportWalletScreen), findsNothing);
            expect(harness.engine.calls, isEmpty);
            expect(harness.keyGenerator.validatedMnemonics, isEmpty);
            await tester.pump(const Duration(milliseconds: 100));
            expect(assets.loadCount, 1);

            assets.release();
            await _pumpUntil(
              tester,
              () => succeeds
                  ? find
                        .byType(
                          importing
                              ? OnboardingImportWalletScreen
                              : OnboardingCreateWalletScreen,
                        )
                        .evaluate()
                        .isNotEmpty
                  : harness.toasts.messages.isNotEmpty,
            );
            await _pumpOnboardingTransition(tester);
            expect(
              assets.loadCount,
              1,
              reason:
                  'Preflight and the form must use the same cached repository.',
            );
            if (succeeds) {
              expect(
                find.byType(
                  importing
                      ? OnboardingImportWalletScreen
                      : OnboardingCreateWalletScreen,
                ),
                findsOneWidget,
              );
              expect(
                find.byType(
                  importing
                      ? OnboardingCreateWalletScreen
                      : OnboardingImportWalletScreen,
                ),
                findsNothing,
              );
              expect(harness.toasts.messages, isEmpty);
              expect(
                harness.haptics.intents.where(
                  (intent) => intent == HapticIntent.lightImpact,
                ),
                hasLength(1),
              );
            } else {
              expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
              expect(find.byType(OnboardingImportWalletScreen), findsNothing);
              expect(harness.engine.calls, isEmpty);
              expect(harness.keyGenerator.validatedMnemonics, isEmpty);
              expect(harness.toasts.messages, hasLength(1));
              expect(
                harness.toasts.messages.single.title,
                'Wallet setup unavailable',
              );
              expect(
                harness.toasts.messages.single.message,
                'Recovery phrase validation is unavailable in this build.',
              );
              expect(
                harness.toasts.messages.single.variant,
                ToastVariant.failure,
              );
              expect(
                find.text(harness.toasts.messages.single.message!),
                findsNothing,
              );
              final restored = tester.widget<CustomButton>(
                find.widgetWithText(CustomButton, primaryLabel),
              );
              expect(restored.loading, isFalse);
              expect(restored.enabled, isTrue);
              expect(
                tester
                    .widget<OnboardingTextAction>(
                      find.widgetWithText(
                        OnboardingTextAction,
                        'Import Wallet',
                      ),
                    )
                    .enabled,
                isTrue,
              );
              if (addWallet) {
                expect(
                  tester
                      .widget<AsterIconButton>(_dictionaryWelcomeBack())
                      .onPressed,
                  isNotNull,
                );
              }
            }
          },
        );
      }
    }
  }

  for (final succeeds in [false, true]) {
    testWidgets(
      'dictionary ${succeeds ? 'success' : 'failure'} after unmount cannot navigate or announce',
      (tester) async {
        final assets = await _DictionaryAssetBundle.create(succeeds: succeeds);
        addTearDown(assets.release);
        final harness = await OnboardingTestHarness.create(
          onboardingAssets: assets,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());
        tester
            .widget<OnboardingTextAction>(
              find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
            )
            .onPressed();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        assets.release();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(harness.toasts.messages, isEmpty);
        expect(harness.engine.calls, isEmpty);
        expect(harness.keyGenerator.validatedMnemonics, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'background dictionary completion restores controls without late feedback',
    (tester) async {
      final assets = await _DictionaryAssetBundle.create(succeeds: false);
      addTearDown(assets.release);
      final harness = await OnboardingTestHarness.create(
        onboardingAssets: assets,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _pumpScreen(tester, harness, const AddWalletScreen());
      tester
          .widget<OnboardingTextAction>(
            find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
          )
          .onPressed();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Add New Wallet'),
            )
            .loading,
        isTrue,
      );

      assets.release();
      await _pumpUntil(
        tester,
        () => !tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Add New Wallet'),
            )
            .loading,
      );
      expect(harness.toasts.messages, isEmpty);
      expect(find.byType(OnboardingImportWalletScreen), findsNothing);
      tester
          .widget<OnboardingTextAction>(
            find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
          )
          .onPressed();
      await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
      expect(harness.toasts.messages, hasLength(1));
      expect(assets.loadCount, 1);
      expect(harness.engine.calls, isEmpty);
    },
  );

  testWidgets(
    'a covered welcome ignores dictionary success and can retry on return',
    (tester) async {
      final assets = await _DictionaryAssetBundle.create(succeeds: true);
      addTearDown(assets.release);
      final harness = await OnboardingTestHarness.create(
        onboardingAssets: assets,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      _configureDictionaryPreflightPhone(tester);
      final route = await _pumpOnboardingRoute(
        tester,
        harness,
        path: '/test-dictionary-preflight',
        screen: const AddWalletScreen(),
      );
      addTearDown(route.router.dispose);
      tester
          .widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Add New Wallet'),
          )
          .onTap!();
      await tester.pump();
      unawaited(route.router.push<void>(RoutePaths.home));
      await tester.pump();
      assets.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Home destination'), findsOneWidget);
      expect(harness.toasts.messages, isEmpty);
      expect(harness.keyGenerator.validatedMnemonics, isEmpty);
      route.router.pop();
      await _pumpUntil(
        tester,
        () => find
            .widgetWithText(CustomButton, 'Add New Wallet')
            .evaluate()
            .isNotEmpty,
      );
      await _pumpUntil(
        tester,
        () => !tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Add New Wallet'),
            )
            .loading,
      );
      tester
          .widget<OnboardingTextAction>(
            find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
          )
          .onPressed();
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingImportWalletScreen).evaluate().isNotEmpty,
      );
      expect(assets.loadCount, 1);
      expect(harness.toasts.messages, isEmpty);
    },
  );

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

  testWidgets('import lowercases input and advances focus across its grid', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());

    expect(find.text('Aster'), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.widgetWithText(OnboardingTextAction, 'Back'), findsNothing);
    expect(find.widgetWithText(CustomButton, 'Continue'), findsOneWidget);
    final first = find.byKey(const ValueKey('recovery-word-1'));
    final twelfth = find.byKey(const ValueKey('recovery-word-12'));
    expect(
      tester.widget<TextField>(twelfth).textInputAction,
      TextInputAction.done,
    );
    await tester.tap(twelfth);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<TextField>(first).focusNode!.hasPrimaryFocus, isTrue);

    await tester.enterText(first, 'ABANDON1');
    await tester.pump();
    final firstField = tester.widget<TextField>(first);
    expect(firstField.controller!.text, 'abandon');
    expect(firstField.decoration!.filled, isFalse);
    expect(firstField.decoration!.border, InputBorder.none);
    expect(firstField.decoration!.enabledBorder, InputBorder.none);
    expect(firstField.decoration!.focusedBorder, InputBorder.none);
    expect(firstField.decoration!.disabledBorder, InputBorder.none);
    expect(firstField.decoration!.errorBorder, InputBorder.none);
    expect(firstField.decoration!.focusedErrorBorder, InputBorder.none);
    final firstFieldSemantics = tester
        .getSemantics(find.bySemanticsLabel('Recovery word 1'))
        .getSemanticsData();
    expect(firstFieldSemantics.hint, 'valid word');
    expect(firstFieldSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(firstFieldSemantics.hasAction(ui.SemanticsAction.setText), isTrue);
    expect(
      find.bySemanticsLabel(RegExp(r'^Recovery word \d+$')),
      findsNWidgets(12),
    );
    final firstTile = find.byKey(const ValueKey('recovery-word-entry-tile-1'));
    final seventhTile = find.byKey(
      const ValueKey('recovery-word-entry-tile-7'),
    );
    expect(tester.getTopLeft(firstTile).dy, tester.getTopLeft(seventhTile).dy);
    expect(
      tester.getTopLeft(firstTile).dx,
      lessThan(tester.getTopLeft(seventhTile).dx),
    );
    final firstTileRect = tester.getRect(firstTile);
    final firstFieldRect = tester.getRect(first);
    expect(
      firstTileRect.right - firstFieldRect.right,
      closeTo(tester.element(first).radii.recoveryWord, 0.01),
    );
    await tester.pump(const AsterMotion().selectionTransitionDuration);
    final themeColors = AppTheme.light().extension<AsterColors>()!;
    final firstSurface = tester.widget<Squircle>(
      find.descendant(of: firstTile, matching: find.byType(Squircle)),
    );
    expect(firstSurface.color, themeColors.successContainer);
    expect(firstSurface.borderColor, themeColors.success);
    expect(
      find.descendant(of: firstTile, matching: find.byType(Icon)),
      findsNothing,
    );
    await tester.tap(find.text('Import with recovery phrase'));
    await tester.pump();
    expect(firstField.focusNode!.hasFocus, isFalse);

    final second = find.byKey(const ValueKey('recovery-word-2'));
    await tester.enterText(second, 'zzzz');
    await tester.pump();
    await tester.pump(const AsterMotion().selectionTransitionDuration);
    final secondTile = find.byKey(const ValueKey('recovery-word-entry-tile-2'));
    final secondSurface = tester.widget<Squircle>(
      find.descendant(of: secondTile, matching: find.byType(Squircle)),
    );
    expect(secondSurface.color, themeColors.dangerContainer);
    expect(secondSurface.borderColor, themeColors.danger);
    expect(
      find.descendant(of: secondTile, matching: find.byType(Icon)),
      findsNothing,
    );
    await tester.tap(twelfth);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<TextField>(second).focusNode!.hasPrimaryFocus, isTrue);

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
    expect(tester.widget<TextField>(fifth).focusNode!.hasPrimaryFocus, isTrue);
    expect(find.byType(PageView), findsNothing);
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
    for (var index = 1; index <= ImportWalletState.wordCount; index++) {
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

  testWidgets('Duo cover scrolls the system inset with onboarding actions', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.aster.wallet/cover_navigation'),
      MockStreamHandler.inline(
        onListen: (_, events) =>
            events.success({'width': 466.0, 'height': 678.0}),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(466, 678);
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));

    final viewport = find.byType(CustomScrollView);
    Future<void> expectFooter(
      Finder action, {
      required double viewportBottom,
      required double actionBottom,
    }) async {
      final scrollable = find.descendant(
        of: viewport,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable.first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(viewport).dy, closeTo(viewportBottom, 0.5));
      expect(tester.getBottomLeft(action).dy, closeTo(actionBottom, 0.5));
    }

    for (final screen in [
      const OnboardingWelcomeScreen(),
      const AddWalletScreen(),
    ]) {
      await _pumpScreen(tester, harness, screen, disableAnimations: true);
      await expectFooter(
        find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
        viewportBottom: 678,
        actionBottom: 628,
      );
    }

    await _pumpScreen(
      tester,
      harness,
      const OnboardingImportWalletScreen(),
      disableAnimations: true,
    );
    final continueButton = find.widgetWithText(CustomButton, 'Continue');
    await expectFooter(continueButton, viewportBottom: 678, actionBottom: 628);

    tester.view.padding = const FakeViewPadding(right: 84);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    await expectFooter(continueButton, viewportBottom: 418, actionBottom: 402);

    tester.view.viewInsets = const FakeViewPadding();
    tester.view.physicalSize = const Size(669, 951);
    tester.view.padding = const FakeViewPadding(top: 82, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    await tester.pumpAndSettle();
    await expectFooter(continueButton, viewportBottom: 917, actionBottom: 901);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('import grid follows copy while only the action tracks height', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
    final description = find.text(
      'Enter your 12-word recovery phrase in order. '
      'Never share it with anyone.',
    );
    final firstTile = find.byKey(const ValueKey('recovery-word-entry-tile-1'));
    final continueButton = find.widgetWithText(CustomButton, 'Continue');
    final spacing = tester.element(firstTile).spacing;
    final fieldTop = tester.getTopLeft(firstTile);
    final buttonTop = tester.getTopLeft(continueButton);
    expect(fieldTop.dx, tester.getTopLeft(description).dx);
    expect(
      fieldTop.dy - tester.getBottomLeft(description).dy,
      closeTo(spacing.xxl, 0.01),
    );
    expect(find.text('Never share your recovery phrase'), findsNothing);
    expect(find.byType(PageView), findsNothing);

    tester.view.physicalSize += const Offset(0, 120);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstTile), fieldTop);
    expect(
      tester.getTopLeft(continueButton).dy,
      closeTo(buttonTop.dy + 120, 0.01),
    );
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

  testWidgets('create shows 1-6 and 7-12 while keeping the phrase offline', (
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

    final reveal = find.widgetWithText(OnboardingTextAction, 'Reveal');
    final continueButton = find.widgetWithText(CustomButton, 'Continue');
    final copyAction = find.widgetWithText(
      OnboardingTextAction,
      'Copy recovery phrase',
    );
    expect(reveal, findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.widgetWithText(CustomButton, 'Reveal'), findsNothing);
    final back = find.byWidgetPredicate(
      (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
    );
    final backGlyph = find.descendant(of: back, matching: find.byType(Icon));
    final recoveryTiles = find.byType(Squircle);
    expect(recoveryTiles, findsNWidgets(12));
    expect(
      tester.getTopLeft(backGlyph).dx,
      moreOrLessEquals(tester.getTopLeft(recoveryTiles.first).dx),
    );
    expect(
      tester.getTopRight(reveal).dx,
      moreOrLessEquals(tester.getTopRight(recoveryTiles.last).dx),
    );
    expect(
      tester.getTopLeft(reveal).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(recoveryTiles.last).dy),
    );
    expect(
      tester.widget<OnboardingTextAction>(reveal).size,
      OnboardingTextActionSize.compact,
    );
    expect(tester.widget<OnboardingTextAction>(reveal).icon, isNotNull);
    final actionStyle = tester.widget<Text>(find.text('Reveal')).style!;
    final actionRole = AppTheme.light()
        .extension<AsterTypeRoles>()!
        .compactButtonLabel;
    expect(actionStyle.fontFamily, actionRole.fontFamily);
    expect(actionStyle.fontSize, actionRole.fontSize);
    expect(actionStyle.fontWeight, actionRole.fontWeight);
    expect(actionStyle.color, AppTheme.light().colorScheme.onSurface);
    expect(actionStyle.color!.a, 1);
    // The control uses opaque, approved action ink. Keep the rendered WCAG
    // guideline below as well: Linux rasterization must not hide a regression.
    final inkLuminance = actionStyle.color!.computeLuminance();
    final surfaceLuminance = AppTheme.light().colorScheme.surface
        .computeLuminance();
    final inkContrast = surfaceLuminance > inkLuminance
        ? (surfaceLuminance + 0.05) / (inkLuminance + 0.05)
        : (inkLuminance + 0.05) / (surfaceLuminance + 0.05);
    expect(inkContrast, greaterThanOrEqualTo(4.5));
    expect(continueButton, findsOneWidget);
    expect(copyAction, findsNothing);
    expect(
      tester.getTopLeft(reveal).dy,
      lessThan(tester.getTopLeft(continueButton).dy),
    );
    await tester.ensureVisible(reveal);
    await tester.tap(reveal);
    await tester.pump();

    expect(find.text('abandon'), findsNWidgets(11));
    expect(find.text('about'), findsOneWidget);
    expect(find.bySemanticsLabel('1. abandon'), findsOneWidget);
    final hide = find.widgetWithText(OnboardingTextAction, 'Hide');
    expect(hide, findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Hide')).style!.fontWeight,
      actionRole.fontWeight,
    );
    expect(find.text('Hide'), findsOneWidget);
    expect(find.widgetWithText(CustomButton, 'Hide'), findsNothing);
    await _expectOnboardingContrast(tester);

    await tester.tap(hide);
    await tester.pump();
    expect(find.text('abandon'), findsNothing);
    expect(find.bySemanticsLabel('Recovery word 1, hidden'), findsOneWidget);
    await tester.tap(reveal);
    await tester.pump();

    expect(find.text('Copy recovery phrase'), findsNothing);
    expect(harness.clipboardText, isEmpty);

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
    var continued = false;
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await harness.container.read(walletViewModelProvider.future);
    final validationGate = Completer<void>();
    harness.keyGenerator.validationGate = validationGate;
    await _pumpScreen(
      tester,
      harness,
      OnboardingImportWalletScreen(onContinue: () => continued = true),
    );

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
              ?.checksumStatus ==
          MnemonicChecksumStatus.checking,
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
    expect(find.byType(OnboardingEditableRecoveryPhraseGrid), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Recovery phrase is valid'), findsNothing);
    expect(find.text('Checking recovery phrase...'), findsNothing);
    expect(
      tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
          .loading,
      isTrue,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(continued, isFalse);
    validationGate.complete();
    await _pumpUntil(tester, () => continued);
    expect(continued, isTrue);
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets(
    'import announces each failed phrase check once and retries through Continue',
    (tester) async {
      var continued = false;
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
      await _pumpScreen(
        tester,
        harness,
        OnboardingImportWalletScreen(onContinue: () => continued = true),
      );

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
      expect(harness.toasts.messages, hasLength(1));
      final message = harness.toasts.messages.single;
      expect(message.title, 'Phrase could not be checked');
      expect(message.message, 'Phrase checking is temporarily unavailable.');
      expect(message.variant, ToastVariant.failure);
      expect(
        '${message.title} ${message.message}',
        isNot(contains(validTestMnemonic)),
      );
      expect(
        find.text('Phrase checking is temporarily unavailable.'),
        findsNothing,
      );
      expect(find.text('Retry phrase check'), findsNothing);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Continue'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isTrue,
      );

      final retained = harness.container.listen(
        importWalletViewModelProvider,
        (_, _) {},
      );
      addTearDown(retained.close);
      await _pumpScreen(
        tester,
        harness,
        OnboardingImportWalletScreen(onContinue: () => continued = true),
        textScaler: const TextScaler.linear(1.1),
      );
      expect(harness.toasts.messages, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpScreen(
        tester,
        harness,
        OnboardingImportWalletScreen(onContinue: () => continued = true),
      );
      expect(harness.toasts.messages, hasLength(1));

      await tester.tap(find.bySemanticsLabel('Continue'));
      await _pumpUntil(tester, () => harness.toasts.messages.length == 2);
      expect(harness.toasts.messages.last.title, message.title);
      expect(harness.toasts.messages.last.message, message.message);
      expect(continued, isFalse);

      harness.keyGenerator.validationError = null;
      await tester.tap(find.bySemanticsLabel('Continue'));
      await _pumpUntil(tester, () => continued);
      await tester.pump();

      expect(continued, isTrue);
      expect(find.text('Recovery phrase is valid'), findsNothing);
      expect(find.text('Retry phrase check'), findsNothing);
      expect(harness.toasts.messages, hasLength(2));
      expect(harness.engine.calls, isEmpty);
    },
  );

  for (final invalidChecksum in [true, false]) {
    testWidgets(
      'import keeps ${invalidChecksum ? 'an invalid checksum' : 'a terminal check failure'} silent',
      (tester) async {
        final harness = await OnboardingTestHarness.create(
          validationError: AppFailureException(
            AppFailure(
              code: invalidChecksum
                  ? 'native_phrase_invalid'
                  : 'checksum_service_unavailable',
              kind: invalidChecksum
                  ? AppFailureKind.validation
                  : AppFailureKind.unavailable,
              userMessage: 'Phrase checking did not complete.',
              retryable: false,
            ),
          ),
        );
        addTearDown(() => _disposeHarness(tester, harness));
        await _pumpScreen(
          tester,
          harness,
          const OnboardingImportWalletScreen(),
        );

        await tester.enterText(
          find.byKey(const ValueKey('recovery-word-1')),
          validTestMnemonic,
        );
        await _pumpUntil(
          tester,
          () => harness.keyGenerator.validationCompletionCount == 1,
        );
        await tester.pump();
        final state = harness.container
            .read(importWalletViewModelProvider)
            .requireValue;
        expect(state.allWordsKnown, isTrue);
        expect(
          state.checksumStatus,
          invalidChecksum
              ? MnemonicChecksumStatus.invalid
              : MnemonicChecksumStatus.incomplete,
        );
        expect(state.canContinue, isFalse);
        expect(harness.toasts.messages, isEmpty);
        expect(find.text('Phrase checking did not complete.'), findsNothing);
        expect(
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, 'Continue'),
              )
              .enabled,
          isFalse,
        );
      },
    );
  }

  for (final unmount in [true, false]) {
    testWidgets(
      'import ignores a failed check after ${unmount ? 'unmounting' : 'editing the phrase'}',
      (tester) async {
        final harness = await OnboardingTestHarness.create(
          validationError: _temporaryChecksumFailure,
        );
        addTearDown(() => _disposeHarness(tester, harness));
        final retained = harness.container.listen(
          importWalletViewModelProvider,
          (_, _) {},
        );
        addTearDown(retained.close);
        final validationGate = Completer<void>();
        addTearDown(() {
          if (!validationGate.isCompleted) validationGate.complete();
        });
        harness.keyGenerator.validationGate = validationGate;
        await _pumpScreen(
          tester,
          harness,
          const OnboardingImportWalletScreen(),
        );

        await tester.enterText(
          find.byKey(const ValueKey('recovery-word-1')),
          validTestMnemonic,
        );
        await _pumpUntil(
          tester,
          () => harness.keyGenerator.validatedMnemonics.isNotEmpty,
        );
        if (unmount) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await tester.enterText(
            find.byKey(const ValueKey('recovery-word-12')),
            '',
          );
        }
        validationGate.complete();
        await _pumpUntil(
          tester,
          () => harness.keyGenerator.validationCompletionCount == 1,
        );
        await tester.pump();

        expect(harness.toasts.messages, isEmpty);
        expect(tester.takeException(), isNull);
        if (!unmount) {
          final state = harness.container
              .read(importWalletViewModelProvider)
              .requireValue;
          expect(state.allWordsKnown, isFalse);
          expect(state.failure, isNull);
          expect(state.canContinue, isFalse);
        }
      },
    );
  }

  testWidgets(
    'import discards a queued check warning when the phrase changes before display',
    (tester) async {
      final harness = await OnboardingTestHarness.create(
        validationError: _temporaryChecksumFailure,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      await _pumpScreen(tester, harness, const OnboardingImportWalletScreen());
      final notifier = harness.container.read(
        importWalletViewModelProvider.notifier,
      );

      notifier.updateWords(0, validTestMnemonicWords);
      await notifier.waitForChecksumValidation();
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .failure,
        isNotNull,
      );
      notifier.updateWord(11, '');
      await tester.pump();

      expect(harness.toasts.messages, isEmpty);
      expect(
        find.text('Phrase checking is temporarily unavailable.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a temporary phrase-check failure toast automatically disappears',
    (tester) async {
      final harness = await OnboardingTestHarness.create(
        validationError: _temporaryChecksumFailure,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      final toasts = harness.container.read(toastControllerProvider.notifier);
      await _pumpScreen(
        tester,
        harness,
        AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: toasts,
          child: const ToastHost(child: OnboardingImportWalletScreen()),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('recovery-word-1')),
        validTestMnemonic,
      );
      await _pumpUntil(
        tester,
        () => find.byType(CustomToast).evaluate().isNotEmpty,
      );
      final message = harness.container.read(toastControllerProvider).current!;
      expect(find.text('Phrase could not be checked'), findsOneWidget);
      expect(find.text(message.message!), findsOneWidget);
      expect(
        '${message.title} ${message.message}',
        isNot(contains(validTestMnemonic)),
      );
      expect(
        find.descendant(
          of: find.byType(OnboardingImportWalletScreen),
          matching: find.text(message.message!),
        ),
        findsNothing,
      );

      await tester.pump(message.duration + const Duration(milliseconds: 1));
      await tester.pump(
        const AsterMotion().toastTransitionDuration +
            const Duration(milliseconds: 1),
      );
      expect(harness.container.read(toastControllerProvider).current, isNull);
      expect(harness.container.read(toastControllerProvider).pending, isEmpty);
      expect(find.byType(CustomToast), findsNothing);
      expect(find.text(message.message!), findsNothing);
    },
  );

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

    expect(find.text('Wallet setup is temporarily unavailable.'), findsNothing);
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

    expect(find.text('Restart before continuing wallet setup.'), findsNothing);
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

  testWidgets(
    'create keeps phrase offline and disables unknown-outcome provisioning',
    (tester) async {
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
        findsNothing,
      );
      expect(harness.toasts.messages, isEmpty);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Continue'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );
      expect(find.bySemanticsLabel('Copy recovery phrase'), findsNothing);
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
    },
  );

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

  testWidgets(
    'create keeps phrase offline and freezes known retained navigation',
    (tester) async {
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
      expect(find.bySemanticsLabel('Copy recovery phrase'), findsNothing);
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
    },
  );

  testWidgets('create quiz verifies words 3, 7, and 11 in equal option rows', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingCreateWalletScreen());
    final initial = harness.container
        .read(createWalletViewModelProvider)
        .requireValue;
    final recoveryTile = tester.widget<Squircle>(find.byType(Squircle).first);
    final recoveryTileHeight = tester
        .getSize(find.byType(Squircle).first)
        .height;

    await _pumpScreen(tester, harness, const CreateWalletQuizScreen());
    expect(find.text('Aster'), findsNothing);
    expect(find.text('Verify seed phrase'), findsOneWidget);
    expect(
      find.text('Choose each word from the recovery phrase you wrote down.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.widgetWithText(OnboardingTextAction, 'Back'), findsNothing);
    expect(find.byType(AsterDivider), findsNothing);
    expect(find.byType(Squircle), findsNWidgets(9));

    for (var index = 0; index < initial.questions.length; index += 1) {
      final question = initial.questions[index];
      expect(find.text('Word ${question.wordNumber}'), findsOneWidget);
      final optionFinders = [
        for (final word in question.options)
          find.byKey(ValueKey('quiz-option-${question.wordNumber}-$word')),
      ];
      final firstSurface = find.byKey(
        ValueKey(
          'quiz-option-surface-${question.wordNumber}-${question.options.first}',
        ),
      );
      final quizTile = tester.widget<Squircle>(firstSurface);
      expect(tester.getSize(firstSurface).height, recoveryTileHeight);
      expect(quizTile.borderRadius, recoveryTile.borderRadius);
      final firstSize = tester.getSize(optionFinders.first);
      final firstCenter = tester.getCenter(optionFinders.first);
      for (final optionFinder in optionFinders.skip(1)) {
        expect(tester.getSize(optionFinder).width, firstSize.width);
        expect(tester.getCenter(optionFinder).dy, firstCenter.dy);
      }
      if (index == 0) {
        final incorrect = question.options.firstWhere(
          (option) => option != question.expectedWord,
        );
        final incorrectOption = find.byKey(
          ValueKey('quiz-option-${question.wordNumber}-$incorrect'),
        );
        await tester.tap(incorrectOption);
        await tester.pump(const AsterMotion().selectionTransitionDuration);
        expect(tester.getSemantics(incorrectOption).value, 'Incorrect');
        expect(
          harness.container
              .read(createWalletViewModelProvider)
              .requireValue
              .confirmedQuestionCount,
          0,
        );
      }
      final expectedOption = find.byKey(
        ValueKey('quiz-option-${question.wordNumber}-${question.expectedWord}'),
      );
      await tester.tap(expectedOption);
      await tester.pump(const AsterMotion().selectionTransitionDuration);
      expect(tester.getSemantics(expectedOption).value, 'Correct');
    }

    expect(
      harness.container
          .read(createWalletViewModelProvider)
          .requireValue
          .quizComplete,
      isTrue,
    );
    expect(find.text('Word 3'), findsOneWidget);
    expect(find.text('Word 7'), findsOneWidget);
    expect(find.text('Word 11'), findsOneWidget);
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
      expect(
        notifier.selectQuizOption(
          wordNumber: question.wordNumber,
          word: question.expectedWord,
        ),
        isTrue,
      );
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
    expect(
      nameField.decoration?.focusedBorder,
      nameField.decoration?.enabledBorder,
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    await tester.tap(find.text('Name your wallet'));
    await tester.pump();
    expect(editable.focusNode.hasFocus, isFalse);

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
      '${source.label} retains the name button while committed navigation completes',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        await harness.container.read(walletViewModelProvider.future);
        await _prepareWalletNameSource(tester, harness, source);
        addTearDown(_keepWalletNameSourceAlive(harness, source));
        final nativeGate = Completer<void>();
        addTearDown(() {
          if (!nativeGate.isCompleted) nativeGate.complete();
        });
        harness.engine.provisionGate = nativeGate;
        var completions = 0;
        // Hold the completed route on screen, as it remains while a Home
        // transition paints. This exposes the entire committed-state frame
        // instead of letting a fast test router hide an intermediate loader.
        final screen = source.createsWallet
            ? WalletNameScreen.create(onCompleted: () => completions += 1)
            : WalletNameScreen.import(onCompleted: () => completions += 1);
        await _pumpScreen(tester, harness, screen);
        final submitFinder = find.widgetWithText(
          CustomButton,
          source.submitLabel,
        );
        tester.widget<CustomButton>(submitFinder).onTap!();
        await _pumpUntil(
          tester,
          () => harness.engine.calls.contains('provision'),
        );
        expect(tester.widget<CustomButton>(submitFinder).loading, isTrue);
        expect(find.byType(OnboardingStatusPanel), findsNothing);

        nativeGate.complete();
        await _pumpUntil(tester, () => completions == 1);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Name your wallet'), findsOneWidget);
        expect(find.byType(OnboardingStatusPanel), findsNothing);
        expect(find.text('Finishing wallet setup...'), findsNothing);
        final button = tester.widget<CustomButton>(submitFinder);
        expect(button.loading, isTrue);
        expect(button.enabled, isFalse);
        final nameField = tester.widget<TextField>(
          find.byKey(const ValueKey('wallet-name-field')),
        );
        expect(nameField.controller!.text, source.walletName);
        expect(nameField.enabled, isFalse);
        expect(
          tester
              .widget<PopScope<dynamic>>(
                find.byWidgetPredicate((widget) => widget is PopScope),
              )
              .canPop,
          isFalse,
        );
        expect(
          harness.container
              .read(walletViewModelProvider)
              .requireValue
              .activeWallet
              ?.name,
          source.walletName,
        );
        // Preserve immediate secret erasure; only the non-secret field text
        // stays visible while the outgoing route is retained for animation.
        if (source.createsWallet) {
          final completed = harness.container
              .read(createWalletViewModelProvider)
              .requireValue;
          expect(completed.completed, isTrue);
          expect(completed.words, isEmpty);
          expect(completed.questions, isEmpty);
        } else {
          final completed = harness.container
              .read(importWalletViewModelProvider)
              .requireValue;
          expect(completed.completed, isTrue);
          expect(completed.words.every((word) => word.isEmpty), isTrue);
        }
        expect(completions, 1);
        expect(harness.toasts.messages, isEmpty);
      },
    );

    testWidgets(
      '${source.label} reports a naming failure once without retaining visible copy',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        await _prepareWalletNameSource(tester, harness, source);
        addTearDown(_keepWalletNameSourceAlive(harness, source));
        harness.engine.provisionError = const AppFailureException(
          AppFailure(
            code: 'wallet_setup_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'Wallet setup is temporarily unavailable.',
            retryable: true,
          ),
        );
        await _pumpScreen(tester, harness, source.screen);

        final submit = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, source.submitLabel),
        );
        submit.onTap!();
        submit.onTap!();
        await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);

        expect(harness.toasts.messages, hasLength(1));
        final message = harness.toasts.messages.single;
        expect(
          message.title,
          source.createsWallet
              ? 'Wallet could not be created'
              : 'Wallet could not be imported',
        );
        expect(message.message, 'Wallet setup is temporarily unavailable.');
        expect(message.variant, ToastVariant.failure);
        expect(
          '${message.title} ${message.message}',
          isNot(contains(validTestMnemonic)),
        );
        expect(find.text(message.message!), findsNothing);
        expect(
          harness.engine.calls.where((call) => call == 'provision'),
          hasLength(1),
        );
        expect(
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, source.submitLabel),
              )
              .enabled,
          isTrue,
        );

        await _pumpScreen(
          tester,
          harness,
          source.screen,
          textScaler: const TextScaler.linear(1.1),
        );
        expect(harness.toasts.messages, hasLength(1));
        expect(find.text(message.message!), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpScreen(tester, harness, source.screen);
        expect(harness.toasts.messages, hasLength(1));
        expect(find.text(message.message!), findsNothing);

        if (source.createsWallet) {
          await _pumpScreen(
            tester,
            harness,
            const OnboardingCreateWalletScreen(),
          );
          expect(find.byType(OnboardingRecoveryPhraseGrid), findsOneWidget);
          expect(
            harness.container
                .read(createWalletViewModelProvider)
                .requireValue
                .failure,
            isNotNull,
          );
          expect(find.text(message.message!), findsNothing);
          expect(harness.toasts.messages, hasLength(1));
        }
      },
    );

    testWidgets(
      '${source.label} does not announce a naming failure after unmounting',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        await _prepareWalletNameSource(tester, harness, source);
        addTearDown(_keepWalletNameSourceAlive(harness, source));
        final nativeGate = Completer<void>();
        addTearDown(() {
          if (!nativeGate.isCompleted) nativeGate.complete();
        });
        harness.engine
          ..provisionGate = nativeGate
          ..provisionError = const AppFailureException(
            AppFailure(
              code: 'wallet_setup_unavailable',
              kind: AppFailureKind.unavailable,
              userMessage: 'Wallet setup is temporarily unavailable.',
              retryable: true,
            ),
          );
        await _pumpScreen(tester, harness, source.screen);

        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, source.submitLabel),
            )
            .onTap!();
        await _pumpUntil(
          tester,
          () => harness.engine.calls.contains('provision'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        nativeGate.complete();
        await _pumpUntil(
          tester,
          () => _walletNameFailure(harness, source) != null,
        );
        await tester.pump();

        expect(harness.toasts.messages, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${source.label} announces uncertain setup once while keeping naming locked',
      (tester) async {
        final harness = await OnboardingTestHarness.create();
        addTearDown(() => _disposeHarness(tester, harness));
        await _prepareWalletNameSource(tester, harness, source);
        addTearDown(_keepWalletNameSourceAlive(harness, source));
        harness.engine.provisionError = const AppFailureException(
          AppFailure(
            code: 'wallet_setup_outcome_unknown',
            kind: AppFailureKind.timeout,
            userMessage: 'Restart before continuing wallet setup.',
            retryable: false,
            outcomeUnknown: true,
          ),
        );
        await _pumpScreen(tester, harness, source.screen);

        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, source.submitLabel),
            )
            .onTap!();
        await _pumpUntil(tester, () => harness.toasts.messages.isNotEmpty);
        await tester.pump();

        final failure = _walletNameFailure(harness, source)!;
        expect(failure.requiresReconciliation, isTrue);
        expect(harness.toasts.messages, hasLength(1));
        expect(harness.toasts.messages.single.message, failure.userMessage);
        expect(find.text(failure.userMessage), findsNothing);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('wallet-name-field')),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<CustomButton>(
                find.widgetWithText(CustomButton, source.submitLabel),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Back'))
              .flagsCollection
              .isEnabled,
          ui.Tristate.isFalse,
        );
        expect(
          tester
              .widget<PopScope<dynamic>>(
                find.byWidgetPredicate((widget) => widget is PopScope),
              )
              .canPop,
          isFalse,
        );
      },
    );

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
        expect(harness.toasts.messages, isEmpty);
      },
    );
  }

  testWidgets(
    'a naming failure toast appears and then automatically disappears',
    (tester) async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));
      final source = _walletNameTestSources.first;
      await _prepareWalletNameSource(tester, harness, source);
      addTearDown(_keepWalletNameSourceAlive(harness, source));
      harness.engine.provisionError = const AppFailureException(
        AppFailure(
          code: 'wallet_setup_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'Wallet setup is temporarily unavailable.',
          retryable: true,
        ),
      );
      final toasts = harness.container.read(toastControllerProvider.notifier);
      await _pumpScreen(
        tester,
        harness,
        AsterFeedbackScope(
          haptics: harness.haptics,
          toasts: toasts,
          child: const ToastHost(child: WalletNameScreen.create()),
        ),
      );

      tester
          .widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Create Wallet'),
          )
          .onTap!();
      await _pumpUntil(
        tester,
        () => find.byType(CustomToast).evaluate().isNotEmpty,
      );
      final message = harness.container.read(toastControllerProvider).current!;
      expect(find.text('Wallet could not be created'), findsOneWidget);
      expect(find.text(message.message!), findsOneWidget);
      expect(
        '${message.title} ${message.message}',
        isNot(contains(validTestMnemonic)),
      );
      expect(
        find.descendant(
          of: find.byType(WalletNameScreen),
          matching: find.text(message.message!),
        ),
        findsNothing,
      );

      await tester.pump(message.duration + const Duration(milliseconds: 1));
      await tester.pump(
        const AsterMotion().toastTransitionDuration +
            const Duration(milliseconds: 1),
      );
      expect(harness.container.read(toastControllerProvider).current, isNull);
      expect(harness.container.read(toastControllerProvider).pending, isEmpty);
      expect(find.byType(CustomToast), findsNothing);
      expect(find.text(message.message!), findsNothing);
      expect(find.text('Name your wallet'), findsOneWidget);
    },
  );

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
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingShell(child: OnboardingWelcomeScreen()),
        ),
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

  testWidgets('welcome exits in a staged handoff before recovery enters', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());
    expect(
      find.text('One wallet for Bitcoin, USDT and RGB assets.'),
      findsOneWidget,
    );
    expect(find.textContaining('Lightning'), findsNothing);
    final createSubscription = harness.container.listen(
      createWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(createSubscription.close);
    await harness.container.read(createWalletViewModelProvider.future);
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
    await _pumpSetupActionHandoff(tester);
    expect(find.byType(OnboardingImportWalletScreen), findsNothing);

    const motion = AsterMotion();
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 1);
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 0,
      expectedOffset: motion.contentTransitionVerticalOffset,
    );
    expect(_choreographyItemOpacity(tester, _journeyChromeMotionId), 0);
    expect(
      _choreographyItemVerticalOffset(tester, _journeyChromeMotionId),
      motion.contentTransitionVerticalOffset,
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.15),
    );
    final actionsAtFirstStagger = _welcomeItemOpacity(
      tester,
      'welcome-actions-motion',
    );
    final messageAtFirstStagger = _welcomeItemOpacity(
      tester,
      'welcome-message-motion',
    );
    expect(actionsAtFirstStagger, inExclusiveRange(0, 1));
    expect(messageAtFirstStagger, inExclusiveRange(0, 1));
    expect(actionsAtFirstStagger, lessThan(messageAtFirstStagger));
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 1);
    expect(
      _welcomeItemVerticalOffset(tester, 'welcome-actions-motion'),
      inExclusiveRange(0, motion.contentTransitionVerticalOffset),
    );
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 0,
      expectedOffset: motion.contentTransitionVerticalOffset,
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.1),
    );
    final messageAtSecondStagger = _welcomeItemOpacity(
      tester,
      'welcome-message-motion',
    );
    final gridAtSecondStagger = _welcomeItemOpacity(
      tester,
      'welcome-grid-motion',
    );
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);
    expect(messageAtSecondStagger, inExclusiveRange(0, 1));
    expect(gridAtSecondStagger, inExclusiveRange(0, 1));
    expect(messageAtSecondStagger, lessThan(gridAtSecondStagger));
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 1);
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 0,
      expectedOffset: motion.contentTransitionVerticalOffset,
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.25),
    );
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 0);
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 0,
      expectedOffset: motion.contentTransitionVerticalOffset,
    );
    expect(_choreographyItemOpacity(tester, _journeyChromeMotionId), 0);

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.1),
    );
    expect(
      _choreographyItemOpacity(tester, _journeyChromeMotionId),
      inExclusiveRange(0, 1),
    );
    expect(
      _choreographyItemVerticalOffset(tester, _journeyChromeMotionId),
      inExclusiveRange(0, motion.contentTransitionVerticalOffset),
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.15),
    );
    expect(_choreographyItemOpacity(tester, _journeyChromeMotionId), 1);
    expect(_choreographyItemVerticalOffset(tester, _journeyChromeMotionId), 0);
    final recoveryCopy = _choreographyItemOpacity(
      tester,
      _createRecoveryMotionIds[0],
    );
    final recoveryPhrase = _choreographyItemOpacity(
      tester,
      _createRecoveryMotionIds[1],
    );
    expect(recoveryCopy, inExclusiveRange(0, 1));
    expect(recoveryPhrase, inExclusiveRange(0, 1));
    expect(recoveryCopy, greaterThan(recoveryPhrase));
    expect(_choreographyItemOpacity(tester, _createRecoveryMotionIds[2]), 0);
    expect(
      _choreographyItemVerticalOffset(tester, _createRecoveryMotionIds[0]),
      inExclusiveRange(0, motion.contentTransitionVerticalOffset),
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.25),
    );
    await _pumpUntil(
      tester,
      () => find.text('Your 12-word recovery phrase').evaluate().isNotEmpty,
    );

    expect(find.byType(OnboardingCreateWalletScreen), findsOneWidget);
    expect(find.byType(OnboardingImportWalletScreen), findsNothing);
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 1,
      expectedOffset: 0,
    );
    expect(find.byType(OnboardingWelcomeMeshBackground), findsOneWidget);
    final createScaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(OnboardingCreateWalletScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(
      createScaffold.backgroundColor,
      AppTheme.light().extension<AsterColors>()!.transparentSurface,
    );
    expect(
      tester
          .widget<Text>(find.text('Your 12-word recovery phrase'))
          .style!
          .color,
      AppTheme.light().extension<AsterColors>()!.onBrandArt,
    );
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('retained chrome animates the create progress rail in place', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());

    tester
        .widget<CustomButton>(
          find.widgetWithText(CustomButton, 'Create Wallet'),
        )
        .onTap!();
    await _pumpOnboardingTransition(tester);

    final backButton = find.byWidgetPredicate(
      (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
    );
    const chromeKey = ValueKey('wallet-setup-journey-chrome');
    const firstSegmentKey = ValueKey('onboarding-step-indicator-0');
    const secondSegmentKey = ValueKey('onboarding-step-indicator-1');
    final metrics = AppTheme.light().extension<AsterComponentMetrics>()!;

    expect(find.byKey(chromeKey), findsOneWidget);
    expect(backButton, findsOneWidget);
    expect(find.bySemanticsLabel('Wallet setup step 1 of 3'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(firstSegmentKey)).width,
      metrics.onboardingStepIndicatorActiveWidth,
    );
    expect(
      tester.getSize(find.byKey(secondSegmentKey)).width,
      metrics.onboardingStepIndicatorInactiveWidth,
    );
    expect(
      tester.widget<AnimatedContainer>(find.byKey(firstSegmentKey)).duration,
      const AsterMotion().onboardingStepIndicatorTransitionDuration,
    );

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await tester.pump();

    expect(find.byKey(chromeKey), findsOneWidget);
    expect(backButton, findsOneWidget);
    expect(
      find.byKey(ValueKey('$_journeyChromeMotionId-opacity')),
      findsNothing,
    );
    final progress = tester.widget<OnboardingStepIndicator>(
      find.byType(OnboardingStepIndicator),
    );
    expect(progress.currentStep, 1);
    expect(progress.stepCount, 3);

    await tester.pump(
      _durationFraction(
        const AsterMotion().onboardingStepIndicatorTransitionDuration,
        0.5,
      ),
    );
    final firstWidth = tester.getSize(find.byKey(firstSegmentKey)).width;
    final secondWidth = tester.getSize(find.byKey(secondSegmentKey)).width;
    expect(
      firstWidth,
      inExclusiveRange(
        metrics.onboardingStepIndicatorInactiveWidth,
        metrics.onboardingStepIndicatorActiveWidth,
      ),
    );
    expect(
      secondWidth,
      inExclusiveRange(
        metrics.onboardingStepIndicatorInactiveWidth,
        metrics.onboardingStepIndicatorActiveWidth,
      ),
    );
    expect(firstWidth, lessThan(secondWidth));

    await tester.pump(
      _durationFraction(
        const AsterMotion().onboardingStepIndicatorTransitionDuration,
        0.5,
      ),
    );
    expect(
      tester.getSize(find.byKey(firstSegmentKey)).width,
      metrics.onboardingStepIndicatorInactiveWidth,
    );
    expect(
      tester.getSize(find.byKey(secondSegmentKey)).width,
      metrics.onboardingStepIndicatorActiveWidth,
    );
  });

  testWidgets('create content animates beneath one retained progress bar', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());

    tester
        .widget<CustomButton>(
          find.widgetWithText(CustomButton, 'Create Wallet'),
        )
        .onTap!();
    await _pumpOnboardingTransition(tester);
    await _pumpUntil(
      tester,
      () => find.byType(OnboardingCreateWalletScreen).evaluate().isNotEmpty,
    );

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await tester.pump();
    await _expectOrchestratedStepHandoff(
      tester,
      outgoing: find.byType(OnboardingCreateWalletScreen),
      incoming: find.byType(CreateWalletQuizScreen),
      outgoingIds: _createRecoveryMotionIds,
      incomingIds: _createQuizMotionIds,
    );

    final notifier = harness.container.read(
      createWalletViewModelProvider.notifier,
    );
    final state = harness.container
        .read(createWalletViewModelProvider)
        .requireValue;
    for (final question in state.questions) {
      expect(
        notifier.selectQuizOption(
          wordNumber: question.wordNumber,
          word: question.expectedWord,
        ),
        isTrue,
      );
    }
    await tester.pump();

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await tester.pump();
    await _expectOrchestratedStepHandoff(
      tester,
      outgoing: find.byType(CreateWalletQuizScreen),
      incoming: find.byType(WalletNameScreen),
      outgoingIds: _createQuizMotionIds,
      incomingIds: _walletNameMotionIds,
    );

    expect(find.text('Name your wallet'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('wallet-name-field')),
      'Temporary name',
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await _expectOrchestratedStepHandoff(
      tester,
      outgoing: find.byType(WalletNameScreen),
      incoming: find.byType(CreateWalletQuizScreen),
      outgoingIds: _walletNameMotionIds,
      incomingIds: _createQuizMotionIds,
    );
    expect(
      harness.container
          .read(createWalletViewModelProvider)
          .requireValue
          .walletName,
      isEmpty,
    );

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await _pumpOnboardingTransition(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('wallet-name-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('import content animates beneath one retained progress bar', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());

    tester
        .widget<OnboardingTextAction>(
          find.widgetWithText(OnboardingTextAction, 'Import Wallet'),
        )
        .onPressed();
    await _pumpOnboardingTransition(tester);
    expect(
      tester.widget<OnboardingStepIndicator>(
        find.byType(OnboardingStepIndicator),
      ),
      isA<OnboardingStepIndicator>()
          .having((indicator) => indicator.currentStep, 'currentStep', 0)
          .having((indicator) => indicator.stepCount, 'stepCount', 2),
    );

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

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await tester.pump();
    expect(
      tester.widget<OnboardingStepIndicator>(
        find.byType(OnboardingStepIndicator),
      ),
      isA<OnboardingStepIndicator>()
          .having((indicator) => indicator.currentStep, 'currentStep', 1)
          .having((indicator) => indicator.stepCount, 'stepCount', 2),
    );
    await _expectOrchestratedStepHandoff(
      tester,
      outgoing: find.byType(OnboardingImportWalletScreen),
      incoming: find.byType(WalletNameScreen),
      outgoingIds: _importMotionIds,
      incomingIds: _walletNameMotionIds,
    );

    expect(find.text('Name your wallet'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('wallet-name-field')),
      'Temporary import',
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    await _expectOrchestratedStepHandoff(
      tester,
      outgoing: find.byType(WalletNameScreen),
      incoming: find.byType(OnboardingImportWalletScreen),
      outgoingIds: _walletNameMotionIds,
      incomingIds: _importMotionIds,
    );
    expect(
      harness.container
          .read(importWalletViewModelProvider)
          .requireValue
          .walletName,
      isEmpty,
    );

    tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Continue'))
        .onTap!();
    await _pumpOnboardingTransition(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('wallet-name-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('welcome skips choreography when reduced motion is requested', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(
      tester,
      harness,
      const OnboardingWelcomeScreen(),
      disableAnimations: true,
    );
    final createSubscription = harness.container.listen(
      createWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(createSubscription.close);
    await harness.container.read(createWalletViewModelProvider.future);

    tester
        .widget<CustomButton>(
          find.widgetWithText(CustomButton, 'Create Wallet'),
        )
        .onTap!();
    await _pumpSetupActionHandoff(tester);

    expect(find.text('Built for\nUSDT on Bitcoin'), findsNothing);
    expect(find.byType(OnboardingCreateWalletScreen), findsOneWidget);
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 1,
      expectedOffset: 0,
    );
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('returning to welcome restores its hierarchy top to bottom', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());

    tester
        .widget<CustomButton>(
          find.widgetWithText(CustomButton, 'Create Wallet'),
        )
        .onTap!();
    await _pumpOnboardingTransition(tester);
    await _pumpUntil(
      tester,
      () => find.text('Your 12-word recovery phrase').evaluate().isNotEmpty,
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();

    const motion = AsterMotion();
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 1,
      expectedOffset: 0,
    );
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);
    expect(_choreographyItemOpacity(tester, _journeyChromeMotionId), 1);
    expect(_choreographyItemVerticalOffset(tester, _journeyChromeMotionId), 0);

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.5),
    );
    _expectChoreographyVisibility(
      tester,
      _createRecoveryMotionIds,
      expected: 0,
      expectedOffset: motion.contentTransitionVerticalOffset,
    );
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);
    expect(_choreographyItemOpacity(tester, _journeyChromeMotionId), 0);
    expect(
      _choreographyItemVerticalOffset(tester, _journeyChromeMotionId),
      motion.contentTransitionVerticalOffset,
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.15),
    );
    final headerAtFirstStagger = _welcomeItemOpacity(
      tester,
      'welcome-header-motion',
    );
    final gridAtFirstStagger = _welcomeItemOpacity(
      tester,
      'welcome-grid-motion',
    );
    expect(headerAtFirstStagger, inExclusiveRange(0, 1));
    expect(gridAtFirstStagger, inExclusiveRange(0, 1));
    expect(headerAtFirstStagger, greaterThan(gridAtFirstStagger));
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 0);
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);
    expect(
      _welcomeItemVerticalOffset(tester, 'welcome-header-motion'),
      inExclusiveRange(0, motion.contentTransitionVerticalOffset),
    );

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.1),
    );
    final gridAtSecondStagger = _welcomeItemOpacity(
      tester,
      'welcome-grid-motion',
    );
    final messageAtSecondStagger = _welcomeItemOpacity(
      tester,
      'welcome-message-motion',
    );
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 1);
    expect(gridAtSecondStagger, inExclusiveRange(0, 1));
    expect(messageAtSecondStagger, inExclusiveRange(0, 1));
    expect(gridAtSecondStagger, greaterThan(messageAtSecondStagger));
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 0);

    await tester.pump(
      _durationFraction(motion.onboardingStepTransitionDuration, 0.25),
    );
    await _pumpUntil(
      tester,
      () => find.byType(OnboardingCreateWalletScreen).evaluate().isEmpty,
    );
    expect(find.byType(OnboardingCreateWalletScreen), findsNothing);
    expect(_welcomeItemOpacity(tester, 'welcome-header-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-grid-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-message-motion'), 1);
    expect(_welcomeItemOpacity(tester, 'welcome-actions-motion'), 1);
  });

  testWidgets('recovery never exposes a clipboard action or writes a phrase', (
    tester,
  ) async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await _pumpScreen(tester, harness, const OnboardingWelcomeScreen());

    await tester.tap(find.widgetWithText(CustomButton, 'Create Wallet'));
    await _pumpOnboardingTransition(tester);
    await _pumpUntil(
      tester,
      () => find.text('Your 12-word recovery phrase').evaluate().isNotEmpty,
    );
    expect(find.text('Copy recovery phrase'), findsNothing);
    expect(harness.clipboardText, isEmpty);

    await tester.tap(find.bySemanticsLabel('Back'));
    await _pumpOnboardingTransition(tester);
    await _pumpUntil(tester, () => harness.clipboardText.isEmpty);

    expect(find.text('Built for\nUSDT on Bitcoin'), findsOneWidget);
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
        tester
            .getSize(find.byKey(const ValueKey('recovery-word-entry-target-1')))
            .height,
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

AppFailure? _walletNameFailure(
  OnboardingTestHarness harness,
  _WalletNameTestSource source,
) => source.createsWallet
    ? harness.container.read(createWalletViewModelProvider).value?.failure
    : harness.container.read(importWalletViewModelProvider).value?.failure;

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
    expect(
      notifier.selectQuizOption(
        wordNumber: question.wordNumber,
        word: question.expectedWord,
      ),
      isTrue,
    );
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
  // Standalone route tests use the standard light surface; the single-route
  // coordinator separately verifies its transparent brand-art presentation.
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

const _createRecoveryMotionIds = [
  'create-recovery-copy-motion',
  'create-recovery-phrase-motion',
  'create-recovery-actions-motion',
];

const _createQuizMotionIds = [
  'create-quiz-copy-motion',
  'create-quiz-question-motion',
  'create-quiz-actions-motion',
];

const _importMotionIds = [
  'import-copy-motion',
  'import-fields-motion',
  'import-actions-motion',
];

const _walletNameMotionIds = [
  'wallet-name-copy-motion',
  'wallet-name-field-motion',
  'wallet-name-actions-motion',
];

const _journeyChromeMotionId = 'wallet-setup-journey-chrome-motion';

void _expectChoreographyVisibility(
  WidgetTester tester,
  List<String> ids, {
  required double expected,
  required double expectedOffset,
}) {
  for (final id in ids) {
    expect(_choreographyItemOpacity(tester, id), expected);
    expect(_choreographyItemVerticalOffset(tester, id), expectedOffset);
  }
}

double _choreographyItemOpacity(WidgetTester tester, String id) {
  final opacity = find.byKey(ValueKey('$id-opacity'));
  expect(opacity, findsOneWidget);
  return tester.widget<Opacity>(opacity).opacity;
}

double _choreographyItemVerticalOffset(WidgetTester tester, String id) {
  final translation = find.byKey(ValueKey('$id-transform'));
  expect(translation, findsOneWidget);
  return tester.widget<Transform>(translation).transform.getTranslation().y;
}

double _welcomeItemOpacity(WidgetTester tester, String key) {
  return _choreographyItemOpacity(tester, key);
}

double _welcomeItemVerticalOffset(WidgetTester tester, String key) {
  return _choreographyItemVerticalOffset(tester, key);
}

Duration _durationFraction(Duration duration, double fraction) {
  return Duration(microseconds: (duration.inMicroseconds * fraction).round());
}

Future<void> _expectOrchestratedStepHandoff(
  WidgetTester tester, {
  required Finder outgoing,
  required Finder incoming,
  required List<String> outgoingIds,
  required List<String> incomingIds,
}) async {
  const motion = AsterMotion();
  _expectChoreographyVisibility(
    tester,
    outgoingIds,
    expected: 1,
    expectedOffset: 0,
  );
  _expectChoreographyVisibility(
    tester,
    incomingIds,
    expected: 0,
    expectedOffset: motion.contentTransitionVerticalOffset,
  );

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.15),
  );
  final outgoingActions = _choreographyItemOpacity(tester, outgoingIds[2]);
  final outgoingContent = _choreographyItemOpacity(tester, outgoingIds[1]);
  expect(outgoingActions, inExclusiveRange(0, 1));
  expect(outgoingContent, inExclusiveRange(0, 1));
  expect(outgoingActions, lessThan(outgoingContent));
  expect(_choreographyItemOpacity(tester, outgoingIds[0]), 1);
  expect(
    _choreographyItemVerticalOffset(tester, outgoingIds[2]),
    inExclusiveRange(0, motion.contentTransitionVerticalOffset),
  );
  _expectChoreographyVisibility(
    tester,
    incomingIds,
    expected: 0,
    expectedOffset: motion.contentTransitionVerticalOffset,
  );

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.1),
  );
  expect(_choreographyItemOpacity(tester, outgoingIds[2]), 0);
  final outgoingCopy = _choreographyItemOpacity(tester, outgoingIds[0]);
  final outgoingPrimary = _choreographyItemOpacity(tester, outgoingIds[1]);
  expect(outgoingCopy, inExclusiveRange(0, 1));
  expect(outgoingPrimary, inExclusiveRange(0, 1));
  expect(outgoingCopy, greaterThan(outgoingPrimary));

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.25),
  );
  _expectChoreographyVisibility(
    tester,
    outgoingIds,
    expected: 0,
    expectedOffset: motion.contentTransitionVerticalOffset,
  );
  _expectChoreographyVisibility(
    tester,
    incomingIds,
    expected: 0,
    expectedOffset: motion.contentTransitionVerticalOffset,
  );

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.15),
  );
  final incomingCopy = _choreographyItemOpacity(tester, incomingIds[0]);
  expect(incomingCopy, inExclusiveRange(0, 1));
  expect(_choreographyItemOpacity(tester, incomingIds[1]), 0);
  expect(_choreographyItemOpacity(tester, incomingIds[2]), 0);
  expect(
    _choreographyItemVerticalOffset(tester, incomingIds[0]),
    inExclusiveRange(0, motion.contentTransitionVerticalOffset),
  );

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.1),
  );
  final incomingSecondary = _choreographyItemOpacity(tester, incomingIds[0]);
  final incomingPrimary = _choreographyItemOpacity(tester, incomingIds[1]);
  expect(incomingSecondary, inExclusiveRange(0, 1));
  expect(incomingPrimary, inExclusiveRange(0, 1));
  expect(incomingSecondary, greaterThan(incomingPrimary));
  expect(_choreographyItemOpacity(tester, incomingIds[2]), 0);

  await tester.pump(
    _durationFraction(motion.onboardingStepTransitionDuration, 0.25),
  );
  await _pumpUntil(tester, () => outgoing.evaluate().isEmpty);
  expect(incoming, findsOneWidget);
  _expectChoreographyVisibility(
    tester,
    incomingIds,
    expected: 1,
    expectedOffset: 0,
  );
}

Future<void> _pumpOnboardingTransition(WidgetTester tester) async {
  const motion = AsterMotion();
  await _pumpSetupActionHandoff(tester);
  await tester.pump(
    motion.onboardingStepTransitionDuration + const Duration(milliseconds: 20),
  );
}

Future<void> _pumpSetupActionHandoff(WidgetTester tester) async {
  // Device authentication deliberately waits for a painted foreground frame
  // before loading recovery data. Flush that asynchronous action handoff with
  // zero elapsed animation time, then measure the existing choreography from
  // its unchanged first frame.
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump();
    final welcomeActions = find.descendant(
      of: find.byKey(const ValueKey('welcome-actions-motion-opacity')),
      matching: find.byType(CustomButton),
    );
    if (!tester
        .widgetList<CustomButton>(welcomeActions)
        .any((button) => button.loading)) {
      return;
    }
  }
  fail('Timed out waiting for the recovery action handoff.');
}

void _configureDictionaryPreflightPhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 932);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Finder _dictionaryWelcomeBack() => find.byWidgetPredicate(
  (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
);

final class _DictionaryAssetBundle extends CachingAssetBundle {
  _DictionaryAssetBundle(this.data);

  final ByteData data;
  final _gate = Completer<void>();
  var loadCount = 0;

  static Future<_DictionaryAssetBundle> create({required bool succeeds}) async {
    final data = succeeds
        ? await rootBundle.load(Bip39WordListRepository.assetPath)
        : ByteData(0);
    return _DictionaryAssetBundle(data);
  }

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ByteData> load(String key) async {
    // The read now runs after asynchronous device-security preflight and can
    // legitimately complete inside tester.pump's guard.
    expectSync(key, Bip39WordListRepository.assetPath);
    loadCount += 1;
    await _gate.future;
    return data;
  }
}

enum _SetupAuthInterruption { cancelled, background, walletChanged }

final class _SetupAuthentication
    implements DeviceAuthentication, DeviceAuthenticationBackgroundEvents {
  final prompt = Completer<DeviceAuthenticationResult>();
  int prompts = 0;
  final sensitiveValues = <bool>[];
  final _captures = StreamController<bool>.broadcast(sync: true);
  final _backgrounds = StreamController<void>.broadcast(sync: true);
  bool _captured = false;

  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) {
    prompts += 1;
    return prompt.future;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> setSensitive(bool sensitive) async {
    sensitiveValues.add(sensitive);
  }

  @override
  Stream<bool> get captureChanges => _captures.stream;

  @override
  bool get isCaptured => _captured;

  void capture(bool value) {
    _captured = value;
    _captures.add(value);
  }

  @override
  Stream<void> get backgroundEvents => _backgrounds.stream;

  void background() => _backgrounds.add(null);

  Future<void> close() async {
    await _captures.close();
    await _backgrounds.close();
  }
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
  bool disableAnimations = false,
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
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
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
  bool securityAtRoot = false,
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
          child: securityAtRoot
              ? _RootSecurityLifecycleHost(
                  security: harness.security,
                  child: SecurityGate(
                    controller: harness.security,
                    child: OnboardingShell(child: child!),
                  ),
                )
              : OnboardingShell(child: child!),
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

Future<void> _tapSetupAction(
  WidgetTester tester, {
  required bool addWallet,
  required bool importing,
}) => tester.tap(
  importing
      ? find.widgetWithText(OnboardingTextAction, 'Import Wallet')
      : find.widgetWithText(
          CustomButton,
          addWallet ? 'Add New Wallet' : 'Create Wallet',
        ),
);

/// Mirrors AppLoader's outer lifecycle owner and AsterApp's root SecurityGate
/// placement. The gate encloses Navigator instead of living inside one route.
class _RootSecurityLifecycleHost extends StatefulWidget {
  const _RootSecurityLifecycleHost({
    required this.security,
    required this.child,
  });
  final SecurityController security;
  final Widget child;

  @override
  State<_RootSecurityLifecycleHost> createState() =>
      _RootSecurityLifecycleHostState();
}

class _RootSecurityLifecycleHostState extends State<_RootSecurityLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.security.handleLifecycle(state);

  @override
  Widget build(BuildContext context) => widget.child;
}
