import 'package:flutter/foundation.dart';

import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'haptic_feedback_service.g.dart';

/// Product-level meanings for tactile feedback.
///
/// Widgets request an intent instead of choosing a platform vibration pattern.
/// This keeps interaction semantics consistent and leaves platform mapping at a
/// single, injectable boundary.
enum HapticIntent {
  /// A discrete value or choice changed.
  selection,

  /// A low-impact local action such as copy, reveal, max, or scan capture.
  lightImpact,

  /// A meaningful user commit, before an asynchronous result is known.
  commit,

  /// An asynchronous operation completed successfully.
  success,

  /// An operation reached a meaningful caution state.
  warning,

  /// An operation failed.
  error,
}

/// Emits semantic haptic feedback without participating in action completion.
abstract interface class HapticFeedbackService {
  /// Attempts to emit [intent]. Implementations must fail silently so tactile
  /// feedback can never block or fail the associated user action.
  Future<void> trigger(HapticIntent intent);
}

/// Function used to probe whether the current device supports haptics.
typedef HapticCapabilityProbe = Future<bool> Function();

/// Function used to emit one semantic haptic intent.
typedef HapticEmitter = Future<void> Function(HapticIntent intent);

/// `haptic_feedback` adapter with a process-lifetime capability cache.
final class PlatformHapticFeedbackService implements HapticFeedbackService {
  PlatformHapticFeedbackService({
    HapticCapabilityProbe? capabilityProbe,
    HapticEmitter? emitter,
  }) : _capabilityProbe = capabilityProbe ?? Haptics.canVibrate,
       _emitter = emitter ?? _emitPlatformIntent;

  final HapticCapabilityProbe _capabilityProbe;
  final HapticEmitter _emitter;
  Future<bool>? _supportsHaptics;

  @override
  Future<void> trigger(HapticIntent intent) async {
    try {
      final supported = await (_supportsHaptics ??= _probeSafely());
      if (!supported) return;
      await _emitter(intent);
    } catch (_) {
      // Haptics are optional presentation feedback. Plugin/platform failures
      // must not alter the associated action or surface an error to the user.
    }
  }

  Future<bool> _probeSafely() async {
    try {
      return await _capabilityProbe();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _emitPlatformIntent(HapticIntent intent) {
    final type = switch (intent) {
      HapticIntent.selection => HapticsType.selection,
      HapticIntent.lightImpact => HapticsType.light,
      HapticIntent.commit => HapticsType.medium,
      HapticIntent.success => HapticsType.success,
      HapticIntent.warning => HapticsType.warning,
      HapticIntent.error => HapticsType.error,
    };
    return Haptics.vibrate(type, useAndroidHapticConstants: true);
  }
}

/// Silent implementation used where feedback is intentionally unavailable.
@immutable
final class NoopHapticFeedbackService implements HapticFeedbackService {
  const NoopHapticFeedbackService();

  @override
  Future<void> trigger(HapticIntent intent) => SynchronousFuture<void>(null);
}

/// App-wide haptic boundary. Override this provider in widget and integration
/// tests to verify intent selection without invoking a platform plugin.
@Riverpod(keepAlive: true)
HapticFeedbackService hapticFeedbackService(Ref ref) {
  return PlatformHapticFeedbackService();
}
