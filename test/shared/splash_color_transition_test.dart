import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aster/shared/branding/aster_launch_logo.dart';
import 'package:aster/shared/branding/aster_logo_geometry.dart';
import 'package:aster/shared/screens/animated_splash_screen.dart';
import 'package:aster/shared/screens/splash_screen.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewport = Size(390, 844);
const _logoWidth = 160.0;
const _underlay = Color(0xFFE91E63);
const _blue = Color(0xFF001AFF);

void main() {
  testWidgets('cold hold and animated opening are pixel-identical', (
    tester,
  ) async {
    _configureViewport(tester);
    final capture = _Capture(tester);
    final held = await capture.widget(const SplashScreen());
    final opening = await capture.widget(
      const AnimatedSplashScreen(
        controller: AlwaysStoppedAnimation(0),
        colorTransition: AlwaysStoppedAnimation(0),
      ),
      captureName: '00-opening-white',
    );
    expect(opening, held);
    expect(_pixel(opening, 0, 0), [255, 255, 255, 255]);
    expect(_pixel(opening, 389, 843), [255, 255, 255, 255]);
    // The horizontal stroke is below the opaque portion of the vertical fill:
    // it is visibly blue, rather than the previous white mark on blue.
    final middle = _pixel(opening, 130, 422);
    expect(middle[2], greaterThan(240));
    expect(middle[0], lessThan(100));
    expect(middle[1], greaterThan(middle[0]));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opacity prelude keeps the mark stationary on a white background',
    (tester) async {
      _configureViewport(tester);
      final reveal = AnimatedSplashScreen.createController(tester);
      final colour = AnimatedSplashScreen.createColorTransitionController(
        tester,
      );
      addTearDown(reveal.dispose);
      addTearDown(colour.dispose);
      final capture = _Capture(tester);
      await capture.widget(
        AnimatedSplashScreen(controller: reveal, colorTransition: colour),
      );
      for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        colour.value = progress;
        final actual = await capture.frame(
          captureName: progress == 0.5
              ? '01-colour-midpoint'
              : progress == 1
              ? '02-colour-complete'
              : null,
        );
        final expected = (await tester.runAsync(
          () => _stationaryReference(progress),
        ))!;
        expect(actual, expected, reason: 'Stationary prelude at $progress');
        expect(_pixel(actual, 0, 0), [255, 255, 255, 255]);
        expect(_pixel(actual, 389, 843), [255, 255, 255, 255]);
        expect(reveal.value, 0);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completed prelude is a solid blue SVG without shadows', (
    tester,
  ) async {
    _configureViewport(tester);
    final capture = _Capture(tester);
    final current = await capture.widget(
      const AnimatedSplashScreen(
        controller: AlwaysStoppedAnimation(0),
        colorTransition: AlwaysStoppedAnimation(1),
      ),
    );
    final svg = await vg.loadPicture(
      SvgStringLoader(
        File('assets/brand/aster-mark.svg')
            .readAsStringSync()
            .replaceFirst('fill="white"', 'fill="#001AFF"'),
      ),
      null,
    );
    addTearDown(svg.picture.dispose);
    final legacy = (await tester.runAsync(
      () => _raster((canvas) {
        canvas.drawRect(Offset.zero & _viewport, Paint()..color = Colors.white);
        final scale = _logoWidth / svg.size.width;
        canvas
          ..translate(
            (_viewport.width - _logoWidth) / 2,
            (_viewport.height - svg.size.height * scale) / 2,
          )
          ..scale(scale)
          ..drawPicture(svg.picture);
      }),
    ))!;
    var difference = 0;
    for (var index = 0; index < current.length; index++) {
      difference += (current[index] - legacy[index]).abs();
    }
    // Only sub-pixel rounding of the SVG's merged intersections is allowed.
    expect(difference / (current.length * 255), lessThan(0.00001));

    final background = (await tester.runAsync(
      () => _stationaryReference(1, includeLogo: false),
    ))!;
    final bounds = Rect.fromCenter(
      center: _viewport.center(Offset.zero),
      width: _logoWidth,
      height: _logoWidth * 373 / 705,
    ).inflate(1);
    for (var y = 0; y < _viewport.height; y++) {
      for (var x = 0; x < _viewport.width; x++) {
        if (bounds.contains(Offset(x.toDouble(), y.toDouble()))) continue;
        final index = (y * _viewport.width.toInt() + x) * 4;
        expect(
          current.sublist(index, index + 4),
          background.sublist(index, index + 4),
          reason: 'No residual shadow at $x,$y',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the completed colour phase retains the entire existing reveal', (
    tester,
  ) async {
    _configureViewport(tester);
    final capture = _Capture(tester);
    for (final phase in [0.1, 0.7, 1.0]) {
      final explicit = await capture.widget(
        AnimatedSplashScreen(
          controller: AlwaysStoppedAnimation(phase),
          colorTransition: const AlwaysStoppedAnimation(1),
        ),
        captureName: 'reveal-${(phase * 100).toInt()}',
      );
      final established = await capture.widget(
        AnimatedSplashScreen(controller: AlwaysStoppedAnimation(phase)),
      );
      expect(explicit, established);
      if (phase < 1) {
        expect(_pixel(explicit, 0, 0), [255, 255, 255, 255]);
        expect(_pixel(explicit, 389, 843), [255, 255, 255, 255]);
      }
      if (phase == 1) {
        for (var index = 0; index < explicit.length; index += 4) {
          expect(explicit.sublist(index, index + 4), [233, 30, 99, 255]);
        }
      }
    }
    expect(tester.takeException(), isNull);
  });
}

void _configureViewport(WidgetTester tester) {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final class _Capture {
  _Capture(this.tester);

  final WidgetTester tester;
  final boundary = GlobalKey();

  Future<Uint8List> widget(Widget child, {String? captureName}) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(color: _underlay, child: child),
        ),
      ),
    );
    return frame(captureName: captureName);
  }

  Future<Uint8List> frame({String? captureName}) async {
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await render.toImage();
      try {
        if (captureName != null &&
            Platform.environment['ASTER_CAPTURE_SPLASH_FRAMES'] == '1') {
          final directory = Directory('.buildlog/splash-white-blue-20261026');
          await directory.create(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${directory.path}/$captureName.png')
              .writeAsBytes(png!.buffer.asUint8List());
        }
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  }
}

Future<Uint8List> _stationaryReference(
  double progress, {
  bool includeLogo = true,
}) => _raster((canvas) {
  canvas.drawRect(Offset.zero & _viewport, Paint()..color = Colors.white);
  if (!includeLogo) return;
  final path = AsterLogoGeometry.animatedPath(
    logoWidth: _logoWidth,
    horizontalWidth: _logoWidth,
    rotationProgress: 0,
    expansionProgress: 0,
  );
  canvas.translate(_viewport.width / 2, _viewport.height / 2);
  AsterLaunchLogo.paint(
    canvas,
    path: path,
    logoBounds: path.getBounds(),
    blueColor: _blue,
    finalColor: _blue,
    colorProgress: progress,
  );
});

List<int> _pixel(Uint8List pixels, int x, int y) {
  final index = (y * _viewport.width.toInt() + x) * 4;
  return pixels.sublist(index, index + 4);
}

Future<Uint8List> _raster(void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _viewport.width.toInt(),
    _viewport.height.toInt(),
  );
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
