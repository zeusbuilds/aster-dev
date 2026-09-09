import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme/tokens/motion_tokens.dart';
import 'toast_message.dart';

part 'toast_controller.g.dart';

/// Owns the app's bounded, deduplicated FIFO toast queue.
@Riverpod(keepAlive: true)
class ToastController extends _$ToastController
    implements ToastPresentationService {
  static const int maximumPendingMessages = 4;
  static const int maximumTitleCharacters = 80;
  static const int maximumMessageCharacters = 240;
  static const Duration maximumVisibleDuration = Duration(seconds: 10);
  static const Duration _readingTimePerWord = Duration(milliseconds: 350);
  static const Duration _readingOrientationTime = Duration(seconds: 1);

  /// A bounded default for visual reading. Assistive navigation is untimed in
  /// ToastHost; this estimate is not used as a screen-reader speech deadline.
  static Duration _readingDuration(String title, String? message) {
    final words = '$title ${message ?? ''}'.trim().split(RegExp(r'\s+')).length;
    final estimate = _readingOrientationTime + _readingTimePerWord * words;
    final minimum = const AsterMotion().toastVisibleDuration;
    if (estimate < minimum) return minimum;
    return estimate > maximumVisibleDuration
        ? maximumVisibleDuration
        : estimate;
  }

  int _nextId = 0;

  @override
  ToastQueueState build() => ToastQueueState();

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) {
    final normalizedTitle = title.trim();
    final normalizedMessage = message?.trim();
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > maximumTitleCharacters ||
        (normalizedMessage?.length ?? 0) > maximumMessageCharacters) {
      return false;
    }

    final candidate = ToastMessage(
      id: _nextId,
      title: normalizedTitle,
      message: normalizedMessage == null || normalizedMessage.isEmpty
          ? null
          : normalizedMessage,
      variant: variant,
      duration:
          duration ?? _readingDuration(normalizedTitle, normalizedMessage),
    );
    if (candidate.duration <= Duration.zero ||
        candidate.duration > maximumVisibleDuration ||
        _contains(candidate)) {
      return false;
    }

    _nextId += 1;
    if (state.current == null) {
      state = ToastQueueState(current: candidate);
      return true;
    }
    if (state.pending.length >= maximumPendingMessages) return false;
    state = state.copyWith(pending: [...state.pending, candidate]);
    return true;
  }

  @override
  void dismissCurrent({int? id}) {
    final current = state.current;
    if (current == null || (id != null && current.id != id)) return;
    if (state.pending.isEmpty) {
      state = ToastQueueState();
      return;
    }
    state = ToastQueueState(
      current: state.pending.first,
      pending: state.pending.skip(1).toList(growable: false),
    );
  }

  bool _contains(ToastMessage candidate) {
    final current = state.current;
    return (current != null && current.hasSameContent(candidate)) ||
        state.pending.any(candidate.hasSameContent);
  }
}
