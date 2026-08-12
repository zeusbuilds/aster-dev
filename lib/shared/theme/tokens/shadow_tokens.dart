import 'package:flutter/material.dart';

@immutable
class AsterShadows extends ThemeExtension<AsterShadows> {
  AsterShadows({
    List<BoxShadow> none = const [],
    List<BoxShadow> raised = const [
      BoxShadow(color: Color(0x1A00041C), offset: Offset(0, 8), blurRadius: 24),
    ],
    List<BoxShadow> sheet = const [
      BoxShadow(
        color: Color(0x2600041C),
        offset: Offset(0, -8),
        blurRadius: 32,
      ),
    ],
    List<BoxShadow> modal = const [
      BoxShadow(
        color: Color(0x3300041C),
        offset: Offset(0, 16),
        blurRadius: 48,
      ),
    ],
  }) : none = List<BoxShadow>.unmodifiable(none),
       raised = List<BoxShadow>.unmodifiable(raised),
       sheet = List<BoxShadow>.unmodifiable(sheet),
       modal = List<BoxShadow>.unmodifiable(modal);

  final List<BoxShadow> none;
  final List<BoxShadow> raised;
  final List<BoxShadow> sheet;
  final List<BoxShadow> modal;

  @override
  AsterShadows copyWith({
    List<BoxShadow>? none,
    List<BoxShadow>? raised,
    List<BoxShadow>? sheet,
    List<BoxShadow>? modal,
  }) {
    return AsterShadows(
      none: none ?? this.none,
      raised: raised ?? this.raised,
      sheet: sheet ?? this.sheet,
      modal: modal ?? this.modal,
    );
  }

  @override
  AsterShadows lerp(ThemeExtension<AsterShadows>? other, double t) {
    if (other is! AsterShadows) return this;
    return AsterShadows(
      none: BoxShadow.lerpList(none, other.none, t) ?? const [],
      raised: BoxShadow.lerpList(raised, other.raised, t) ?? const [],
      sheet: BoxShadow.lerpList(sheet, other.sheet, t) ?? const [],
      modal: BoxShadow.lerpList(modal, other.modal, t) ?? const [],
    );
  }
}
