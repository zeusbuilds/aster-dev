import 'dart:async';

import 'package:flutter/material.dart';

import '../feedback/feedback.dart';
import '../motion/motion.dart';
import '../theme/theme.dart';
import 'grid_loader.dart';

/// Visual variants supported by [CustomButton].
enum ButtonVariant { primary, secondary, translucent, tonal, neutral }

/// App button with stable loading geometry, keyboard support, and semantic
/// haptics.
class CustomButton extends StatefulWidget {
  const CustomButton({
    super.key,
    required this.text,
    this.prefixIcon,
    this.suffixIcon,
    this.onTap,
    this.variant = ButtonVariant.primary,
    this.enabled = true,
    this.loading = false,
    this.width,
    this.hapticIntent = HapticIntent.lightImpact,
  }) : _isCompact = false;

  /// Compact buttons are true capsules. They retain the minimum touch target
  /// while presenting a shorter visual control.
  const CustomButton.compact({
    super.key,
    required this.text,
    this.prefixIcon,
    this.suffixIcon,
    this.onTap,
    this.variant = ButtonVariant.primary,
    this.enabled = true,
    this.loading = false,
    this.width,
    this.hapticIntent = HapticIntent.lightImpact,
  }) : _isCompact = true;

  final String text;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onTap;
  final ButtonVariant variant;
  final bool enabled;
  final bool loading;
  final double? width;

  /// Tap feedback intent. Use `null` when the owning async flow emits one
  /// result haptic after success or failure instead of immediate tap feedback.
  final HapticIntent? hapticIntent;
  final bool _isCompact;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;
  bool _minimumPressElapsed = true;
  bool _releaseRequested = false;
  Timer? _minimumPressTimer;

  bool get _isInteractive =>
      !widget.loading && widget.enabled && widget.onTap != null;

