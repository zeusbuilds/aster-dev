import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks plain text painted directly over a separately rendered backdrop.
///
/// Flutter's histogram guideline can mistake two mesh colors for foreground
/// and background. This instead composites the resolved text color over every
/// pixel beneath its bounds and requires the worst contrast to meet WCAG AA.
/// The backdrop must exclude foreground content and intervening surfaces.
/// Other labels retain Flutter's normal semantics-based contrast checks.
final class BackdropTextContrastGuideline extends AccessibilityGuideline {
  const BackdropTextContrastGuideline({
    required this.backdrop,
    required this.labels,
    required this.underlay,
  });

  final Finder backdrop;
  final Set<String> labels;
  final Color underlay;

  @override
  String get description => 'Text meets WCAG AA over every backdrop pixel';

  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    final visible = <String, Finder>{
      for (final label in labels)
        if (find.text(label).hitTestable().evaluate().isNotEmpty)
          label: find.text(label).hitTestable(),
    };
    if (visible.isEmpty) return textContrastGuideline.evaluate(tester);
    if (underlay.a != 1 || backdrop.evaluate().length != 1) {
      return const Evaluation.fail('Requires one backdrop and opaque underlay');
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(backdrop);
    var result = const Evaluation.pass();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        for (final entry in visible.entries) {
          for (final element in entry.value.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final span = paragraph.text as TextSpan;
            final style = span.style!;
            final foreground = style.color;
            if (foreground == null ||
                style.foreground != null ||
                span.children?.isNotEmpty == true) {
              result += Evaluation.fail('${entry.key}: requires uniform text');
              continue;
            }
            final bounds = Rect.fromPoints(
              boundary.globalToLocal(paragraph.localToGlobal(Offset.zero)),
              boundary.globalToLocal(
                paragraph.localToGlobal(
                  paragraph.size.bottomRight(Offset.zero),
                ),
              ),
            ).intersect(Offset.zero & boundary.size);
            if (bounds.isEmpty) {
              result += Evaluation.fail('${entry.key}: no backdrop pixels');
              continue;
            }
            var minimum = double.infinity;
            for (var y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
              for (var x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
                final offset = (y * image.width + x) * 4;
                final background = Color.alphaBlend(
                  Color.fromARGB(
                    pixels.getUint8(offset + 3),
                    pixels.getUint8(offset),
                    pixels.getUint8(offset + 1),
                    pixels.getUint8(offset + 2),
                  ),
                  underlay,
                );
                final ink = Color.alphaBlend(foreground, background);
                final a = ink.computeLuminance();
                final b = background.computeLuminance();
                minimum = math.min(
                  minimum,
                  (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05),
                );
              }
            }
            // 4.5 also covers large text; there is no reduced threshold here.
            if (minimum < 4.5) {
              result += Evaluation.fail(
                '${entry.key}: minimum backdrop contrast '
                '${minimum.toStringAsFixed(2)} is below 4.5',
              );
            }
          }
        }
      } finally {
        image.dispose();
      }
    });
    return result +
        await _RemainingTextContrastGuideline(visible.keys.toSet())
            .evaluate(tester);
  }
}

final class _RemainingTextContrastGuideline
    extends MinimumTextContrastGuideline {
  const _RemainingTextContrastGuideline(this.measuredLabels);

  final Set<String> measuredLabels;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      measuredLabels.contains(data.label) || super.shouldSkipNode(data);
}
