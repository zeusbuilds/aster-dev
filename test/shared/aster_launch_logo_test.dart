import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aster/shared/branding/aster_launch_logo.dart';
import 'package:aster/shared/branding/aster_logo_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = Color(0xFF001AFF);
const _viewport = Size(360, 260);
const _center = Offset(180, 120);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening fill matches the exported SVG with the authored gradient', () async {
    final source = File('assets/brand/aster-mark.svg').readAsStringSync();
    final svg = await vg.loadPicture(
      SvgStringLoader(
        source
            .replaceFirst(
              '<path ',
              '<defs><linearGradient id="launch" x1="0" y1="0" x2="0" '
                  'y2="373" gradientUnits="userSpaceOnUse">'
                  '<stop offset="0.346154" stop-color="#001AFF"/>'
                  '<stop offset="1" stop-color="#001AFF" stop-opacity="0.3"/>'
                  '</linearGradient></defs><path ',
            )
            .replaceFirst('fill="white"', 'fill="url(#launch)"'),
      ),
      null,
    );
    addTearDown(svg.picture.dispose);
    final reference = await _raster((canvas) {
      const width = 160.0;
      final scale = width / svg.size.width;
      canvas
        ..translate(
          _center.dx - width / 2,
          _center.dy - svg.size.height * scale / 2,
        )
        ..scale(scale)
        ..drawPicture(svg.picture);
    });
    final actual = await _frame(0);
    var difference = 0;
    var ink = 0;
    for (var i = 2; i < actual.length; i += 4) {
      // Black shadows contribute no blue in premultiplied RGBA. Comparing this
      // channel isolates the gradient fill, including the united intersections.
      difference += (actual[i] - reference[i]).abs();
      ink += reference[i];
    }
    // The SVG decoder quantizes opacity and its exported intersections; allow
    // their sub-pixel/one-channel rounding, without accepting a geometry drift.
    expect(difference / ink, lessThan(0.002));
  });

  test(
    'gradient matches the native export stop then reaches 30 percent',
    () async {
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100));
      final pixels = await _raster((canvas) {
        canvas.translate(80, 50);
        AsterLaunchLogo.paint(
          canvas,
          path: path,
          logoBounds: const Rect.fromLTWH(0, 0, 100, 100),
          blueColor: _blue,
          finalColor: _blue,
          colorProgress: 0,
        );
      });
      int blueAt(int y) => _pixel(pixels, 120, y)[2];
      expect(blueAt(60), 255);
      expect(blueAt(83), 255);
      expect(blueAt(85), closeTo(253, 1));
      expect(blueAt(117), closeTo(165, 2));
      expect(blueAt(149), closeTo(78, 2));
    },
  );

  test('shadows follow the artwork and extend outside its bounds', () async {
    final opening = await _frame(0);
    final bounds = _path().getBounds().shift(_center);
    // No filled box in the empty corner of the logo's own bounding rectangle.
    final emptyCorner = _pixel(
      opening,
      bounds.left.ceil() + 4,
      bounds.top.ceil() + 4,
    );
    expect(emptyCorner[2], 0);
    expect(emptyCorner[3], lessThan(3));

    // The lower diagonal tips cast soft shadows outside the unshadowed mark.
    final shadowPixel = _pixel(
      opening,
      (_center.dx + 37).round(),
      bounds.bottom.ceil() + 5,
    );
    expect(shadowPixel.take(3), everyElement(0));
    expect(shadowPixel[3], greaterThan(0));
    // Empty distant canvas stays transparent; no full-screen dark layer.
    expect(_pixel(opening, 5, 5), [0, 0, 0, 0]);
  });

  test('shadow opacity decreases throughout the colour transition', () async {
    final bounds = _path().getBounds().shift(_center);
    final x = (_center.dx + 37).round();
    final y = bounds.bottom.ceil() + 5;
    final alphas = <int>[];
    for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      alphas.add(_pixel(await _frame(progress), x, y)[3]);
    }
    expect(alphas.first, greaterThan(0));
    for (var index = 1; index < alphas.length; index++) {
      expect(alphas[index], lessThanOrEqualTo(alphas[index - 1]));
    }
    expect(alphas.last, 0);
  });

  test(
    'native outside-only shadows do not darken the translucent fill',
    () async {
      final opening = await _frame(0);
      final insideLowerDiagonal = _pixel(opening, 213, 155);
      expect(insideLowerDiagonal[2], inInclusiveRange(70, 110));
      // A blue source over transparency has equal blue and alpha channels. A
      // shadow under that translucent fill would add alpha without adding blue.
      expect(insideLowerDiagonal[3], insideLowerDiagonal[2]);
    },
  );

  test('blue stays the same hue while the gradient becomes opaque', () async {
    var previousAlpha = 0;
    for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final pixels = await _frame(progress);
      final lowerDiagonal = _pixel(pixels, 213, 155);
      final alpha = lowerDiagonal[3];
      expect(alpha, greaterThan(previousAlpha));
      previousAlpha = alpha;
      expect(lowerDiagonal[0], 0);
      expect(lowerDiagonal[2], closeTo(alpha, 1));
      expect(lowerDiagonal[1] * 255 / alpha, closeTo(26, 2));
      // The already-opaque top of the mark never changes colour or opacity.
      expect(_pixel(pixels, 216, 84), [0, 26, 255, 255]);
    }
    expect(previousAlpha, 255);
  });

  test('shadows remain inside the exported filter extent', () async {
    final opening = await _frame(0);
    final bounds = _path().getBounds().shift(_center);
    const scale = 160 / 705;
    final extent = Rect.fromLTRB(
      bounds.left - 30 * scale,
      bounds.top - 20 * scale,
      bounds.right + 30 * scale,
      bounds.bottom + 40 * scale,
    ).inflate(1);
    var leaked = false;
    for (var y = 0; y < _viewport.height; y++) {
      for (var x = 0; x < _viewport.width; x++) {
        if (extent.contains(Offset(x.toDouble(), y.toDouble()))) continue;
        if (_pixel(opening, x, y)[3] != 0) leaked = true;
      }
    }
    expect(leaked, isFalse);
  });

  test(
    'completed transition exactly matches the solid blue reveal mark',
    () async {
      final reference = await _raster((canvas) {
        canvas
          ..translate(_center.dx, _center.dy)
          ..drawPath(_path(), Paint()..color = _blue);
      });
      expect(await _frame(1), reference);
      // Off-range animation values still produce a clean, completed mark.
      expect(await _frame(2), reference);
    },
  );

  test(
    'opening matches the independently rasterized native Figma export',
    () async {
      // Reference: test/fixtures/branding/aster-launch-figma.svg, rendered by
      // librsvg through sharp into a 174×99 viewport with scale 160/705. The
      // fixture preserves its original filter graph and crispEdges export flag.
      const scale = 160 / 705;
      const size = Size(174, 99);
      final center = Offset(30 * scale + 80, (20 + 373 / 2) * scale);
      final path = _path();
      final actual = await _raster((canvas) {
        canvas.translate(center.dx, center.dy);
        AsterLaunchLogo.paint(
          canvas,
          path: path,
          logoBounds: path.getBounds(),
          blueColor: _blue,
          finalColor: _blue,
          colorProgress: 0,
        );
      }, size: size);
      final codec = await ui.instantiateImageCodec(
        File('test/goldens/splash/native-figma-mark-160.png').readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      addTearDown(codec.dispose);
      addTearDown(image.dispose);
      final reference = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(image.width, size.width);
      expect(image.height, size.height);
      var difference = 0;
      var samples = 0;
      var maximum = 0;
      var maximumAt = '';
      for (var y = 0; y < size.height; y++) {
        for (var x = 0; x < size.width; x++) {
          final point = Offset(x + 0.5, y + 0.5) - center;
          final membership = [
            path.contains(point),
            path.contains(point + const Offset(1.5, 0)),
            path.contains(point + const Offset(-1.5, 0)),
            path.contains(point + const Offset(0, 1.5)),
            path.contains(point + const Offset(0, -1.5)),
            path.contains(point + const Offset(1.5, 1.5)),
            path.contains(point + const Offset(-1.5, 1.5)),
            path.contains(point + const Offset(1.5, -1.5)),
            path.contains(point + const Offset(-1.5, -1.5)),
          ];
          // Native SVG requests crisp edges; Flutter retains smooth path edges.
          // Ignore only that narrow geometry boundary, not the shadow footprint
          // or gradient interior, when comparing independent raster engines.
          if (membership.any((value) => value != membership.first)) continue;
          final index = (y * size.width.toInt() + x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            final delta = (actual[index + channel] - reference[index + channel])
                .abs();
            difference += delta;
            if (delta > maximum) {
              maximum = delta;
              maximumAt =
                  '$x,$y c$channel actual=${actual[index + channel]} '
                  'reference=${reference[index + channel]}';
            }
            samples++;
          }
        }
      }
      expect(difference / samples, lessThan(1));
      expect(maximum, lessThanOrEqualTo(12), reason: maximumAt);
    },
  );

  test(
    'effect layers preserve canvas state and support an empty mark',
    () async {
      final pixels = await _raster((canvas) {
        AsterLaunchLogo.paint(
          canvas,
          path: Path(),
          logoBounds: Rect.zero,
          blueColor: _blue,
          finalColor: _blue,
          colorProgress: 0,
        );
        canvas.save();
        canvas.translate(_center.dx, _center.dy);
        final originalSaveCount = canvas.getSaveCount();
        AsterLaunchLogo.paint(
          canvas,
          path: _path(),
          logoBounds: _path().getBounds(),
          blueColor: _blue,
          finalColor: _blue,
          colorProgress: 0.5,
        );
        expect(canvas.getSaveCount(), originalSaveCount);
        canvas.restore();
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 10, 10),
          Paint()..color = Colors.red,
        );
      });
      expect(_pixel(pixels, 5, 5), [244, 67, 54, 255]);
    },
  );
}

Path _path() => AsterLogoGeometry.animatedPath(
  logoWidth: 160,
  horizontalWidth: 160,
  rotationProgress: 0,
  expansionProgress: 0,
);

Future<Uint8List> _frame(double progress) => _raster((canvas) {
  final path = _path();
  canvas.translate(_center.dx, _center.dy);
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

Future<Uint8List> _raster(
  void Function(Canvas canvas) paint, {
  Size size = _viewport,
}) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
