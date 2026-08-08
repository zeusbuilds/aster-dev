import 'package:flutter/material.dart';

/// The three window-inset coordinate spaces exposed by Flutter.
///
/// [safePadding] excludes areas currently obscured by [obscuredInsets], so its
/// bottom value becomes zero while the keyboard is open. [systemPadding]
/// describes persistent hardware/system insets and does not shrink for the
/// keyboard. [obscuredInsets] describes fully obscured regions such as the
/// software keyboard.
@immutable
final class AsterWindowInsets {
  const AsterWindowInsets({
    required this.safePadding,
    required this.systemPadding,
    required this.obscuredInsets,
  });

  factory AsterWindowInsets.of(BuildContext context) {
    return AsterWindowInsets(
      safePadding: MediaQuery.paddingOf(context),
      systemPadding: MediaQuery.viewPaddingOf(context),
      obscuredInsets: MediaQuery.viewInsetsOf(context),
    );
  }

  /// Insets that remain unobscured in the current viewport.
  final EdgeInsets safePadding;

  /// Persistent hardware/system insets, unaffected by the keyboard.
  final EdgeInsets systemPadding;

  /// Fully obscured areas, normally the software keyboard at the bottom.
  final EdgeInsets obscuredInsets;

  double get topSafe => safePadding.top;
  double get bottomSafe => safePadding.bottom;
  double get topSystem => systemPadding.top;
  double get bottomSystem => systemPadding.bottom;
  double get keyboard => obscuredInsets.bottom;
  bool get keyboardVisible => keyboard > 0;
}

extension AsterWindowInsetsContext on BuildContext {
  /// Current window insets with explicit safe/system/keyboard semantics.
  AsterWindowInsets get windowInsets => AsterWindowInsets.of(this);
}
