import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Semantic emphasis for persistent inline status copy.
enum AsterStatusTone {
  /// Informational or neutral state.
  neutral,

  /// A caution that does not mean the operation failed.
  warning,

  /// A failed operation or invalid state.
  danger,

  /// A confirmed successful state.
  success,
}

/// Persistent status copy with one explicit accessibility owner.
///
/// Set [announce] only for a state transition that occurred after the surface
/// was presented, such as an asynchronous failure or timer expiry. Ordinary
/// validation remains readable in traversal without announcing on every
/// keystroke.
class AsterStatusMessage extends StatelessWidget {
  const AsterStatusMessage(
    this.message, {
    super.key,
    this.tone = AsterStatusTone.neutral,
    this.announce = false,
    this.textAlign = TextAlign.center,
    this.maxLines,
  });

  /// User-safe status text. Sensitive diagnostics must never be passed here.
  final String message;

  /// Semantic visual treatment rather than a caller-owned color.
  final AsterStatusTone tone;

  /// Whether assistive technology should announce this state change live.
  final bool announce;

  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final style = switch (tone) {
      AsterStatusTone.neutral => context.type.statusMessage,
      AsterStatusTone.warning => context.type.errorMessage.copyWith(
        color: context.appColors.statusForeground,
      ),
      AsterStatusTone.danger => context.type.errorMessage.copyWith(
        color: context.appColors.statusForeground,
      ),
      AsterStatusTone.success => context.type.statusMessage.copyWith(
        color: context.appColors.statusForeground,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: announce,
      label: message,
      excludeSemantics: true,
      child: Text(
        message,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}