  @override
  void didUpdateWidget(CustomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPressed && !_isInteractive && !_releaseRequested) {
      _resetPressedState(rebuild: false);
    }
  }

  @override
  void dispose() {
    _minimumPressTimer?.cancel();
    super.dispose();
  }

  void _handleHighlight(bool highlighted, Duration minimumPressedDuration) {
    if (highlighted) {
      _beginPress(minimumPressedDuration);
    } else {
      _requestPressRelease();
    }
  }

  void _beginPress(Duration minimumPressedDuration) {
    _minimumPressTimer?.cancel();
    _releaseRequested = false;
    _minimumPressElapsed = minimumPressedDuration <= Duration.zero;

    if (!_minimumPressElapsed) {
      _minimumPressTimer = Timer(minimumPressedDuration, () {
        _minimumPressTimer = null;
        _minimumPressElapsed = true;
        if (_releaseRequested) _resetPressedState();
      });
    }

    if (!_isPressed) setState(() => _isPressed = true);
  }

  void _requestPressRelease() {
    if (!_isPressed || _releaseRequested) return;
    _releaseRequested = true;
    if (_minimumPressElapsed) _resetPressedState();
  }

  void _resetPressedState({bool rebuild = true}) {
    _minimumPressTimer?.cancel();
    _minimumPressTimer = null;
    _minimumPressElapsed = true;
    _releaseRequested = false;
    if (!_isPressed) return;
    if (rebuild && mounted) {
      setState(() => _isPressed = false);
    } else {
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final metrics = context.metrics;
    final motion = context.motion;
    final stateLayers = context.stateLayers;
    final isCompact = widget._isCompact;
    final visualHeight = isCompact
        ? metrics.compactButtonHeight
        : metrics.buttonHeight;
    final tapTargetHeight = visualHeight < metrics.minTouchTarget
        ? metrics.minTouchTarget
        : visualHeight;
    final buttonWidth = widget.width ?? (isCompact ? null : double.infinity);
    final foregroundColor = switch (widget.variant) {
      ButtonVariant.primary => context.colorScheme.onPrimary,
      ButtonVariant.tonal => context.colorScheme.primary,
      ButtonVariant.neutral => context.colorScheme.surface,
      _ => context.colorScheme.onSurface,
    };
    final loadingColor = switch (widget.variant) {
      ButtonVariant.translucent => context.colorScheme.primary,
      _ => foregroundColor,
    };
    final backgroundColor = switch (widget.variant) {
      ButtonVariant.primary => context.colorScheme.primary,
      ButtonVariant.secondary => context.colorScheme.surface,
      ButtonVariant.tonal => context.colorScheme.primaryContainer,
      ButtonVariant.neutral => context.colorScheme.onSurface,
      ButtonVariant.translucent => context.colorScheme.surface.withValues(
        alpha: stateLayers.translucentSurface,
      ),
    };
    final side = widget.variant == ButtonVariant.secondary
        ? BorderSide(color: colors.borderSubtle, width: context.strokes.border)
        : BorderSide.none;
    final OutlinedBorder shape = isCompact
        ? StadiumBorder(side: side)
        : RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(context.radii.button),
            side: side,
          );
    final isEnabled = _isInteractive;
    final opacity = widget.loading || isEnabled
        ? stateLayers.visible
        : stateLayers.disabled;
    final effectiveDuration = context.motionPolicy.duration(
      motion.buttonPressDuration,
    );
    final minimumPressedDuration = context.motionPolicy.duration(
      motion.buttonMinimumPressedDuration,
    );

    void activate() {
      // InkWell normally clears its highlight before invoking onTap. This
      // idempotent fallback queues release before an action can rebuild the
      // button into a loading or disabled state.
      _requestPressRelease();
      if (widget.hapticIntent case final intent?) {
        unawaited(context.haptics.trigger(intent));
      }
      widget.onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.text,
      value: widget.loading ? 'Loading' : null,
      liveRegion: widget.loading,
      onTap: isEnabled ? activate : null,
      excludeSemantics: true,
      // The compact visual remains 40 high; its surrounding target is also
      // tappable. The inner InkWell wins for taps inside the painted control.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: isCompact && isEnabled ? activate : null,
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            width: buttonWidth,
            height: tapTargetHeight,
            child: Center(
              widthFactor: isCompact && buttonWidth == null ? 1 : null,
              child: AnimatedScale(
                scale: _isPressed ? motion.buttonPressedScale : 1,
                duration: effectiveDuration,
                curve: motion.fastEase,
                child: SizedBox(
                  width: buttonWidth,
                  height: visualHeight,
                  child: Material(
                    color: backgroundColor,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: isEnabled ? activate : null,
                      onHighlightChanged: isEnabled
                          ? (highlighted) => _handleHighlight(
                              highlighted,
                              minimumPressedDuration,
                            )
                          : null,
                      customBorder: shape,
                      overlayColor: stateLayers.interactionOverlay(
                        foregroundColor,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? spacing.md : spacing.xxl,
                        ),
                        child: Center(
                          widthFactor: isCompact && buttonWidth == null
                              ? 1
                              : null,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Visibility(
                                visible: !widget.loading,
                                maintainState: true,
                                maintainAnimation: true,
                                maintainSize: true,
                                child: Row(
                                  mainAxisSize: isCompact
                                      ? MainAxisSize.min
                                      : MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (widget.prefixIcon case final icon?) ...[
                                      Icon(
                                        icon,
                                        size: context.icons.sm,
                                        color: foregroundColor,
                                      ),
                                      SizedBox(
                                        width: isCompact
                                            ? spacing.xs
                                            : spacing.sm,
                                      ),
                                    ],
                                    Flexible(
                                      child: Text(
                                        widget.text,
                                        style:
                                            (isCompact
                                                    ? context
                                                          .type
                                                          .compactButtonLabel
                                                    : context.type.buttonLabel)
                                                .copyWith(
                                                  color: foregroundColor,
                                                ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (widget.suffixIcon case final icon?) ...[
                                      SizedBox(
                                        width: isCompact
                                            ? spacing.xs
                                            : spacing.sm,
                                      ),
                                      Icon(
                                        icon,
                                        size: context.icons.sm,
                                        color: foregroundColor,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (widget.loading)
                                Positioned.fill(
                                  child: Center(
                                    child: GridLoader(
                                      colorStyle: GridLoaderColorStyle.custom,
                                      color: loadingColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
