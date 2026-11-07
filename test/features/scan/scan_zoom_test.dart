import 'package:aster/features/scan/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'common hardware cycles real magnifications without using maximum as 3x',
    () {
      const zoom = ScanZoomRange(minimum: 1, maximum: 12, current: 1);
      expect(zoom.presets, [1, 2, 3]);
      expect(zoom.nextRatio, 2);
      expect(zoom.displayLabel, '1x');
      expect(zoom.semanticLabel, 'Zoom 1 times');
      expect(
        const ScanZoomRange(minimum: 1, maximum: 12, current: 3).nextRatio,
        1,
      );
    },
  );

  test(
    'hardware with a smaller maximum never receives an unsupported preset',
    () {
      const zoom = ScanZoomRange(minimum: 1, maximum: 2, current: 2);
      expect(zoom.presets, [1, 2]);
      expect(zoom.nextRatio, 1);
      const constrained = ScanZoomRange(minimum: 1, maximum: 1.5, current: 1);
      expect(constrained.presets, [1, 1.5]);
      expect(constrained.nextRatio, 1.5);
      expect(constrained.canChange, isTrue);
    },
  );

  test('a camera without zoom retains a truthful disabled 1x value', () {
    const zoom = ScanZoomRange(minimum: 1, maximum: 1, current: 1);
    expect(zoom.presets, [1]);
    expect(zoom.canChange, isFalse);
  });

  test('float precision at hardware bounds does not hide available zoom', () {
    const zoom = ScanZoomRange(minimum: 1, maximum: 3, current: 0.99999994);
    expect(zoom.isValid, isTrue);
    expect(zoom.displayLabel, '1x');
    expect(zoom.canChange, isTrue);
    expect(zoom.nextRatio, 2);
  });

  test('hardware readback is formatted rather than replaced by a preset', () {
    const zoom = ScanZoomRange(minimum: 0.5, maximum: 5, current: 1.75);
    expect(zoom.displayLabel, '1.75x');
    expect(zoom.semanticLabel, 'Zoom 1.75 times');
    expect(zoom.nextRatio, 2);
    expect(
      const ScanZoomRange(
        minimum: 1,
        maximum: 5,
        current: 1.9999999,
      ).displayLabel,
      '2x',
    );
    expect(
      const ScanZoomRange(minimum: 1, maximum: 12, current: 10).displayLabel,
      '10x',
    );
  });

  test('invalid capability data cannot enable a zoom command', () {
    for (final zoom in const [
      ScanZoomRange(minimum: 0, maximum: 3, current: 1),
      ScanZoomRange(minimum: 3, maximum: 1, current: 2),
      ScanZoomRange(minimum: 1, maximum: 3, current: 4),
      ScanZoomRange(minimum: 1, maximum: double.infinity, current: 1),
      ScanZoomRange(minimum: 1, maximum: 3, current: double.nan),
    ]) {
      expect(zoom.isValid, isFalse);
      expect(zoom.canChange, isFalse);
      expect(zoom.presets, isEmpty);
    }
  });
}
