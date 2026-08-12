import 'package:easy_radio/easy_radio.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Custom radio button widget with consistent styling
///
/// Provides a radio button with theme-aware colors and animations.
///
/// Supports selection state management through [option] and [selected] values.
class CustomRadio<T> extends StatelessWidget {
  final T option;
  final T? selected;
  final ValueChanged<T?>? onChanged;

  const CustomRadio({
    super.key,
    this.onChanged,
    required this.option,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final radii = context.radii;

    return EasyRadio<T>(
      value: option,
      groupValue: selected,
      onChanged: onChanged,
      activeFillColor: context.colorScheme.primary,
      activeBorderColor: context.colorScheme.primary,
      inactiveBorderColor: context.colorScheme.surfaceContainerHigh,
      inactiveFillColor: context.colorScheme.surface,
      dotColor: context.colorScheme.surface,
      dotRadius: radii.sm,
      radius: radii.sm,
      animateFillColor: true,
      toggleable: true,
      dotStyle: const DotStyle.check(),
    );
  }
}
