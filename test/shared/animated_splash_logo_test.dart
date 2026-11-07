import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aster/shared/branding/aster_logo_geometry.dart';
import 'package:aster/shared/screens/animated_splash_screen.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [160, 705]) {
    test('drawn opening logo matches the shipped SVG at ${width}px', () async {
      final svg = await vg.loadPicture(
        SvgStringLoader(File('assets/brand/aster-mark.svg').readAsStringSync()),
        null,
      );
      addTearDown(svg.picture.dispose);
      expect(svg.size, AsterLogoGeometry.size);
      final scale = width / svg.size.width;
      final height = (svg.size.height * scale).ceil();
      final reference = await _raster(width, height, (canvas) {
        canvas.scale(scale);
        canvas.drawPicture(svg.picture);
      });
      final drawn = await _raster(width, height, (canvas) {
        canvas.translate(width / 2, svg.size.height * scale / 2);
        canvas.drawPath(
          AsterLogoGeometry.animatedPath(
            logoWidth: width.toDouble(),
            horizontalWidth: width.toDouble(),
            rotationProgress: 0,
            expansionProgress: 0,
          ),
          Paint()..color = Colors.white,
        );
      });
      var difference = 0;
      var ink = 0;
      for (var i = 3; i < reference.length; i += 4) {
        difference += (drawn[i] - reference[i]).abs();
        ink += reference[i];
      }
      // The source SVG rounds its merged intersections to three decimals.
      // Rebuilding the exported strokes may differ there by a fraction of an
      // anti-aliased pixel; it must never drift in thickness or proportions.
      expect(difference / ink, lessThan(width == 160 ? 0.001 : 0.0002));
    });
  }

  test('reveal-line thickness scales with the exported horizontal stroke', () {
    expect(
      AsterLogoGeometry.horizontalThicknessForWidth(160),
      closeTo(9.209191489, 0.00000001),
    );
    expect(
      AsterLogoGeometry.horizontalThicknessForWidth(320),
      AsterLogoGeometry.horizontalThicknessForWidth(160) * 2,
    );
  });

  testWidgets('updated mark rotates, hands off without a gap and clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AnimatedSplashScreen.createController(tester);
    addTearDown(controller.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: Colors.pink,
            child: AnimatedSplashScreen(controller: controller),
          ),
        ),
      ),
    );

    Future<Uint8List> frame(double progress) async {
      controller.value = progress;
      await tester.pump();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
    }

    final opening = await frame(0);
    final bounds = _blueBounds(opening, 390);
    final reference = (await tester.runAsync(() async {
      final svg = await vg.loadPicture(
        SvgStringLoader(
          File('assets/brand/aster-mark.svg')
              .readAsStringSync()
              .replaceFirst('fill="white"', 'fill="#001AFF"'),
        ),
        null,
      );
      try {
        return await _raster(390, 844, (canvas) {
          const viewport = Rect.fromLTWH(0, 0, 390, 844);
          canvas.drawRect(viewport, Paint()..color = Colors.white);
          final scale =
              const AsterComponentMetrics().splashLogoWidth / svg.size.width;
          canvas
            ..translate(
              (390 - svg.size.width * scale) / 2,
              (844 - svg.size.height * scale) / 2,
            )
            ..scale(scale)
            ..drawPicture(svg.picture);
        });
      } finally {
        svg.picture.dispose();
      }
    }))!;
    // Anti-aliased tips blend into white; compare against the actual
    // shipped SVG on the same viewport/background rather than rounded bounds.
    expect(bounds, _blueBounds(reference, 390));

    final rotating = await frame(0.096);
    expect(_blueBounds(rotating, 390).height, lessThan(bounds.height));

    final motion = const AsterMotion();
    final beforeHandoff = await frame(motion.splashLinesLengthStart);
    final afterHandoff = await frame(motion.splashLinesLengthStart + 0.0001);
    // The full-width middle line remains solid when reveal bars take over.
    for (final pixels in [beforeHandoff, afterHandoff]) {
      expect(_blueBounds(pixels, 390).width, 390);
      for (var x = 0; x < 390; x += 1) {
        expect(_isBlue(pixels, (422 * 390 + x) * 4), isTrue);
      }
    }

    final settled = await frame(1);
    expect(_blueBounds(settled, 390), Rect.zero);
    var fullyCleared = true;
    for (var i = 0; i < settled.length; i += 4) {
      if (settled[i] != 233 ||
          settled[i + 1] != 30 ||
          settled[i + 2] != 99 ||
          settled[i + 3] != 255) {
        fullyCleared = false;
        break;
      }
    }
    expect(fullyCleared, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _raster(
  int width,
  int height,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

bool _isBlue(Uint8List pixels, int index) =>
    pixels[index] < 10 && pixels[index + 1] < 40 && pixels[index + 2] > 245;

Rect _blueBounds(Uint8List pixels, int width) {
  var left = width;
  var right = -1;
  var top = pixels.length ~/ (width * 4);
  var bottom = -1;
  for (var i = 0; i < pixels.length; i += 4) {
    if (!_isBlue(pixels, i)) continue;
    final x = i ~/ 4 % width;
    final y = i ~/ 4 ~/ width;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  if (right < left) return Rect.zero;
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}
