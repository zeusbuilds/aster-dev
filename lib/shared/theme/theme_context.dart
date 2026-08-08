import 'package:flutter/material.dart';

import 'tokens/tokens.dart';

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colorScheme => theme.colorScheme;

  AsterColors get appColors => _requireExtension<AsterColors>();
  AsterSpacing get spacing => _requireExtension<AsterSpacing>();
  AsterRadii get radii => _requireExtension<AsterRadii>();
  AsterShadows get shadows => _requireExtension<AsterShadows>();
  AsterTypography get typography => _requireExtension<AsterTypography>();
  AsterComponentMetrics get metrics =>
      _requireExtension<AsterComponentMetrics>();
  AsterMotion get motion => _requireExtension<AsterMotion>();
  AsterEffects get effects => _requireExtension<AsterEffects>();
  AsterIconography get icons => _requireExtension<AsterIconography>();
  AsterStrokes get strokes => _requireExtension<AsterStrokes>();
  AsterStateLayers get stateLayers => _requireExtension<AsterStateLayers>();
  AsterGradients get gradients => _requireExtension<AsterGradients>();
  AsterArt get art => _requireExtension<AsterArt>();
  AsterTypeRoles get type => _requireExtension<AsterTypeRoles>();

  T _requireExtension<T extends ThemeExtension<T>>() {
    final extension = theme.extension<T>();
    if (extension == null) {
      throw FlutterError(
        'Missing $T in ThemeData.extensions. Use AppTheme.light() at every '
        'application and widget-test root.',
      );
    }
    return extension;
  }
}
