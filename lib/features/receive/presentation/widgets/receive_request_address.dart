import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// A compact RGB request preview. The underlying request is never shortened.
final class ReceiveRequestAddress extends StatelessWidget {
  const ReceiveRequestAddress({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(context.type.addressSmall);
    return LayoutBuilder(
      builder: (context, constraints) {
        final characters = value.characters.toList();
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 2,
        );
        bool fits(String text) {
          painter.text = TextSpan(text: text, style: style);
          painter.layout(maxWidth: constraints.maxWidth);
          return !painter.didExceedMaxLines &&
              painter.width <= constraints.maxWidth;
        }

        String shortened(int count) {
          final prefix = (count + 1) ~/ 2;
          final suffix = count ~/ 2;
          return '${characters.take(prefix).join()}......\n'
              '......${characters.skip(characters.length - suffix).join()}';
        }

        var display = value;
        try {
          if (!fits(value)) {
            var low = 0;
            var high = characters.length - 1;
            while (low < high) {
              final middle = (low + high + 1) ~/ 2;
              if (fits(shortened(middle))) {
                low = middle;
              } else {
                high = middle - 1;
              }
            }
            display = shortened(low);
          }
        } finally {
          painter.dispose();
        }
        return Text(
          display,
          semanticsLabel: value,
          style: style,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.clip,
        );
      },
    );
  }
}
