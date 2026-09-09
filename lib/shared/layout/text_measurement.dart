import 'package:flutter/widgets.dart';

/// Measures one unwrapped label in logical pixels using the active locale,
/// direction and accessibility text scaling. Used to reflow rather than shrink
/// text; the temporary paragraph is disposed synchronously.
double unwrappedTextWidth(BuildContext context, String text, TextStyle style) {
  return unwrappedSpanWidth(context, TextSpan(text: text, style: style));
}

/// Same layout contract as [unwrappedTextWidth], including mixed-font spans.
double unwrappedSpanWidth(BuildContext context, InlineSpan span) {
  final painter = TextPainter(
    text: span,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  );
  try {
    painter.layout();
    return painter.width;
  } finally {
    painter.dispose();
  }
}
