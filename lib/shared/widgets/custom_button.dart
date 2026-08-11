import 'dart:async';

import 'package:flutter/material.dart';

import '../feedback/feedback.dart';
import '../motion/motion.dart';
import '../theme/theme.dart';
import 'grid_loader.dart';

/// Visual variants supported by [CustomButton].
enum ButtonVariant { primary, secondary, translucent }

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

  void _handleHighlight(bool highlighted) {
    if (_isPressed == highlighted) return;
    setState(() => _isPressed = highlighted);
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
    final foregroundColor = widget.variant == ButtonVariant.primary
        ? context.colorScheme.onPrimary
        : context.colorScheme.onSurface;
    final backgroundColor = switch (widget.variant) {
      ButtonVariant.primary => context.colorScheme.primary,
      ButtonVariant.secondary => context.colorScheme.surface,
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
    final isEnabled = !widget.loading && widget.enabled && widget.onTap != null;
    final opacity = widget.loading || isEnabled ? 1.0 : stateLayers.disabled;
    final effectiveDuration = context.motionPolicy.duration(
      motion.buttonPressDuration,
    );

    void activate() {
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
      excludeSemantics: true,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: buttonWidth,
          height: tapTargetHeight,
          child: Center(
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
                    onHighlightChanged: isEnabled ? _handleHighlight : null,
                    customBorder: shape,
                    overlayColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.pressed)) {
                        return foregroundColor.withValues(
                          alpha: stateLayers.pressedOverlay,
                        );
                      }
                      if (states.contains(WidgetState.focused)) {
                        return foregroundColor.withValues(
                          alpha: stateLayers.focusOverlay,
                        );
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return foregroundColor.withValues(
                          alpha: stateLayers.hoverOverlay,
                        );
                      }
                      return colors.transparentSurface;
                    }),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? spacing.lg : spacing.xxl,
                      ),
                      child: Center(
                        child: widget.loading
                            ? GridLoader(
                                colorStyle: GridLoaderColorStyle.custom,
                                color: foregroundColor,
                              )
                            : Row(
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
                                              .copyWith(color: foregroundColor),
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
