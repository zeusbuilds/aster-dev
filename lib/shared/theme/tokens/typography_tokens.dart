import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'typography_tokens.freezed.dart';

/// Typography tokens configuration - Base design tokens
@freezed
class TypographyTokens with _$TypographyTokens {
  const factory TypographyTokens({
    @Default('DM Sans') String fontFamilyPrimary,
    @Default('DM Mono') String fontFamilyMonospace,
    @Default('Public Sans') String fontFamilyNumeric,

    @Default(FontWeight.w100) FontWeight weightThin,
    @Default(FontWeight.w200) FontWeight weightExtraLight,
    @Default(FontWeight.w300) FontWeight weightLight,
    @Default(FontWeight.w400) FontWeight weightRegular,
    @Default(FontWeight.w500) FontWeight weightMedium,
    @Default(FontWeight.w600) FontWeight weightSemiBold,
    @Default(FontWeight.w700) FontWeight weightBold,
    @Default(FontWeight.w800) FontWeight weightExtraBold,
    @Default(FontWeight.w900) FontWeight weightBlack,

    @Default(6.0) double size6,
    @Default(8.0) double size8,
    @Default(10.0) double size10,
    @Default(12.0) double size12,
    @Default(14.0) double size14,
    @Default(16.0) double size16,
    @Default(18.0) double size18,
    @Default(20.0) double size20,
    @Default(22.0) double size22,
    @Default(24.0) double size24,
    @Default(26.0) double size26,
    @Default(28.0) double size28,
    @Default(30.0) double size30,
    @Default(32.0) double size32,
    @Default(34.0) double size34,
    @Default(36.0) double size36,
    @Default(38.0) double size38,
    @Default(40.0) double size40,
    @Default(42.0) double size42,
    @Default(44.0) double size44,
    @Default(46.0) double size46,
    @Default(48.0) double size48,
    @Default(50.0) double size50,
    @Default(52.0) double size52,
    @Default(54.0) double size54,
    @Default(56.0) double size56,

    @Default(1.0) double lineHeightTight,
    @Default(1.2) double lineHeightSnug,
    @Default(1.4) double lineHeightNormal,
    @Default(1.5) double lineHeightRelaxed,
    @Default(1.6) double lineHeightLoose,

    @Default(-0.025) double letterSpacingTight,
    @Default(0.0) double letterSpacingNormal,
    @Default(0.05) double letterSpacingWide,
    @Default(0.1) double letterSpacingWider,
    @Default(0.15) double letterSpacingWidest,
  }) = _TypographyTokens;
}
