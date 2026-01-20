import 'package:flutter/material.dart';

import 'package:easy_radio/easy_radio.dart';

import 'package:aster/shared/shared.dart';

/// Custom radio button widget with consistent styling
///
/// Provides a radio button with theme-aware colors and animations.
///
/// Supports selection state management through [option] and [selected] values.
class CustomRadio extends StatefulWidget {
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
  State<CustomRadio> createState() => _CustomRadioState();
}

class _CustomRadioState extends State<CustomRadio> {
  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;

    return EasyRadio<int>(
      value: widget.option,
      groupValue: widget.selected,
      onChanged: (value) => widget.onChanged(value),
      activeFillColor: colors.brand6,
      activeBorderColor: colors.brand6,
      inactiveBorderColor: colors.fill3,
      inactiveFillColor: colors.fill1,
      dotColor: colors.fill1,
      dotRadius: spacing.spacing8,
      radius: spacing.spacing8,
      animateFillColor: true,
      toggleable: true,
      dotStyle: const DotStyle.check(),
    );
  }
}
