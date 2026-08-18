import 'dart:io';

import 'package:aster/features/onboarding/presentation/screens/onboarding_shell.dart';
import 'package:aster/features/onboarding/presentation/widgets/widgets.dart';
import 'package:aster/main.dart' as app;
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _mebibyte = 1024 * 1024;
const _maximumRetainedGrowthBytes = 32 * _mebibyte;
const _maximumMissedFrameRatio = 0.05;
const _frameBudgetMicroseconds = 16000;
const _setupTimeout = Duration(seconds: 45);
const _routeCycles = 6;
const _pageCycles = 5;
const _isIsolatedProfileBenchmark = bool.fromEnvironment(
  'UTEXO_ISOLATED_PROFILE_BENCHMARK',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('onboarding choreography stays within frame and memory budgets', (
    tester,
  ) async {
    expect(
      _isIsolatedProfileBenchmark,
      isTrue,
      reason:
          'Run this benchmark through '
          '`make android-presentation-performance-test` so Profile state is '
          'isolated and reset.',
    );
    app.main();
    await _pumpUntilGone(tester, find.byType(AnimatedSplashScreen));
    await _pumpUntilFound(tester, find.bySemanticsLabel('Import Wallet'));
    final backgroundSnapshot = await _waitForBackgroundSnapshot(tester);

    // Warm image, shader, route, and BIP39 caches before measuring retention.
    await _exerciseImportRoute(tester);
    expect(backgroundSnapshot.controller.allowSnapshotting, isTrue);
    final backgroundPainter =
        backgroundSnapshot.painter as OnboardingBackgroundSnapshotPainter;
    expect(backgroundPainter.hasPaintedSnapshot, isTrue);
    final warmRssBytes = ProcessInfo.currentRss;

    await binding.watchPerformance(() async {
      for (var iteration = 0; iteration < _routeCycles; iteration += 1) {
        await _openImportRoute(tester);
        await _closeImportRoute(tester);
      }
    }, reportKey: 'onboarding_route_choreography');

    await _openImportRoute(tester);
    _expectMountedBackgroundSnapshot(tester, backgroundPainter);
    await binding.watchPerformance(() async {
      await _exercisePageChoreography(tester);
    }, reportKey: 'onboarding_page_choreography');
    _expectMountedBackgroundSnapshot(tester, backgroundPainter);
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
    binding.reportData!['onboarding_background_snapshot'] = <String, Object>{
      'painted': backgroundPainter.hasPaintedSnapshot,
      'physical_width': backgroundPainter.physicalSize!.width,
      'physical_height': backgroundPainter.physicalSize!.height,
      'pixel_ratio': backgroundPainter.pixelRatio!,
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

Future<SnapshotWidget> _waitForBackgroundSnapshot(
  WidgetTester tester, {
  Duration timeout = _setupTimeout,
}) async {
  final snapshot = tester
      .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
      .singleWhere(
        (candidate) => candidate.child is OnboardingWelcomeMeshBackground,
      );
  expect(snapshot.painter, isA<OnboardingBackgroundSnapshotPainter>());
  final painter = snapshot.painter as OnboardingBackgroundSnapshotPainter;
  final deadline = DateTime.now().add(timeout);
  while (!painter.hasPaintedSnapshot && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    painter.hasPaintedSnapshot,
    isTrue,
    reason: 'The onboarding background never produced a retained snapshot.',
  );
  return snapshot;
}

void _expectMountedBackgroundSnapshot(
  WidgetTester tester,
  OnboardingBackgroundSnapshotPainter expectedPainter,
) {
  final snapshots = tester
      .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
      .where((candidate) => candidate.child is OnboardingWelcomeMeshBackground)
      .toList(growable: false);
  expect(snapshots, hasLength(1));
  expect(snapshots.single.painter, same(expectedPainter));
  expect(expectedPainter.hasPaintedSnapshot, isTrue);
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
    reason: _budgetFailure(
      workload,
      phase: 'build',
      metrics: metrics,
      frameCount: frameCount,
      missedFrames: missedBuildFrames,
    ),
  );
  expect(
    missedRasterFrames / frameCount,
    lessThanOrEqualTo(_maximumMissedFrameRatio),
    reason: _budgetFailure(
      workload,
      phase: 'rasterizer',
      metrics: metrics,
      frameCount: frameCount,
      missedFrames: missedRasterFrames,
    ),
  );
}

String _budgetFailure(
  String workload, {
  required String phase,
  required Map<String, dynamic> metrics,
  required int frameCount,
  required int missedFrames,
}) {
  final rawTimes = metrics['frame_${phase}_times'];
  final frameTimes = <int>[];
  final slowFrames = <String>[];
  if (rawTimes is List<dynamic>) {
    for (final (index, value) in rawTimes.indexed) {
      if (value is! int) continue;
      frameTimes.add(value);
      if (value > _frameBudgetMicroseconds) {
        slowFrames.add('$index:${(value / 1000).toStringAsFixed(3)}ms');
      }
    }
  }
  frameTimes.sort();
  final average = frameTimes.isEmpty
      ? 0
      : frameTimes.reduce((left, right) => left + right) / frameTimes.length;
  final p90 = frameTimes.isEmpty
      ? 0
      : frameTimes[((frameTimes.length - 1) * 0.9).round()];
  final worst = frameTimes.isEmpty ? 0 : frameTimes.last;
  return '$workload missed $missedFrames/$frameCount $phase budgets; '
      'average ${(average / 1000).toStringAsFixed(3)}ms, '
      'p90 ${(p90 / 1000).toStringAsFixed(3)}ms, '
      'worst ${(worst / 1000).toStringAsFixed(3)}ms; '
      'slow frames: ${slowFrames.join(', ')}.';
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
