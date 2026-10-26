import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentKey = ValueKey('confirmation-content');
const _openKey = ValueKey('open-confirmation');
const _lockBody =
    'Anyone using this device will be able to open Aster. '
    'Revealing your seed phrase and exporting keys will still '
    'require device authentication.';
const _deleteBody =
    'Remove “Everyday” and its wallet data from this device. '
    'Keep your seed phrase safe. A seed phrase alone cannot restore '
    'USDT or other RGB assets. '
    'Your other wallets will stay. Aster will open the next wallet.';

enum _CallerTheme { normal, buttonOnlyOverride, inheritedOverride }

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
  });

  for (final sample in [
    (title: 'Turn off App lock?', body: _lockBody, action: 'Turn off'),
    (title: 'Delete wallet?', body: _deleteBody, action: 'Delete'),
    (
      title: 'Delete wallet?',
      body: _deleteBody.replaceFirst(
        'assets. Your other wallets',
        'assets.\n\nYour other wallets',
      ),
      action: 'Delete',
    ),
  ].indexed) {
    for (final caller in _CallerTheme.values) {
      for (final viewport in [
        (size: const Size(440, 956), scale: 1.0),
        (size: const Size(320, 568), scale: 3.0),
      ]) {
        testWidgets('${sample.$2.title} content ${sample.$1}: '
            '${caller.name}, ${viewport.scale}× preserves the action gap', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final theme = AppTheme.light();
          final overridden = _buttonTheme(theme);
          final page = _DialogCaller(
            title: sample.$2.title,
            body: sample.$2.body,
            action: sample.$2.action,
            buttonTheme: caller == _CallerTheme.buttonOnlyOverride
                ? overridden
                : null,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: caller == _CallerTheme.inheritedOverride
                  ? Theme(data: overridden, child: page)
                  : page,
            ),
          );
          await tester.tap(find.byKey(_openKey));
          await tester.pumpAndSettle();

          final cancel = find.widgetWithText(CustomButton, 'Cancel');
          final confirm = find.widgetWithText(CustomButton, sample.$2.action);
          // At large text the body scrolls independently of the actions.
          // Measure its end after exposing it, not offscreen text bounds.
          final scroll = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          );
          await tester.drag(scroll, const Offset(0, -4000));
          await tester.pumpAndSettle();
          final content = tester.getRect(find.byKey(_contentKey));
          final firstAction = tester.getRect(cancel);
          final gap = firstAction.top - content.bottom;
          expect(gap, closeTo(40, 0.01));
          expect(
            firstAction.top,
            lessThanOrEqualTo(tester.getRect(confirm).top),
          );
          expect(
            DefaultTextStyle.of(tester.element(find.byKey(_contentKey)))
                .style
                .fontSize,
            16,
          );
          expect(tester.takeException(), isNull);
          if (caller == _CallerTheme.buttonOnlyOverride) {
            final context = tester.element(find.byType(AlertDialog));
            expect(context.spacing.xxl, 24);
            expect(context.metrics.buttonHeight, isNot(88));
          }
          // ignore: avoid_print
          print(
            '${sample.$2.title} ${sample.$1} ${caller.name} '
            '${viewport.scale}x measured content/actions gap=$gap',
          );
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        });
      }
    }
  }
}

ThemeData _buttonTheme(ThemeData original) {
  final spacing = original.extension<AsterSpacing>()!;
  final metrics = original.extension<AsterComponentMetrics>()!;
  return original.copyWith(
    extensions: [
      ...original.extensions.values.where(
        (extension) =>
            extension is! AsterSpacing && extension is! AsterComponentMetrics,
      ),
      spacing.copyWith(xxl: 2),
      metrics.copyWith(buttonHeight: 88),
    ],
  );
}

class _DialogCaller extends StatefulWidget {
  const _DialogCaller({
    required this.title,
    required this.body,
    required this.action,
    this.buttonTheme,
  });

  final String title;
  final String body;
  final String action;
  final ThemeData? buttonTheme;

  @override
  State<_DialogCaller> createState() => _DialogCallerState();
}

class _DialogCallerState extends State<_DialogCaller> {
  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      key: _openKey,
      onPressed: () => showDialog<void>(
        // Like both production callers, this is the State's context above
        // any button-only metrics override, not a descendant Builder context.
        context: this.context,
        builder: (context) => AsterConfirmationDialog(
          title: widget.title,
          content: Text(widget.body, key: _contentKey),
          confirmText: widget.action,
        ),
      ),
      child: const Text('Open'),
    );
    return Scaffold(
      body: Center(
        child: widget.buttonTheme != null
            ? Theme(data: widget.buttonTheme!, child: button)
            : button,
      ),
    );
  }
}
