import 'package:flutter/material.dart';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'shadow_tokens.freezed.dart';

/// Shadow tokens configuration
@freezed
class ShadowTokens with _$ShadowTokens {
  const factory ShadowTokens({
    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow1,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow2,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 4),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow4,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 6),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow6,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 8),
        blurRadius: 16,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow8,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 12),
        blurRadius: 24,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow12,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 16),
        blurRadius: 32,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow16,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 20),
        blurRadius: 40,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow20,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 24),
        blurRadius: 48,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadow24,

    @Default([
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, 1),
        blurRadius: 3,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Color(0x0A000000),
        offset: Offset(0, 1),
        blurRadius: 1,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowCard,

    @Default([
      BoxShadow(
        color: Color(0x1A000000),
        offset: Offset(0, 2),
        blurRadius: 8,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 1),
        blurRadius: 3,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowCardHover,

    @Default([
      BoxShadow(
        color: Color(0x1F000000),
        offset: Offset(0, 4),
        blurRadius: 16,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, 2),
        blurRadius: 6,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowModal,

    @Default([
      BoxShadow(
        color: Color(0x33000000),
        offset: Offset(0, 8),
        blurRadius: 32,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Color(0x1A000000),
        offset: Offset(0, 4),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowDialog,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowButton,

    @Default([
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowButtonHover,

    @Default([
      BoxShadow(
        color: Color(0x1A000000),
        offset: Offset(0, 4),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowButtonPressed,

    @Default([
      BoxShadow(
        color: Color(0x0A000000),
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowInput,

    @Default([
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowInputFocus,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, -1),
        blurRadius: 2,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowTop,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowBottom,

    @Default([
      BoxShadow(
        color: Color(0x1A000000),
        offset: Offset(-2, 0),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowLeft,

    @Default([
      BoxShadow(
        color: Color(0x1A000000),
        offset: Offset(2, 0),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowRight,

    @Default([
      BoxShadow(
        color: Color(0x0D000000),
        offset: Offset(0, 0),
        blurRadius: 4,
        spreadRadius: 0,
      ),
    ])
    List<BoxShadow> shadowInner,
  }) = _ShadowTokens;
}
