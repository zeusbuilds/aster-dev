import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_design_system.dart';

void main() {
  late Directory repository;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('aster_design_system_');
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts semantic UI roles and reviewed coordinate math', () {
    _write(
      repository,
      'lib/features/pay/presentation/screens/pay_screen.dart',
      '''
Widget build(BuildContext context) {
  final center = Offset(size.width / 2, size.height / 2);
  return Padding(
    padding: EdgeInsets.all(context.spacing.lg),
    child: Text('Ready', style: context.type.statusMessage),
  );
}
''',
    );
    _write(repository, 'lib/shared/widgets/semantic_surface.dart', '''
Widget build(BuildContext context) => Squircle(
  borderRadius: context.radii.card,
  color: context.colorScheme.surface,
  child: SizedBox(height: context.metrics.buttonHeight),
);
''');
    _write(repository, 'lib/shared/widgets/coordinate_painter.dart', '''
class CoordinatePainter extends CustomPainter {
  void paint(Canvas canvas, Size size) {
    final opacity = size.width > 0 ? 1.0 : 0.0;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 2,
      height: size.height,
    );
  }
}
''');
    _write(
      repository,
      'lib/features/pay/presentation/models/visual_model.dart',
      'const rawDomainScale = 0.5;',
    );

    final result = verifyDesignSystem(repository);

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.sourceCount, 3);
  });

  test('rejects raw typography, color, effect, shape, and gradient APIs', () {
    _write(
      repository,
      'lib/features/pay/presentation/widgets/pay_tile.dart',
      '''
Widget build(BuildContext context) {
  final first = Text('Bad', style: context.textTheme.bodyMedium);
  final second = Text(
    'Worse',
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
  final color = const Color(0xFFFFFFFF).withOpacity(0.5);
  final channelColor = Color.fromARGB(255, 1, 2, 3);
  final faded = Colors.red.withValues(alpha: 0.5);
  final gradient = LinearGradient(colors: [color, faded]);
  final shadow = BoxShadow(color: color);
  final shape = RoundedRectangleBorder();
  final field = OutlineInputBorder();
  return ClipRRect(child: first);
}
''',
    );
    _write(repository, 'lib/core/bootstrap/bootstrap_surface.dart', '''
class BootstrapSurface extends StatelessWidget {
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.black, child: child);
  }
}
''');

    final result = verifyDesignSystem(repository);

    expect(result.passed, isFalse);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('use AsterTypeRoles instead of TextTheme'),
        contains('TextStyle must be supplied'),
        contains('fontSize must come from an AsterTypeRoles'),
        contains('fontWeight must come from an AsterTypeRoles'),
        contains('Color must be supplied'),
        contains('withOpacity is forbidden'),
        contains('Colors.* is forbidden'),
        contains('A raw alpha is forbidden'),
        contains('LinearGradient must be supplied'),
        contains('BoxShadow must be supplied'),
        contains('RoundedRectangleBorder must be supplied'),
        contains('OutlineInputBorder must be supplied'),
        contains('ClipRRect must be supplied'),
        contains('lib/core/bootstrap/bootstrap_surface.dart'),
      ]),
    );
  });

  test('rejects feature overrides of the global no-splash policy', () {
    _write(repository, 'lib/shared/widgets/local_ink.dart', '''
Widget build(BuildContext context) => InkWell(
  splashFactory: InkRipple.splashFactory,
  splashColor: context.colorScheme.primary,
  child: child,
);
''');
    expect(verifyDesignSystem(repository).failures, hasLength(2));
    expect(
      verifyDesignSystem(repository).failures,
      everyElement(contains('Tap ink policy belongs to AppTheme')),
    );
  });

  test('rejects raw geometry, opacity, motion, and legacy token access', () {
    _write(repository, 'lib/shared/screens/broken_screen.dart', '''
Widget build(BuildContext context) => AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeIn,
  padding: const EdgeInsets.all(12),
  width: 40,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(8),
  ),
  child: Opacity(
    opacity: 0.5,
    child: SizedBox(height: spacing.spacing20),
  ),
);
''');
    _write(repository, 'lib/shared/widgets/local_opacity.dart', '''
Widget build(BuildContext context) {
  final opacity = enabled ? 1.0 : context.stateLayers.disabled;
  return Opacity(opacity: opacity, child: child);
}
''');

    final result = verifyDesignSystem(repository);

    expect(result.passed, isFalse);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('duration must use a semantic'),
        contains('Curves.* must be replaced'),
        contains('EdgeInsets must use semantic spacing'),
        contains('width must use spacing'),
        contains('BorderRadius must use semantic spacing'),
        contains('opacity must use a semantic'),
        contains('Primitive token access spacing.spacing20'),
        contains('Local opacity values must use semantic'),
      ]),
    );
  });

  test('fails closed for missing roots and malformed owned UI', () {
    var result = verifyDesignSystem(repository);
    expect(result.passed, isFalse);
    expect(result.failures.single, contains('Missing lib directory'));

    _write(
      repository,
      'lib/features/pay/presentation/pages/broken_page.dart',
      "Widget build( => Text('broken');",
    );
    result = verifyDesignSystem(repository);

    expect(result.passed, isFalse);
    expect(result.failures, contains(contains('parse error:')));
  });
}

void _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${contents.trim()}\n');
}
