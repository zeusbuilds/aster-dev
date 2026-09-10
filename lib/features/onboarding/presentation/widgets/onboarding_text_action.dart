import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/shared.dart';

/// Unframed icon/text action with tap, keyboard, and screen-reader activation.
///
/// No Material button or ink layer is created. Keyboard focus is indicated by
/// an underline; loading keeps the label's footprint and blocks every input.
class OnboardingTextAction extends StatefulWidget {
  const OnboardingTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.onBrandArt = false,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Preserves the label's geometry and blocks activation during the operation.
  final bool loading;
  final bool enabled;
  final bool onBrandArt;
  final HapticIntent? hapticIntent;

  @override
  State<OnboardingTextAction> createState() => _OnboardingTextActionState();
}

class _OnboardingTextActionState extends State<OnboardingTextAction> {
  bool _focused = false;
  bool _showFocusHighlight = false;

  bool get _interactive => widget.enabled && !widget.loading;

  void _activate() {
    if (!_interactive) return;
    if (widget.hapticIntent case final intent?) {
      unawaited(context.haptics.trigger(intent));
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.onBrandArt
        ? context.appColors.onBrandArt
        : context.colorScheme.onSurface;
    final color = _interactive || widget.loading
        ? foreground
        : foreground.withValues(alpha: context.stateLayers.disabled);

    return Semantics(
      button: true,
      enabled: _interactive,
      focusable: _interactive,
      focused: _interactive && _focused,
      label: widget.label,
      value: widget.loading ? 'Loading' : null,
      liveRegion: widget.loading,
      excludeSemantics: true,
      onTap: _interactive ? _activate : null,
      child: FocusableActionDetector(
        enabled: _interactive,
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onShowFocusHighlight: (show) =>
            setState(() => _showFocusHighlight = show),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _interactive ? _activate : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: context.metrics.minTouchTarget,
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Visibility(
                      visible: !widget.loading,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon case final value?) ...[
                            Icon(value, size: context.icons.sm, color: color),
                            SizedBox(width: context.spacing.sm),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              style: context.type.brandAction.copyWith(
                                color: color,
                                decoration: _interactive && _showFocusHighlight
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                                decorationColor: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.loading)
                      GridLoader(
                        colorStyle: GridLoaderColorStyle.custom,
                        color: color,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
