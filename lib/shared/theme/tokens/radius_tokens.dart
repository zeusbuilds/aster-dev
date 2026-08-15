import 'package:flutter/material.dart';

@immutable
class AsterRadii extends ThemeExtension<AsterRadii> {
  const AsterRadii({
    this.card = 24,
    this.sheet = 28,
    this.button = 18,
    this.input = 12,
    this.badge = 8,
    this.checkbox = 4,
    this.snackbar = 12,
    this.floatingActionButton = 16,
  });

  final double card;
  final double sheet;
  final double button;
  final double input;
  final double badge;
  final double checkbox;
  final double snackbar;
  final double floatingActionButton;

  @override
  AsterRadii copyWith({
    double? card,
    double? sheet,
    double? button,
    double? input,
    double? badge,
    double? checkbox,
    double? snackbar,
    double? floatingActionButton,
  }) {
    return AsterRadii(
      card: card ?? this.card,
      sheet: sheet ?? this.sheet,
      button: button ?? this.button,
      input: input ?? this.input,
      badge: badge ?? this.badge,
      checkbox: checkbox ?? this.checkbox,
      snackbar: snackbar ?? this.snackbar,
      floatingActionButton: floatingActionButton ?? this.floatingActionButton,
    );
  }

  @override
  AsterRadii lerp(ThemeExtension<AsterRadii>? other, double t) {
    if (other is! AsterRadii) return this;
    return AsterRadii(
      card: _lerp(card, other.card, t),
      sheet: _lerp(sheet, other.sheet, t),
      button: _lerp(button, other.button, t),
      input: _lerp(input, other.input, t),
      badge: _lerp(badge, other.badge, t),
      checkbox: _lerp(checkbox, other.checkbox, t),
      snackbar: _lerp(snackbar, other.snackbar, t),
      floatingActionButton: _lerp(
        floatingActionButton,
        other.floatingActionButton,
        t,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
