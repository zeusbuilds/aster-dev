import 'package:flutter/widgets.dart';

import 'haptic_feedback_service.dart';
import 'toast_message.dart';

/// Makes app-owned feedback boundaries available to ordinary presentation
/// widgets while Riverpod retains lifecycle and test-override ownership.
class AsterFeedbackScope extends InheritedWidget {
  const AsterFeedbackScope({
    super.key,
    required this.haptics,
    required this.toasts,
    required super.child,
  });

  final HapticFeedbackService haptics;
  final ToastPresentationService toasts;

  static AsterFeedbackScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AsterFeedbackScope>();
  }

  @override
  bool updateShouldNotify(AsterFeedbackScope oldWidget) {
    return !identical(haptics, oldWidget.haptics) ||
        !identical(toasts, oldWidget.toasts);
  }
}

extension AsterFeedbackContext on BuildContext {
  /// Semantic haptic service, or a no-op during pre-provider bootstrap UI.
  HapticFeedbackService get haptics {
    return AsterFeedbackScope.maybeOf(this)?.haptics ??
        const NoopHapticFeedbackService();
  }

  /// App toast queue. A missing scope is a root-composition error.
  ToastPresentationService get toasts {
    final service = AsterFeedbackScope.maybeOf(this)?.toasts;
    if (service == null) {
      throw FlutterError(
        'Missing AsterFeedbackScope. Compose feature UI below the Aster app '
        'root or provide an explicit scope in widget tests.',
      );
    }
    return service;
  }
}
