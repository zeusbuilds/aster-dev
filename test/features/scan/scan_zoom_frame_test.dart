import 'dart:ui' as ui;

import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/models/models.dart';
import 'package:aster/features/scan/presentation/widgets/scan_control_button.dart';
import 'package:aster/features/scan/presentation/widgets/scan_frame.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('DM Sans', 'assets/fonts/DMSans-Variable.ttf'),
      ('Public Sans', 'assets/fonts/PublicSans-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
      'magnification including x fits a compact scanner at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final ratio in [1.0, 2.0, 3.0, 1.5, 1.75]) {
          final state = ScanState(
            cameraInitialized: true,
            cameraRunning: true,
            zoom: ScanZoomRange(minimum: 1, maximum: 5, current: ratio),
          );
          await tester.pumpWidget(_frame(state, scale: scale));

          final zoom = find.byWidgetPredicate(
            (widget) =>
                widget is ScanControlButton &&
                widget.semanticLabel == 'Change zoom level',
          );
          final text = find.text(state.zoom!.displayLabel);
          final textRect = tester.getRect(text);
          final controlRect = tester.getRect(zoom);
          final circles = _circleRects(tester);
          final touchRects = _touchRects(tester);
          final pillRect = tester.getRect(find.byType(AsterPill));
          expect(text, findsOneWidget);
          expect(textRect.left, greaterThanOrEqualTo(controlRect.left));
          expect(textRect.right, lessThanOrEqualTo(controlRect.right));
          expect(textRect.top, greaterThanOrEqualTo(controlRect.top));
          expect(textRect.bottom, lessThanOrEqualTo(controlRect.bottom));
          _expectUniformGeometry(circles, touchRects, pillRect);
          expect(pillRect.width, lessThanOrEqualTo(224.001));
          expect(pillRect.left, greaterThanOrEqualTo(48));
          expect(pillRect.right, lessThanOrEqualTo(272));
          for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
            expect(icon.size, 16);
          }
          expect(tester.takeException(), isNull);
          final semantics = tester.getSemantics(
            find.bySemanticsLabel('Change zoom level'),
          );
          expect(semantics.value, state.zoom!.semanticLabel);
          expect(
            semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          expect(find.byType(GridLoader), findsNothing);
          expect(find.textContaining('/3'), findsNothing);
        }
      },
    );
  }

  testWidgets(
    'default circles are 32 px with 16 px icons and 48 px hit cells',
    (tester) async {
      await tester.pumpWidget(_frame(_readyState));

      final circles = _circleRects(tester);
      final touchRects = _touchRects(tester);
      _expectUniformGeometry(
        circles,
        touchRects,
        tester.getRect(find.byType(AsterPill)),
      );
      expect(
        circles.map((rect) => rect.size),
        everyElement(const Size(32, 32)),
      );
      expect(
        touchRects.map((rect) => rect.size),
        everyElement(const Size(48, 48)),
      );
      expect(tester.getSize(find.byType(AsterPill)), const Size(144, 48));
      final label = tester.widget<NumericText>(find.byType(NumericText));
      expect(label.style!.fontSize, 16);
      expect(label.style!.height, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy and unknown controls keep all three circles equally sized',
    (tester) async {
      await tester.pumpWidget(_frame(_readyState));
      final readyCircles = _circleRects(tester);
      final readyTouch = _touchRects(tester);
      for (final state in [
        _readyState.copyWith(operation: ScanOperation.selectingGallery),
        _readyState.copyWith(operation: ScanOperation.changingZoom),
        const ScanState(cameraInitialized: true, cameraRunning: true),
      ]) {
        await tester.pumpWidget(_frame(state));
        final circles = _circleRects(tester);
        final touchRects = _touchRects(tester);
        expect(circles, readyCircles);
        expect(touchRects, readyTouch);
        for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
          expect(icon.size, 16);
        }
        expect(find.byType(GridLoader), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'unknown capabilities display a quiet disabled icon without inventing 1x',
    (tester) async {
      await tester.pumpWidget(
        _frame(const ScanState(cameraInitialized: true, cameraRunning: true)),
      );

      final zoom = tester.getSemantics(
        find.bySemanticsLabel('Change zoom level'),
      );
      expect(zoom.value, isEmpty);
      expect(
        zoom.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      expect(find.text('1x'), findsNothing);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byType(GridLoader), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

const _readyState = ScanState(
  cameraInitialized: true,
  cameraRunning: true,
  zoom: ScanZoomRange(minimum: 1, maximum: 5, current: 1),
);

List<Rect> _circleRects(WidgetTester tester) => tester
    .widgetList<ScanControlButton>(find.byType(ScanControlButton))
    .map((control) {
      final circle = find.descendant(
        of: find.byWidget(control),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      return tester.getRect(circle);
    })
    .toList();

List<Rect> _touchRects(WidgetTester tester) => find
    .byType(ScanControlButton)
    .evaluate()
    .map((element) => tester.getRect(find.byWidget(element.widget)))
    .toList();

void _expectUniformGeometry(
  List<Rect> circles,
  List<Rect> touchRects,
  Rect pillRect,
) {
  expect(circles, hasLength(3));
  final inset = (touchRects.first.width - circles.first.width) / 2;
  expect(inset, greaterThanOrEqualTo(4));
  for (var index = 0; index < circles.length; index++) {
    final circle = circles[index];
    final touch = touchRects[index];
    expect(circle.width, closeTo(circles.first.width, 0.001));
    expect(circle.height, closeTo(circles.first.height, 0.001));
    expect(touch.width, greaterThanOrEqualTo(48));
    expect(touch.height, greaterThanOrEqualTo(48));
    expect(circle.left - touch.left, closeTo(inset, 0.001));
    expect(circle.top - pillRect.top, closeTo(inset, 0.001));
    expect(pillRect.bottom - circle.bottom, closeTo(inset, 0.001));
    if (index > 0) {
      expect(circle.left - circles[index - 1].right, closeTo(inset * 2, 0.001));
      expect(touch.left, closeTo(touchRects[index - 1].right, 0.001));
    }
  }
  expect(circles.first.left - pillRect.left, closeTo(inset, 0.001));
  expect(pillRect.right - circles.last.right, closeTo(inset, 0.001));
}

Widget _frame(ScanState state, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: ScanFrame(
        size: 224,
        state: state,
        onGalleryTap: () {},
        onFlashTap: () {},
        onZoomTap: state.canChangeZoom ? () {} : null,
      ),
    ),
  ),
);
