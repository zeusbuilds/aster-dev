import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/services.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/models/models.dart';
import 'package:aster/features/scan/presentation/screens/screens.dart';
import 'package:aster/features/scan/presentation/view_model/view_model.dart';
import 'package:aster/features/scan/presentation/widgets/scan_control_button.dart';
import 'package:aster/features/scan/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/skeleton/presentation/providers/providers.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/presentation_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
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
    expect(zoom.value, 'Zoom level 1 of 3');
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(session.galleryCalls, 1);
  });

  testWidgets(
    'camera failure stays on-screen while gallery remains available',
    (tester) async {
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
        findsOneWidget,
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
    },
  );

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
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.title, 'Scanner could not pause');
    expect(harness.toasts.messages.single.variant, ToastVariant.failure);
    expect(harness.haptics.intents, [
      HapticIntent.lightImpact,
      HapticIntent.error,
    ]);
  });

  testWidgets('retryable camera failure remains usable on a compact phone', (
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

    expect(find.text('Retry'), findsOneWidget);
    expect(find.bySemanticsLabel('Choose a QR image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('orphaned picker fails closed without staging Send data', (
    tester,
  ) async {
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
    expect(harness.toasts.messages, hasLength(1));
    expect(harness.toasts.messages.single.title, 'Scan session expired');
    expect(session.resetCaptureCalls, 1);
    expect(session.activeValues.last, isTrue);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });
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
    required FakeScanSession session,
    required GoRouter router,
    ScanPurpose purpose = ScanPurpose.destinationPicker,
  }) {
    final haptics = RecordingHapticFeedbackService();
    return _ScanWidgetHarness._(
      session: session,
      router: router,
      purpose: purpose,
      haptics: haptics,
      toasts: RecordingToastPresentationService(),
    );
  }

  _ScanWidgetHarness._({
    required this.session,
    required this.router,
    required this.purpose,
    required this.haptics,
    required this.toasts,
  }) : container = ProviderContainer(
         overrides: [
           scanSessionProvider(purpose).overrideWithValue(session),
           scanWalletIdentityProvider.overrideWith(
             (ref) async => const ScanWalletIdentity(
               name: 'Primary wallet',
               displayId: 'ABCDEF 123456',
             ),
           ),
           hapticFeedbackServiceProvider.overrideWithValue(haptics),
         ],
       );

  final FakeScanSession session;
  final GoRouter router;
  final ScanPurpose purpose;
  final RecordingHapticFeedbackService haptics;
  final RecordingToastPresentationService toasts;
  final ProviderContainer container;

  void activateScanTab() {
    container
        .read(skeletonIndexProvider.notifier)
        .setIndex(skeletonScanTabIndex);
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
