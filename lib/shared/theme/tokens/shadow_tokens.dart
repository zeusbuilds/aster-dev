import 'package:flutter/material.dart';

@immutable
class AsterShadows extends ThemeExtension<AsterShadows> {
  const AsterShadows({
    this.none = const [],
    this.raised = const [
      BoxShadow(color: Color(0x1A00041C), offset: Offset(0, 8), blurRadius: 24),
    ],
    this.sheet = const [
      BoxShadow(
        color: Color(0x2600041C),
        offset: Offset(0, -8),
        blurRadius: 32,
      ),
    ],
    this.modal = const [
      BoxShadow(
        color: Color(0x3300041C),
        offset: Offset(0, 16),
        blurRadius: 48,
      ),
    ],
  });

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
      none: none,
      raised: _lerpShadowList(raised, other.raised, t),
      sheet: _lerpShadowList(sheet, other.sheet, t),
      modal: _lerpShadowList(modal, other.modal, t),
    );
  }

  static List<BoxShadow> _lerpShadowList(
    List<BoxShadow> a,
    List<BoxShadow> b,
    double t,
  ) {
    final length = a.length < b.length ? a.length : b.length;
    return List<BoxShadow>.generate(
      length,
      (i) => BoxShadow.lerp(a[i], b[i], t)!,
    );
  }
}
