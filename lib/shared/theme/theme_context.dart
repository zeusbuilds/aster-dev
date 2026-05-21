import 'package:flutter/material.dart';

import 'tokens/tokens.dart';

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colorScheme => theme.colorScheme;

  AsterColors get appColors =>
      theme.extension<AsterColors>() ?? AsterColors.light;
  AsterSpacing get spacing =>
      theme.extension<AsterSpacing>() ?? const AsterSpacing();
  AsterRadii get radii => theme.extension<AsterRadii>() ?? const AsterRadii();
  AsterShadows get shadows =>
      theme.extension<AsterShadows>() ?? const AsterShadows();
  AsterTypography get typography =>
      theme.extension<AsterTypography>() ?? const AsterTypography();
  AsterComponentMetrics get metrics =>
      theme.extension<AsterComponentMetrics>() ?? const AsterComponentMetrics();
  AsterMotion get motion =>
      theme.extension<AsterMotion>() ?? const AsterMotion();
  AsterEffects get effects =>
      theme.extension<AsterEffects>() ?? const AsterEffects();
}
