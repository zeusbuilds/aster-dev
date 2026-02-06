import 'package:flutter/material.dart';

import 'package:haptic_feedback/haptic_feedback.dart';

import '../shared.dart';

// TODO: fix button variant colors and also match grid loader variant colors
/// Button variant types
enum ButtonVariant {
  /// Primary button - filled with primary color
  primary,

  /// Secondary button - outlined or filled with surface color
  secondary,

  /// Outlined button - white/transparent background with blue border and black text/icon
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
    final textTheme = context.textTheme;
    final spacing = context.spacing;
    final radius = context.radius;
    final colors = context.colors;

    // Size-specific configurations
    final isCompact = widget._isCompact;
    final height = isCompact ? 40.0 : 48.0;
    final horizontalPadding = isCompact ? spacing.spacing16 : spacing.spacing24;
    // Vertical padding: compact uses 12px, normal uses 12px (closest to original 14px)
    // This gives 24px content area for 48px button, which fits 16px text comfortably
    final verticalPadding = isCompact ? spacing.spacing12 : spacing.spacing12;
    final iconSize = isCompact ? spacing.spacing18 : spacing.spacing20;
    final iconTextGap = isCompact ? spacing.spacing4 : spacing.spacing8;
    final borderRadius = isCompact ? radius.radius24 : radius.radius18;
    final textStyle = isCompact
        ? textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.0,
          )
        : textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.0,
          );

    // Variant-specific colors
    final backgroundColor = widget.variant == ButtonVariant.primary
        ? colors.brand6
        : widget.variant == ButtonVariant.translucent
        ? Colors.white.withValues(alpha: 0.8)
        : colors.fill1;
    final foregroundColor = widget.variant == ButtonVariant.primary
        ? colors.text5
        : widget.variant == ButtonVariant.translucent
        ? colors.text1
        : colors.text1;
    final borderColor = widget.variant == ButtonVariant.secondary
        ? colors.fill1
        : Colors.transparent;
    final borderWidth = widget.variant == ButtonVariant.secondary ? 1.0 : 0.0;

    // Disabled state (disabled if loading, not enabled, or no onTap)
    final isEnabled = !widget.loading && widget.enabled && widget.onTap != null;
    // Keep full opacity when loading, only fade when disabled (not loading)
    final opacity = widget.loading ? 1.0 : (isEnabled ? 1.0 : 0.5);

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
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
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: SizedBox(
            width: widget.width ?? (isCompact ? null : double.infinity),
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
                  ? Center(child: GridLoader())
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
                            style: textStyle?.copyWith(color: foregroundColor),
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
    );
  }
}
