import 'package:flutter/material.dart';

import '../theme/theme.dart';

class NumericText extends StatelessWidget {
  const NumericText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style?.toNumeric(context),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class AmountText extends StatelessWidget {
  const AmountText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: NumericTextSpans.build(context, text, style)),
      style: style,
      textAlign: textAlign ?? TextAlign.start,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class NumericTextSpans {
  NumericTextSpans._();

  static final RegExp _numericChunk = RegExp(r'[+\-]?\$?\d[\d,._:/]*%?');

  static List<TextSpan> build(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _numericChunk.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: style),
        );
      }

      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: style?.toNumeric(context),
        ),
      );
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }

    return spans;
  }
}
