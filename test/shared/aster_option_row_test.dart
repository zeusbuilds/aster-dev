import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';

import '../support/presentation_fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform toggle preserves shared dynamic row geometry', (
      tester,
    ) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        for (final scale in [1.0, 2.0, 3.0]) {
          await tester.pumpWidget(
            _harness(
              platform: platform,
              direction: direction,
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AsterOptionRow(
                    key: const ValueKey('ordinary'),
                    title: 'App lock',
                    prefixIcon: RemixIcons.lock_line,
                    onTap: () {},
                  ),
                  AsterOptionRow.toggle(
                    key: const ValueKey('toggle'),
                    title: 'App lock',
                    prefixIcon: RemixIcons.lock_line,
                    value: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final ordinary = find.byKey(const ValueKey('ordinary'));
          final toggle = find.byKey(const ValueKey('toggle'));
          final ordinaryRect = tester.getRect(ordinary);
          final toggleRect = tester.getRect(toggle);
          final switchRect = tester.getRect(find.byType(Switch));
          final ordinaryTitle = tester.getRect(
            find.descendant(of: ordinary, matching: find.text('App lock')),
          );
          final toggleTitle = tester.getRect(
            find.descendant(of: toggle, matching: find.text('App lock')),
          );
          final leadingRect = tester.getRect(
            find.descendant(
              of: toggle,
              matching: find.byIcon(RemixIcons.lock_line),
            ),
          );
          final ordinaryLeading = tester.getRect(
            find.descendant(
              of: ordinary,
              matching: find.byIcon(RemixIcons.lock_line),
            ),
          );
          final sharedContentHeight = math.max(
            ordinaryTitle.height,
            ordinaryLeading.height,
          );
          expect(
            ordinaryRect.height,
            closeTo(math.max(48, sharedContentHeight + 32), 0.01),
          );
          expect(
            toggleRect.height,
            closeTo(
              math.max(
                48,
                math.max(toggleTitle.height, leadingRect.height) + 32,
              ),
              0.01,
            ),
          );
          if (scale == 1) {
            expect(toggleRect.height, closeTo(ordinaryRect.height, 0.01));
          }
          expect(switchRect.center.dy, closeTo(toggleRect.center.dy, 0.01));
          expect(switchRect.top, greaterThanOrEqualTo(toggleRect.top));
          expect(switchRect.bottom, lessThanOrEqualTo(toggleRect.bottom));
          expect(toggleTitle.top - toggleRect.top, closeTo(16, 0.01));
          expect(toggleRect.bottom - toggleTitle.bottom, closeTo(16, 0.01));
          expect(
            direction == TextDirection.ltr
                ? toggleTitle.left - leadingRect.right
                : leadingRect.left - toggleTitle.right,
            closeTo(12, 0.01),
          );
          expect(
            direction == TextDirection.ltr
                ? leadingRect.left - toggleRect.left
                : toggleRect.right - leadingRect.right,
            closeTo(20, 0.01),
          );
          expect(find.byType(GridLoader), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('$platform toggle has one action for each input method', (
      tester,
    ) async {
      final haptics = RecordingHapticFeedbackService();
      var value = false;
      final changes = <bool>[];
      await tester.pumpWidget(
        _harness(
          platform: platform,
          haptics: haptics,
          child: StatefulBuilder(
            builder: (context, setState) => AsterOptionRow.toggle(
              title: 'App lock',
              prefixIcon: RemixIcons.lock_line,
              value: value,
              hapticIntent: HapticIntent.selection,
              onChanged: (next) {
                changes.add(next);
                setState(() => value = next);
              },
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('App lock'), findsOneWidget);
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(haptics.intents, [HapticIntent.selection]);
      await tester.tapAt(tester.getCenter(find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(haptics.intents, hasLength(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [true, false, true]);
      expect(haptics.intents, hasLength(3));
      final node = tester.getSemantics(find.bySemanticsLabel('App lock'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isToggled, ui.Tristate.isTrue);
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(changes, [true, false, true, false]);
      expect(haptics.intents, hasLength(4));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('App lock'))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        ui.Tristate.isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$platform disabled toggle retains content and has no action', (
      tester,
    ) async {
      final haptics = RecordingHapticFeedbackService();
      var changes = 0;
      var disabled = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _harness(
          platform: platform,
          haptics: haptics,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AsterOptionRow.toggle(
                key: const ValueKey('toggle'),
                title: 'App lock',
                prefixIcon: RemixIcons.lock_line,
                value: true,
                hapticIntent: HapticIntent.selection,
                onChanged: disabled ? null : (_) => changes++,
              );
            },
          ),
        ),
      );
      final originalRow = tester.getRect(find.byKey(const ValueKey('toggle')));
      final originalSwitch = tester.getRect(find.byType(Switch));
      rebuild(() => disabled = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('toggle'))), originalRow);
      expect(tester.getRect(find.byType(Switch)), originalSwitch);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      final data = tester
          .getSemantics(find.bySemanticsLabel('App lock'))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, ui.Tristate.isTrue);
      expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
      await tester.tap(find.text('App lock'));
      await tester.tapAt(tester.getCenter(find.byType(Switch)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(haptics.intents, isEmpty);
      expect(find.text('App lock'), findsOneWidget);
      expect(find.byType(GridLoader), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$platform native switch drag changes the row only once', (
      tester,
    ) async {
      final haptics = RecordingHapticFeedbackService();
      var value = false;
      final changes = <bool>[];
      await tester.pumpWidget(
        _harness(
          platform: platform,
          haptics: haptics,
          child: StatefulBuilder(
            builder: (context, setState) => AsterOptionRow.toggle(
              title: 'App lock',
              value: value,
              hapticIntent: HapticIntent.selection,
              onChanged: (next) {
                changes.add(next);
                setState(() => value = next);
              },
            ),
          ),
        ),
      );
      await tester.drag(find.byType(Switch), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(haptics.intents, [HapticIntent.selection]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _harness({
  required TargetPlatform platform,
  required Widget child,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  HapticFeedbackService? haptics,
}) => MaterialApp(
  theme: AppTheme.light().copyWith(platform: platform),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: AsterFeedbackScope(
          haptics: haptics ?? const NoopHapticFeedbackService(),
          toasts: RecordingToastPresentationService(),
          child: SingleChildScrollView(
            child: SizedBox(width: 280, child: child),
          ),
        ),
      ),
    ),
  ),
);
