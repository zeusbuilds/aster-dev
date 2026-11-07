import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/scan_session.dart';
import 'package:aster/features/scan/data/services/scan_session_contract.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/models/models.dart';
import 'package:aster/features/scan/presentation/screens/screens.dart';
import 'package:aster/features/scan/presentation/view_model/view_models.dart';
import 'package:aster/features/scan/presentation/widgets/scan_control_button.dart';
import 'package:aster/features/scan/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/shell/presentation/providers/providers.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/presentation_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  testWidgets('gallery keeps its icon throughout selection and decoding', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver()
      ..analyzeGate = Completer<Iterable<String?>>();
    final gallery = FakeScanGallerySource()
      ..selectionGate = Completer<String?>();
    final session = ManagedScanSession(driver, gallery);
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    final control = find.byWidgetPredicate(
      (widget) =>
          widget is ScanControlButton &&
          widget.semanticLabel == 'Choose a QR image',
    );
    final originalOpacity = tester
        .widget<Opacity>(
          find.descendant(of: control, matching: find.byType(Opacity)),
        )
        .opacity;

    await tester.tap(find.bySemanticsLabel('Choose a QR image'));
    await tester.pump();

    expect(session.snapshot.galleryPhase, ScanGalleryPhase.selecting);
    expect(tester.widget<ScanControlButton>(control).busy, isTrue);
    expect(
      find.descendant(of: control, matching: find.byType(Icon)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: control, matching: find.byType(Opacity)),
          )
          .opacity,
      originalOpacity,
    );
    expect(find.byType(GridLoader), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Choose a QR image'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    final duplicate = await harness.container
        .read(scanViewModelProvider(ScanPurpose.sendLauncher).notifier)
        .scanGallery();
    expect(duplicate, isA<AppFailureResult<ScanGalleryOutcome>>());
    expect(gallery.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(driver.commandLog, ['start', 'stop']);

    gallery.selectionGate!.complete('temporary-selected-image');
    await tester.pump();
    await tester.pump();
    expect(session.snapshot.galleryPhase, ScanGalleryPhase.analyzing);
    expect(
      find.descendant(of: control, matching: find.byType(GridLoader)),
      findsNothing,
    );
    expect(find.byType(GridLoader), findsNothing);
    expect(harness.toasts.messages, isEmpty);

    driver.analyzeGate!.complete(const []);
    await tester.pumpAndSettle();
    expect(session.snapshot.galleryPhase, ScanGalleryPhase.idle);
    expect(tester.widget<ScanControlButton>(control).busy, isFalse);
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.title, 'No payment QR found');
    expect(driver.commandLog, ['start', 'stop', 'analyze', 'start']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  for (final pickerFailure in [true, false]) {
    testWidgets(
      'gallery ${pickerFailure ? 'permission' : 'decode'} failure is shown once and restores controls',
      (tester) async {
        final driver = FakeScanCameraDriver();
        final gallery = FakeScanGallerySource()..paths.add('selected-image');
        if (pickerFailure) {
          gallery.failure = const ScanDriverException(
            code: 'scan_gallery_selection_failed',
            kind: ScanDriverFailureKind.permissionDenied,
          );
        } else {
          driver.analyzeFailure = const ScanDriverException(
            code: 'scan_gallery_analysis_failed',
            kind: ScanDriverFailureKind.unavailable,
          );
        }
        final session = ManagedScanSession(driver, gallery);
        final router = _launcherRouter();
        addTearDown(router.dispose);
        final harness = _ScanWidgetHarness(
          session: session,
          router: router,
          purpose: ScanPurpose.sendLauncher,
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.app);
        harness.activateScanTab();
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Choose a QR image'));
        await tester.pumpAndSettle();

        expect(harness.toasts.messages, hasLength(1));
        expect(
          harness.toasts.messages.single.title,
          pickerFailure
              ? 'Photo access unavailable'
              : 'Image could not be scanned',
        );
        expect(harness.toasts.messages.single.variant, ToastVariant.warning);
        expect(session.snapshot.galleryPhase, ScanGalleryPhase.idle);
        expect(session.snapshot.isRunning, isTrue);
        expect(session.snapshot.failure, isNull);
        expect(
          harness.container
              .read(scanViewModelProvider(ScanPurpose.sendLauncher))
              .canUseGallery,
          isTrue,
        );

        // A second, cancelled picker remains usable and adds no feedback.
        gallery.failure = null;
        gallery.paths.clear();
        await tester.tap(find.bySemanticsLabel('Choose a QR image'));
        await tester.pumpAndSettle();
        expect(gallery.calls, 2);
        expect(harness.toasts.messages, hasLength(1));
        expect(session.snapshot.isRunning, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(await session.close(), isA<AppSuccess<void>>());
      },
    );
  }

  testWidgets(
    'disposed gallery does not navigate or show delayed decode feedback',
    (tester) async {
      final driver = FakeScanCameraDriver()
        ..analyzeGate = Completer<Iterable<String?>>();
      final gallery = FakeScanGallerySource()..paths.add('selected-image');
      final session = ManagedScanSession(driver, gallery);
      final router = _launcherRouter();
      addTearDown(router.dispose);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.sendLauncher,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      harness.activateScanTab();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Choose a QR image'));
      await tester.pump();
      expect(session.snapshot.galleryPhase, ScanGalleryPhase.analyzing);
      await tester.pumpWidget(const SizedBox.shrink());
      final closing = session.close();
      driver.analyzeGate!.complete(['bitcoin:bc1qlate']);
      await tester.pump();
      expect(await closing, isA<AppSuccess<void>>());
      expect(harness.toasts.messages, isEmpty);
      expect(harness.container.read(sendDestinationHandoffProvider), isNull);
      expect(session.snapshot.captureLocked, isFalse);
      expect(driver.closeCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing wallet identity renders neither loader nor status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ScanWalletHeader()),
      ),
    );
    expect(find.byType(GridLoader), findsNothing);
    expect(find.byType(AppSkeletonizer), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
  });

  for (final retryable in [true, false]) {
    testWidgets('wallet identity failure is silent (retryable: $retryable)', (
      tester,
    ) async {
      final failure = AppFailure(
        code: 'wallet_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Private operational failure.',
        retryable: retryable,
      );
      final session = FakeScanSession();
      final router = _launcherRouter();
      addTearDown(router.dispose);
      final wallet = _RecoveringWalletViewModel(failure);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.sendLauncher,
        walletViewModel: wallet,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      harness.activateScanTab();
      await tester.pumpAndSettle();
      expect(find.text(failure.userMessage), findsNothing);
      expect(find.text('Wallet unavailable'), findsNothing);
      expect(find.bySemanticsLabel('Retry active wallet'), findsNothing);
      expect(find.byType(GridLoader), findsNothing);
      expect(find.byKey(const ValueKey('fake-scan-camera')), findsOneWidget);
      expect(harness.toasts.messages, isEmpty);
      expect(wallet.retryAttempts, 0);
    });
  }

  testWidgets(
    'retained old wallet identity is hidden during loading and failure',
    (tester) async {
      final identity = _MutableScanWalletIdentityViewModel();
      final session = FakeScanSession();
      final router = _launcherRouter();
      addTearDown(router.dispose);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.sendLauncher,
        identityViewModel: identity,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      harness.activateScanTab();
      await tester.pumpAndSettle();
      expect(find.text('Primary wallet'), findsOneWidget);
      identity.pending();
      await tester.pump();
      expect(find.text('Primary wallet'), findsNothing);
      expect(find.byType(GridLoader), findsNothing);
      identity.failed();
      await tester.pump();
      expect(find.text('Primary wallet'), findsNothing);
      expect(find.textContaining('unavailable'), findsNothing);
      identity.ready();
      await tester.pump();
      expect(find.text('Next wallet'), findsOneWidget);
      expect(find.text('Primary wallet'), findsNothing);
    },
  );

  testWidgets('disabled Scan controls expose a visible disabled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ScanControlButton(
            semanticLabel: 'Unavailable scanner control',
            child: Icon(Icons.photo),
          ),
        ),
      ),
    );

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(ScanControlButton),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, const AsterStateLayers().disabled);
  });

  testWidgets('destination picker returns exactly one bounded camera result', (
    tester,
  ) async {
    final session = FakeScanSession();
    final result = ValueNotifier<String?>(null);
    addTearDown(result.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result.value = await context.push<String>(RoutePaths.scan);
              },
              child: const Text('Open scanner'),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.scan,
          name: RouteNames.scan,
          builder: (context, state) =>
              const ScanScreen(purpose: ScanPurpose.destinationPicker),
        ),
      ],
    );
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(session: session, router: router);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    session.emitCamera('bitcoin:bc1qexample');
    session.emitCamera('second');
    await tester.pumpAndSettle();

    expect(result.value, 'bitcoin:bc1qexample');
    expect(find.text('Open scanner'), findsOneWidget);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('direct Scan route defaults to launcher completion semantics', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = GoRouter(
      initialLocation: RoutePaths.scan,
      routes: [_configuredScanRoute()],
    );
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ScanScreen>(find.byType(ScanScreen)).purpose,
      ScanPurpose.sendLauncher,
    );
  });

  testWidgets('configured Scan route honors an explicit picker request', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () => context.push<void>(
                RoutePaths.scan,
                extra: ScanPurpose.destinationPicker,
              ),
              child: const Text('Open configured scanner'),
            ),
          ),
        ),
        _configuredScanRoute(),
      ],
    );
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.destinationPicker,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    await tester.tap(find.text('Open configured scanner'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ScanScreen>(find.byType(ScanScreen)).purpose,
      ScanPurpose.destinationPicker,
    );
  });

  testWidgets('persistent Scan stages one result and opens target selection', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    session.emitCamera('lightning:invoice');
    await tester.pumpAndSettle();

    expect(find.text('Send target selection'), findsOneWidget);
    expect(
      harness.container.read(sendDestinationHandoffProvider)?.toString(),
      'SendDestinationHandoffValue(redacted)',
    );
    expect(
      harness.container.read(sendDestinationHandoffProvider)!.value,
      'lightning:invoice',
    );
    expect(session.activeValues, contains(false));

    router.pop();
    await tester.pumpAndSettle();
    expect(session.resetCaptureCalls, 1);
    expect(session.activeValues.last, isTrue);
  });

  testWidgets(
    'launcher route failure is cleared and resumed without feedback',
    (tester) async {
      final session = FakeScanSession();
      final router = GoRouter(
        initialLocation: RoutePaths.scan,
        routes: [
          GoRoute(
            path: RoutePaths.scan,
            name: RouteNames.scan,
            builder: (context, state) =>
                const ScanScreen(purpose: ScanPurpose.sendLauncher),
          ),
        ],
      );
      addTearDown(router.dispose);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.sendLauncher,
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.app);
      harness.activateScanTab();
      await tester.pump();
      session.emitCamera('lightning:invoice');
      await tester.pumpAndSettle();

      expect(harness.container.read(sendDestinationHandoffProvider), isNull);
      expect(harness.toasts.messages, isEmpty);
      expect(session.activeValues, contains(false));
      expect(session.activeValues.last, isTrue);
      expect(session.resetCaptureCalls, 1);
      expect(harness.haptics.intents, [HapticIntent.lightImpact]);
    },
  );

  testWidgets('manual launcher opens Send without carrying a stale payload', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);
    harness.container
        .read(sendDestinationHandoffProvider.notifier)
        .stage('stale');

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter payment details to send'));
    await tester.pumpAndSettle();

    expect(find.text('Send target selection'), findsOneWidget);
    expect(harness.container.read(sendDestinationHandoffProvider), isNull);
  });

  testWidgets('manual entry is disabled while a Scan operation is active', (
    tester,
  ) async {
    final session = FakeScanSession()
      ..galleryGate = Completer<AppResult<ScanGalleryOutcome>>();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Choose a QR image'));
    await tester.pump();

    final manual = tester.getSemantics(
      find.bySemanticsLabel('Enter payment details to send'),
    );
    expect(
      manual.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.text('Enter payment details to send'));
    await tester.pump();
    expect(find.text('Send target selection'), findsNothing);
    expect(harness.haptics.intents, isEmpty);

    session.galleryGate!.complete(
      const AppResult.success(ScanGalleryCancelled()),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Enter payment details to send'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('header and controls expose truthful accessible state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = FakeScanSession();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pump();

    expect(find.text('Primary wallet'), findsOneWidget);
    expect(find.text('ABCDEF 123456'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ScanWalletHeader),
        matching: find.byType(NumericText),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('Active wallet, Primary wallet, ID ABCDEF 123456'),
      findsOneWidget,
    );
    final gallery = tester.getSemantics(
      find.bySemanticsLabel('Choose a QR image'),
    );
    final flash = tester.getSemantics(
      find.bySemanticsLabel('Turn flashlight on'),
    );
    final zoom = tester.getSemantics(
      find.bySemanticsLabel('Change zoom level'),
    );
    expect(
      gallery.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(flash.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    expect(zoom.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    expect(zoom.value, 'Zoom 1 times');
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(session.galleryCalls, 1);
  });

  testWidgets('camera failure is silent while gallery remains available', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);
    session.current = const ScanSessionSnapshot(
      failure: AppFailure(
        code: 'scan_camera_permission_denied',
        kind: AppFailureKind.authentication,
        userMessage: 'Allow camera access in system settings to scan a code.',
        retryable: false,
      ),
    );

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pump();

    expect(
      find.text('Allow camera access in system settings to scan a code.'),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Choose a QR image'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Choose a QR image'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.none,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Turn flashlight on'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Turn flashlight on'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
  });

  testWidgets('Send stays closed when the scanner cannot pause', (
    tester,
  ) async {
    final session = FakeScanSession()
      ..activeResult = AppResult.failure(
        const AppFailure(
          code: 'scan_camera_stop_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The camera could not be stopped.',
          retryable: true,
        ),
      );
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pump();
    session.emitCamera('bitcoin:bc1qexample');
    await tester.pump();

    expect(find.text('Send target selection'), findsNothing);
    expect(harness.container.read(sendDestinationHandoffProvider), isNull);
    expect(harness.toasts.messages, isEmpty);
    expect(session.resetCaptureCalls, 1);
    expect(session.activeValues.last, isTrue);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('discarded launcher clears its staged destination', (
    tester,
  ) async {
    final session = FakeScanSession();
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    final pauseGate = Completer<AppResult<void>>();
    session.activeGate = pauseGate;

    session.emitCamera('lightning:invoice');
    await tester.pump();

    expect(harness.container.read(sendDestinationHandoffProvider), isNotNull);
    expect(session.activeValues.last, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    pauseGate.complete(const AppResult.success(null));
    await tester.pump();

    expect(harness.container.read(sendDestinationHandoffProvider), isNull);
    expect(find.text('Send target selection'), findsNothing);
  });

  for (final changeWallet in [false, true]) {
    testWidgets(
      'late camera pause cannot navigate after ${changeWallet ? 'wallet change' : 'tab change'}',
      (tester) async {
        final session = FakeScanSession()..contextToken = 1;
        final router = _launcherRouter();
        addTearDown(router.dispose);
        final harness = _ScanWidgetHarness(
          session: session,
          router: router,
          purpose: ScanPurpose.sendLauncher,
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.app);
        harness.activateScanTab();
        await tester.pumpAndSettle();
        final gate = Completer<AppResult<void>>();
        session.activeGate = gate;
        session.emitCamera('bitcoin:accepted');
        await tester.pump();
        if (changeWallet) {
          session.contextToken = 2;
        } else {
          harness.container.read(appShellIndexProvider.notifier).setIndex(0);
          await tester.pump();
        }
        session.activeGate = null;
        gate.complete(const AppResult.success(null));
        await tester.pumpAndSettle();
        expect(find.text('Send target selection'), findsNothing);
        expect(harness.container.read(sendDestinationHandoffProvider), isNull);
        expect(harness.toasts.messages, isEmpty);
        expect(session.resetCaptureCalls, 1);
      },
    );
  }

  testWidgets(
    'gallery completion on a hidden tab is discarded and scanner rearmed',
    (tester) async {
      final session = FakeScanSession()
        ..galleryGate = Completer<AppResult<ScanGalleryOutcome>>();
      final router = _launcherRouter();
      addTearDown(router.dispose);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.sendLauncher,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      harness.activateScanTab();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Choose a QR image'));
      await tester.pump();
      harness.container.read(appShellIndexProvider.notifier).setIndex(0);
      await tester.pump();
      session.galleryGate!.complete(
        AppResult.success(
          ScanGalleryCaptured(
            ScanPayload.parse('bitcoin:old', source: ScanCaptureSource.gallery),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.toasts.messages, isEmpty);
      expect(harness.container.read(sendDestinationHandoffProvider), isNull);
      expect(session.resetCaptureCalls, 1);
      harness.activateScanTab();
      await tester.pumpAndSettle();
      session.emitCamera('bitcoin:fresh');
      await tester.pumpAndSettle();
      expect(find.text('Send target selection'), findsOneWidget);
      expect(
        harness.container.read(sendDestinationHandoffProvider)?.value,
        'bitcoin:fresh',
      );
    },
  );

  testWidgets('gallery camera pause failure never claims an image failed', (
    tester,
  ) async {
    final session = FakeScanSession()
      ..activeResult = const AppResult.failure(
        AppFailure(
          code: 'camera_stop_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'Camera could not be paused.',
          retryable: true,
        ),
      );
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Choose a QR image'));
    await tester.pumpAndSettle();
    expect(session.galleryCalls, 0);
    expect(session.activeValues, [false, true]);
    expect(harness.toasts.messages, isEmpty);
    expect(find.byType(GridLoader), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('replaced gallery session cannot navigate with stale data', (
    tester,
  ) async {
    final first = FakeScanSession()
      ..galleryGate = Completer<AppResult<ScanGalleryOutcome>>();
    final second = FakeScanSession();
    var session = first;
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: first,
      sessionBuilder: () => session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Choose a QR image'));
    await tester.pump();

    session = second;
    harness.container.invalidate(scanSessionProvider(ScanPurpose.sendLauncher));
    await tester.pump();
    first.galleryGate!.complete(
      AppResult.success(
        ScanGalleryCaptured(
          ScanPayload.parse(
            'lightning:obsolete',
            source: ScanCaptureSource.gallery,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Send target selection'), findsNothing);
    expect(harness.container.read(sendDestinationHandoffProvider), isNull);
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets('retryable camera failure remains quiet on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = FakeScanSession();
    session.current = const ScanSessionSnapshot(
      isInitialized: true,
      failure: AppFailure(
        code: 'scan_camera_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'The camera could not be started. Check access and retry.',
        retryable: true,
      ),
    );
    final router = _launcherRouter();
    addTearDown(router.dispose);
    final harness = _ScanWidgetHarness(
      session: session,
      router: router,
      purpose: ScanPurpose.sendLauncher,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    harness.activateScanTab();
    await tester.pump();

    expect(find.text('Retry'), findsNothing);
    expect(find.byType(GridLoader), findsNothing);
    expect(find.bySemanticsLabel('Choose a QR image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets(
    'orphaned picker falls back quietly without claiming session expiry',
    (tester) async {
      final session = FakeScanSession();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const ScanScreen(purpose: ScanPurpose.destinationPicker),
          ),
        ],
      );
      addTearDown(router.dispose);
      final harness = _ScanWidgetHarness(
        session: session,
        router: router,
        purpose: ScanPurpose.destinationPicker,
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pump();
      session.emitCamera('lightning:invoice');
      await tester.pump();

      expect(harness.container.read(sendDestinationHandoffProvider), isNull);
      expect(harness.toasts.messages, isEmpty);
      expect(find.text('Scan session expired'), findsNothing);
      expect(session.resetCaptureCalls, 1);
      expect(session.activeValues.last, isTrue);
      expect(harness.haptics.intents, [HapticIntent.lightImpact]);
    },
  );
}

GoRoute _configuredScanRoute() {
  return RouteConfig.getRoutes().whereType<GoRoute>().singleWhere(
    (route) => route.path == RoutePaths.scan,
  );
}

GoRouter _launcherRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const ScanScreen(purpose: ScanPurpose.sendLauncher),
      ),
      GoRoute(
        path: RoutePaths.send,
        name: RouteNames.send,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Send target selection'))),
      ),
    ],
  );
}

final class _ScanWidgetHarness {
  factory _ScanWidgetHarness({
    required ScanSession session,
    required GoRouter router,
    ScanPurpose purpose = ScanPurpose.destinationPicker,
    ScanSession Function()? sessionBuilder,
    WalletViewModel? walletViewModel,
    ScanWalletIdentityViewModel? identityViewModel,
  }) {
    final haptics = RecordingHapticFeedbackService();
    return _ScanWidgetHarness._(
      session: session,
      router: router,
      purpose: purpose,
      sessionBuilder: sessionBuilder,
      walletViewModel: walletViewModel,
      identityViewModel: identityViewModel,
      haptics: haptics,
      toasts: RecordingToastPresentationService(),
    );
  }

  _ScanWidgetHarness._({
    required this.session,
    required this.router,
    required this.purpose,
    ScanSession Function()? sessionBuilder,
    WalletViewModel? walletViewModel,
    ScanWalletIdentityViewModel? identityViewModel,
    required this.haptics,
    required this.toasts,
  }) : container = ProviderContainer(
         retry: (retryCount, error) => null,
         overrides: [
           scanSessionProvider(purpose)
               .overrideWith((ref) => sessionBuilder?.call() ?? session),
           if (walletViewModel == null)
             scanWalletIdentityViewModelProvider.overrideWith(
               () => identityViewModel ?? _FixedScanWalletIdentityViewModel(),
             )
           else
             walletViewModelProvider.overrideWith(() => walletViewModel),
           hapticFeedbackServiceProvider.overrideWithValue(haptics),
         ],
       );

  final ScanSession session;
  final GoRouter router;
  final ScanPurpose purpose;
  final RecordingHapticFeedbackService haptics;
  final RecordingToastPresentationService toasts;
  final ProviderContainer container;

  void activateScanTab() {
    container
        .read(appShellIndexProvider.notifier)
        .setIndex(appShellScanTabIndex);
  }

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: AsterFeedbackScope(
      haptics: haptics,
      toasts: toasts,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );

  void dispose() => container.dispose();
}

final class _FixedScanWalletIdentityViewModel
    extends ScanWalletIdentityViewModel {
  @override
  Future<ScanWalletIdentity?> build() async => const ScanWalletIdentity(
    name: 'Primary wallet',
    displayId: 'ABCDEF 123456',
  );
}

final class _MutableScanWalletIdentityViewModel
    extends ScanWalletIdentityViewModel {
  static const previous = ScanWalletIdentity(
    name: 'Primary wallet',
    displayId: 'ABCDEF 123456',
  );
  @override
  Future<ScanWalletIdentity?> build() async => previous;
  void pending() => state = const AsyncLoading<ScanWalletIdentity?>()
      // Model Riverpod's real retained-value refresh state explicitly.
      // ignore: invalid_use_of_internal_member
      .copyWithPrevious(const AsyncData(previous));
  void failed() => state = AsyncError<ScanWalletIdentity?>(
    StateError('private failure'),
    StackTrace.current,
    // Model Riverpod's real retained-value error state explicitly.
    // ignore: invalid_use_of_internal_member
  ).copyWithPrevious(const AsyncData(previous));
  void ready() => state = const AsyncData(
    ScanWalletIdentity(name: 'Next wallet', displayId: '987654 ABCDEF'),
  );
}

final class _RecoveringWalletViewModel extends WalletViewModel {
  _RecoveringWalletViewModel(this.failure);

  final AppFailure failure;
  var retryAttempts = 0;

  @override
  Future<WalletState> build() async {
    await Future<void>.delayed(Duration.zero);
    throw AppFailureException(failure);
  }

  @override
  Future<void> reload() async {
    retryAttempts += 1;
    state = AsyncData(_scanWalletState);
  }
}

final _scanWalletProfile = WalletProfile(
  id: '11111111111111111111111111111111',
  name: 'Primary wallet',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);

final _scanWalletState = WalletState(
  wallets: [_scanWalletProfile],
  activeWallet: _scanWalletProfile,
);
