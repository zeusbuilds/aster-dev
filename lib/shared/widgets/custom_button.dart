import 'package:flutter/material.dart';

import 'package:haptic_feedback/haptic_feedback.dart';

import '../theme/theme.dart';
import 'grid_loader.dart';
import 'squircle.dart';

/// Button variant types
enum ButtonVariant {
  /// Primary button - filled with primary color
  primary,

  /// Secondary button - outlined or filled with surface color
  secondary,

  /// Translucent button - glassy surface treatment over brand/art backgrounds
  translucent,
}

/// Professional button widget with consistent spacing, typography, and styling
class CustomButton extends StatefulWidget {
  /// Button text label
  final String text;

  /// Optional icon before the text
  final IconData? prefixIcon;

  /// Optional icon after the text
  final IconData? suffixIcon;

  /// Callback when button is tapped
  final VoidCallback? onTap;

  /// Button variant (primary or secondary)
  final ButtonVariant variant;

  /// Whether the button is enabled
  final bool enabled;

  /// Whether the button is in loading state
  final bool loading;

  /// Optional custom width
  final double? width;

  /// Whether this is a compact button
  final bool _isCompact;

  /// Normal size button constructor
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
  }) : _isCompact = false;

  /// Compact size button constructor
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
  }) : _isCompact = true;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radii;
    final colors = context.appColors;
    final metrics = context.metrics;
    final motion = context.motion;
    final icons = context.icons;
    final strokes = context.strokes;
    final stateLayers = context.stateLayers;
    final type = context.type;

    // Size-specific configurations
    final isCompact = widget._isCompact;
    final height = isCompact
        ? metrics.compactButtonHeight
        : metrics.buttonHeight;
    final tapTargetHeight = height < metrics.minTouchTarget
        ? metrics.minTouchTarget
        : height;
    final buttonWidth = widget.width ?? (isCompact ? null : double.infinity);
    final horizontalPadding = isCompact ? spacing.lg : spacing.xxl;
    final verticalPadding = spacing.md;
    final iconSize = icons.sm;
    final iconTextGap = isCompact ? spacing.xs : spacing.sm;
    final borderRadius = radius.button;
    final textStyle = isCompact ? type.compactButtonLabel : type.buttonLabel;

    // Variant-specific colors
    final backgroundColor = widget.variant == ButtonVariant.primary
        ? context.colorScheme.primary
        : widget.variant == ButtonVariant.translucent
        ? context.colorScheme.surface.withValues(
            alpha: stateLayers.translucentSurface,
          )
        : context.colorScheme.surface;
    final foregroundColor = widget.variant == ButtonVariant.primary
        ? context.colorScheme.onPrimary
        : widget.variant == ButtonVariant.translucent
        ? context.colorScheme.onSurface
        : context.colorScheme.onSurface;
    final borderColor = widget.variant == ButtonVariant.secondary
        ? colors.borderSubtle
        : colors.transparentSurface;
    final borderWidth = widget.variant == ButtonVariant.secondary
        ? strokes.border
        : spacing.none;

    // Disabled state (disabled if loading, not enabled, or no onTap)
    final isEnabled = !widget.loading && widget.enabled && widget.onTap != null;
    // Keep full opacity when loading, only fade when disabled (not loading)
    final opacity = widget.loading
        ? 1.0
        : (isEnabled ? 1.0 : stateLayers.disabled);

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.text,
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: isEnabled
              ? (_) async {
                  setState(() {
                    _isPressed = true;
                  });
                  final canVibrate = await Haptics.canVibrate();
                  if (canVibrate) {
                    await Haptics.vibrate(HapticsType.light);
                  }
                }
              : null,
          onTapUp: isEnabled
              ? (_) {
                  setState(() {
                    _isPressed = false;
                  });
                  widget.onTap?.call();
                }
              : null,
          onTapCancel: isEnabled
              ? () {
                  setState(() {
                    _isPressed = false;
                  });
                }
              : null,
          child: SizedBox(
            width: buttonWidth,
            height: tapTargetHeight,
            child: Center(
              child: AnimatedScale(
                scale: _isPressed ? motion.buttonPressedScale : 1.0,
                duration: motion.buttonPressDuration,
                curve: motion.fastEase,
                child: SizedBox(
                  width: buttonWidth,
                  height: height,
                  child: Squircle(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    borderRadius: borderRadius,
                    borderColor: borderColor,
                    borderWidth: borderWidth,
                    color: backgroundColor,
                    child: widget.loading
                        ? Center(
                            child: GridLoader(
                              colorStyle: GridLoaderColorStyle.custom,
                              color: foregroundColor,
                            ),
                          )
                        : Row(
                            mainAxisSize: isCompact
                                ? MainAxisSize.min
                                : MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (widget.prefixIcon != null) ...[
                                Icon(
                                  widget.prefixIcon,
                                  size: iconSize,
                                  color: foregroundColor,
                                ),
                                SizedBox(width: iconTextGap),
                              ],
                              Flexible(
                                child: Text(
                                  widget.text,
                                  style: textStyle.copyWith(
                                    color: foregroundColor,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.suffixIcon != null) ...[
                                SizedBox(width: iconTextGap),
                                Icon(
                                  widget.suffixIcon,
                                  size: iconSize,
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
    );
  }
}
