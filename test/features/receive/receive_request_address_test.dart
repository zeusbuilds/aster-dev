import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('DM Sans')
      ..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'));
    await font.load();
  });

  const request =
      'rgb:~/~/~/bcrt:wvout:BQ3yP05I-p2duwdw-TLstK3Z-0zRVioV-Xzr9OKW-'
      'YaHPwiC-etOPjqQ?expiry=1792921873&endpoints=rpc://127.0.0.1:29300/json-rpc';

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('middle truncation fits two lines at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 240,
                  child: ReceiveRequestAddress(value: request),
                ),
              ),
            ),
          ),
        ),
      );
      final text = find.descendant(
        of: find.byType(ReceiveRequestAddress),
        matching: find.byType(Text),
      );
      final display = tester.widget<Text>(text);
      final visibleLines = display.data!.split('\n');
      expect(visibleLines, hasLength(2));
      expect(visibleLines.first, endsWith('......'));
      expect(visibleLines.last, startsWith('......'));
      final prefix = visibleLines.first.substring(
        0,
        visibleLines.first.length - 6,
      );
      final suffix = visibleLines.last.substring(6);
      expect(prefix, isNotEmpty);
      expect(suffix, isNotEmpty);
      expect(request, startsWith(prefix));
      expect(request, endsWith(suffix));
      expect(display.semanticsLabel, request);
      expect(display.textDirection, TextDirection.ltr);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: display.data!.length),
          )
          .map((box) => box.top)
          .toSet();
      expect(lines, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a short request stays complete', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Center(
          child: SizedBox(
            width: 300,
            child: ReceiveRequestAddress(value: 'rgb:short-request'),
          ),
        ),
      ),
    );
    expect(find.text('rgb:short-request'), findsOneWidget);
    expect(find.textContaining('…'), findsNothing);
  });
}
