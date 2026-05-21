import 'package:flutter/material.dart';

import 'package:easy_radio/easy_radio.dart';

import '../theme/theme.dart';

/// Custom radio button widget with consistent styling
///
/// Provides a radio button with theme-aware colors and animations.
///
/// Supports selection state management through [option] and [selected] values.
class CustomRadio extends StatelessWidget {
  final int option;
  final int selected;
  final void Function(int?) onChanged;

  const CustomRadio({
    super.key,
    required this.onChanged,
    required this.option,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return EasyRadio<int>(
      value: option,
      groupValue: selected,
      onChanged: onChanged,
      activeFillColor: context.colorScheme.primary,
      activeBorderColor: context.colorScheme.primary,
      inactiveBorderColor: context.colorScheme.surfaceContainerHigh,
      inactiveFillColor: context.colorScheme.surface,
      dotColor: context.colorScheme.surface,
      dotRadius: spacing.sm,
      radius: spacing.sm,
      animateFillColor: true,
      toggleable: true,
      dotStyle: const DotStyle.check(),
    );
  }
}
