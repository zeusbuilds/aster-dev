import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../feedback/feedback.dart';
import '../theme/theme.dart';

/// Stable app-owned decimal keypad for exact monetary text entry.
class AsterNumericKeypad extends StatelessWidget {
  AsterNumericKeypad({
    super.key,
    required this.value,
    required ValueChanged<String> onChanged,
    required this.allowDecimal,
    this.enabled = true,
    this.maximumCharacters = 64,
  }) : _behavior = _NumericKeypadBehavior(onChanged),
       assert(maximumCharacters > 0);

  /// Inert keypad that reserves the same geometry as monetary input.
  const AsterNumericKeypad.loading({super.key})
    : value = '',
      allowDecimal = true,
      enabled = false,
      maximumCharacters = 64,
      _behavior = null;

  final String value;
  final bool allowDecimal;
  final bool enabled;
  final int maximumCharacters;
  final _NumericKeypadBehavior? _behavior;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final gap = metrics.keypadGap;
    final height = metrics.keypadButtonHeight * 4 + gap * 3;
    final keys = <_KeypadValue>[
      for (final digit in const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        _KeypadValue.digit(digit),
      const _KeypadValue.decimal(),
      const _KeypadValue.digit('0'),
      const _KeypadValue.delete(),
    ];

    final keypad = SizedBox(
      height: height,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: keys.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: metrics.keypadButtonHeight,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemBuilder: (context, index) {
          final keyValue = keys[index];
          final keyEnabled = _canActivate(keyValue);
          return _NumericKey(
            value: keyValue,
            enabled: keyEnabled,
            onPressed: () => _activate(keyValue),
            onLongPress: keyEnabled && keyValue.kind == _KeypadKind.delete
                ? () {
                    unawaited(
                      context.haptics.trigger(HapticIntent.lightImpact),
                    );
                    _behavior?.onChanged('');
                  }
                : null,
          );
        },
      ),
    );
    if (_behavior == null) return ExcludeSemantics(child: keypad);
    return keypad;
  }

  bool _canActivate(_KeypadValue keyValue) {
    if (!enabled || _behavior == null) return false;

    return switch (keyValue.kind) {
      _KeypadKind.digit =>
        value.length < maximumCharacters &&
            (value != '0' || keyValue.label != '0'),
      _KeypadKind.decimal =>
        allowDecimal &&
            !value.contains('.') &&
            value.length < maximumCharacters,
      _KeypadKind.delete => value.isNotEmpty,
    };
  }

  void _activate(_KeypadValue keyValue) {
    switch (keyValue.kind) {
      case _KeypadKind.digit:
        if (value.length >= maximumCharacters) return;
        final digit = keyValue.label!;
        if (value == '0') {
          if (digit != '0') _behavior?.onChanged(digit);
          return;
        }
        _behavior?.onChanged('$value$digit');
      case _KeypadKind.decimal:
        if (!allowDecimal || value.contains('.')) return;
        if (value.length >= maximumCharacters) return;
        _behavior?.onChanged(value.isEmpty ? '0.' : '$value.');
      case _KeypadKind.delete:
        if (value.isEmpty) return;
        _behavior?.onChanged(value.substring(0, value.length - 1));
    }
  }
}

final class _NumericKeypadBehavior {
  const _NumericKeypadBehavior(this.onChanged);

  final ValueChanged<String> onChanged;
}

enum _KeypadKind { digit, decimal, delete }

final class _KeypadValue {
  const _KeypadValue.digit(this.label) : kind = _KeypadKind.digit;
  const _KeypadValue.decimal() : kind = _KeypadKind.decimal, label = '.';
  const _KeypadValue.delete() : kind = _KeypadKind.delete, label = null;

  final _KeypadKind kind;
  final String? label;
}

final class _NumericKey extends StatelessWidget {
  const _NumericKey({
    required this.value,
    required this.enabled,
    required this.onPressed,
    required this.onLongPress,
  });

  final _KeypadValue value;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isDelete = value.kind == _KeypadKind.delete;
    final label = isDelete ? 'Delete digit' : value.label!;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(context.radii.input),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onPressed : null,
      onLongPress: enabled ? onLongPress : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled
            ? context.stateLayers.visible
            : context.stateLayers.disabled,
        child: Material(
          color: context.appColors.surfaceSubtle,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            onLongPress: enabled ? onLongPress : null,
            customBorder: shape,
            child: Center(
              child: isDelete
                  ? Icon(
                      MingCuteIcons.mgc_delete_back_line,
                      size: context.icons.md,
                      color: context.colorScheme.onSurface,
                    )
                  : Text(
                      value.label!,
                      style: context.type.keypadNumber.toNumeric(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
