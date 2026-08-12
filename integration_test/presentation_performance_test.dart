import 'dart:io';

import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/main.dart' as app;
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _mebibyte = 1024 * 1024;
const _maximumRetainedGrowthBytes = 32 * _mebibyte;
const _maximumMissedFrameRatio = 0.05;
const _setupTimeout = Duration(seconds: 45);
const _routeCycles = 6;
const _pageCycles = 5;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('onboarding choreography stays within frame and memory budgets', (
    tester,
  ) async {
    app.main();
    await _pumpUntilGone(tester, find.byType(AnimatedSplashScreen));
    await _pumpUntilFound(tester, find.bySemanticsLabel('Import Wallet'));

    // Warm image, shader, route, and BIP39 caches before measuring retention.
    await _exerciseImportRoute(tester);
    final backgroundSnapshot = tester
        .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
        .singleWhere(
          (snapshot) => snapshot.child is OnboardingWelcomeMeshBackground,
        );
    expect(backgroundSnapshot.controller.allowSnapshotting, isTrue);
    final warmRssBytes = ProcessInfo.currentRss;

    await binding.watchPerformance(() async {
      for (var iteration = 0; iteration < _routeCycles; iteration += 1) {
        await _openImportRoute(tester);
        await _closeImportRoute(tester);
      }
    }, reportKey: 'onboarding_route_choreography');

    await _openImportRoute(tester);
    await binding.watchPerformance(() async {
      await _exercisePageChoreography(tester);
    }, reportKey: 'onboarding_page_choreography');
    for (var iteration = 1; iteration < _pageCycles; iteration += 1) {
      await _exercisePageChoreography(tester);
    }
    await _closeImportRoute(tester);

    final finalRssBytes = ProcessInfo.currentRss;
    final retainedGrowthBytes = finalRssBytes - warmRssBytes;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['onboarding_memory'] = <String, Object>{
      'warm_rss_bytes': warmRssBytes,
      'final_rss_bytes': finalRssBytes,
      'retained_growth_bytes': retainedGrowthBytes,
      'route_cycles': _routeCycles,
      'page_cycles': _pageCycles,
    };

    expect(
      retainedGrowthBytes,
      lessThanOrEqualTo(_maximumRetainedGrowthBytes),
      reason:
          'Repeated onboarding choreography retained more than 32 MiB after '
          'warm-up.',
    );

    _expectWithinFrameBudget(
      binding.reportData!['onboarding_route_choreography'],
      workload: 'Onboarding route choreography',
    );
    _expectWithinFrameBudget(
      binding.reportData!['onboarding_page_choreography'],
      workload: 'Onboarding page choreography',
    );
  });
}

Future<void> _exerciseImportRoute(WidgetTester tester) async {
  await _openImportRoute(tester);
  await _exercisePageChoreography(tester);
  await _closeImportRoute(tester);
}

Future<void> _openImportRoute(WidgetTester tester) async {
  await _semanticTap(tester, 'Import Wallet');
  await _pumpUntilFound(tester, find.bySemanticsLabel('Recovery phrase page'));
}

Future<void> _exercisePageChoreography(WidgetTester tester) async {
  final pages = find.byType(PageView);
  expect(pages, findsOneWidget);
  await tester.fling(pages, const Offset(-600, 0), 1600);
  await tester.pumpAndSettle();
  await tester.fling(pages, const Offset(-600, 0), 1600);
  await tester.pumpAndSettle();
  await tester.fling(pages, const Offset(600, 0), 1600);
  await tester.pumpAndSettle();
  await tester.fling(pages, const Offset(600, 0), 1600);
  await tester.pumpAndSettle();
}

Future<void> _closeImportRoute(WidgetTester tester) async {
  await _semanticTap(tester, 'Back');
  await _pumpUntilFound(tester, find.bySemanticsLabel('Import Wallet'));
}

void _expectWithinFrameBudget(Object? report, {required String workload}) {
  expect(report, isA<Map<String, dynamic>>());
  final metrics = report! as Map<String, dynamic>;
  final frameCount = metrics['frame_count']! as int;
  final missedBuildFrames = metrics['missed_frame_build_budget_count']! as int;
  final missedRasterFrames =
      metrics['missed_frame_rasterizer_budget_count']! as int;

  expect(frameCount, greaterThanOrEqualTo(60));
  expect(
    missedBuildFrames / frameCount,
    lessThanOrEqualTo(_maximumMissedFrameRatio),
    reason: '$workload missed more than 5% of build budgets: $metrics',
  );
  expect(
    missedRasterFrames / frameCount,
    lessThanOrEqualTo(_maximumMissedFrameRatio),
    reason: '$workload missed more than 5% of raster budgets: $metrics',
  );
}

Future<void> _semanticTap(WidgetTester tester, String label) async {
  final action = find.semantics.byLabel(label);
  expect(action, findsOneWidget);
  tester.semantics.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = _setupTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = _setupTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsNothing);
  await tester.pumpAndSettle();
}
