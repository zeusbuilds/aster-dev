import 'package:flutter/material.dart';

import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../theme/theme.dart';
import 'squircle.dart';

/// Toast variant types
enum ToastVariant { success, failure, warning }

/// Custom toast widget that appears from the bottom of the screen
///
/// Supports three variants: success, failure, and warning
class CustomToast extends StatelessWidget {
  /// Title text (required)
  final String title;

  /// Message text (optional)
  final String? message;

  /// Toast variant
  final ToastVariant variant;

  const CustomToast({
    super.key,
    required this.title,
    this.message,
    required this.variant,
  });

  /// Get icon for the variant
  IconData _getIcon() {
    switch (variant) {
      case ToastVariant.success:
        return MingCuteIcons.mgc_check_circle_fill;
      case ToastVariant.failure:
        return MingCuteIcons.mgc_close_circle_fill;
      case ToastVariant.warning:
        return MingCuteIcons.mgc_alert_fill;
    }
  }

  /// Get icon color for the variant
  Color _getIconColor(BuildContext context) {
    final colors = context.appColors;
    switch (variant) {
      case ToastVariant.success:
        return colors.success;
      case ToastVariant.failure:
        return colors.danger;
      case ToastVariant.warning:
        return colors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.xxl,
          vertical: spacing.lg,
        ),
        child: Squircle(
          color: context.colorScheme.surface,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.lg,
          ),
          shadows: [context.shadows.raised.first],
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              Icon(
                _getIcon(),
                color: _getIconColor(context),
                size: spacing.xxl,
              ),
              SizedBox(width: spacing.md),
              // Title and message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.colorScheme.onSurface,
                      ),
                    ),
                    if (message != null && message!.isNotEmpty) ...[
                      Text(
                        message!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class to show toast messages
class ToastHelper {
  static OverlayEntry? _currentOverlayEntry;
  static VoidCallback? _currentDismissCallback;
  static Duration? _currentDismissDuration;

  /// Register a dismiss callback for the current toast (internal use)
  static void registerDismissCallback(
    VoidCallback callback,
    Duration duration,
  ) {
    _currentDismissCallback = callback;
    _currentDismissDuration = duration;
  }

  /// Dismiss the current toast if one is showing
  static Future<void> _dismissCurrent() async {
    if (_currentDismissCallback != null) {
      _currentDismissCallback!();
      _currentDismissCallback = null;
      await Future.delayed(
        _currentDismissDuration ?? const AsterMotion().toastTransitionDuration,
      );
    }
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
    }
  }

  /// Show a toast message
  ///
  /// [context] - BuildContext to show the toast
  ///
  /// [title] - Title text (required)
  ///
  /// [message] - Message text (optional)
  ///
  /// [variant] - Toast variant (success, failure, warning)
  ///
  /// [duration] - How long the toast should be visible (default: 3 seconds)
  static Future<void> show(
    BuildContext context, {
    required String title,
    String? message,
    required ToastVariant variant,
    Duration? duration,
  }) async {
    // Dismiss current toast if one is showing
    await _dismissCurrent();

    // Check if context is still mounted after async operation
    if (!context.mounted) return;

    final motion = context.motion;
    final visibleDuration = duration ?? motion.toastVisibleDuration;
    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
        duration: visibleDuration,
        transitionDuration: motion.toastTransitionDuration,
        curve: motion.toastCurve,
        onDismiss: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
          _currentOverlayEntry = null;
          _currentDismissCallback = null;
          _currentDismissDuration = null;
        },
        child: CustomToast(title: title, message: message, variant: variant),
      ),
    );

    _currentOverlayEntry = overlayEntry;
    _currentDismissDuration = motion.toastTransitionDuration;
    overlay.insert(overlayEntry);
  }

  /// Show success toast
  static void showSuccess(
    BuildContext context, {
    required String title,
    String? message,
    Duration? duration,
  }) {
    show(
      context,
      title: title,
      message: message,
      variant: ToastVariant.success,
      duration: duration,
    );
  }

  /// Show failure toast
  static void showFailure(
    BuildContext context, {
    required String title,
    String? message,
    Duration? duration,
  }) {
    show(
      context,
      title: title,
      message: message,
      variant: ToastVariant.failure,
      duration: duration,
    );
  }

  /// Show warning toast
  static void showWarning(
    BuildContext context, {
    required String title,
    String? message,
    Duration? duration,
  }) {
    show(
      context,
      title: title,
      message: message,
      variant: ToastVariant.warning,
      duration: duration,
    );
  }
}

/// Overlay widget that handles the slide animation from bottom
class _ToastOverlay extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration transitionDuration;
  final Curve curve;
  final VoidCallback? onDismiss;

  const _ToastOverlay({
    required this.child,
    required this.duration,
    required this.transitionDuration,
    required this.curve,
    this.onDismiss,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.transitionDuration,
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    // Register dismiss callback with ToastHelper
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ToastHelper.registerDismissCallback(_dismiss, widget.transitionDuration);
    });

    // Start animation
    _controller.forward();

    // Start reverse animation before removing.
    final dismissDelay = widget.duration > widget.transitionDuration
        ? widget.duration - widget.transitionDuration
        : Duration.zero;
    Future.delayed(dismissDelay, () {
      if (mounted && !_isDismissing) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
      ),
    );
  }
}
