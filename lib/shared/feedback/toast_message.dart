import 'package:flutter/foundation.dart';

/// Semantic presentation variants for transient, non-blocking feedback.
enum ToastVariant { success, failure, warning, info }

/// One immutable toast request.
@immutable
final class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.title,
    required this.variant,
    required this.duration,
    this.message,
  });

  /// Monotonic process-local identity used to reject stale dismissal timers.
  final int id;
  final String title;
  final String? message;
  final ToastVariant variant;
  final Duration duration;

  /// Content identity used to deduplicate current and queued messages.
  bool hasSameContent(ToastMessage other) {
    return title == other.title &&
        message == other.message &&
        variant == other.variant;
  }
}

/// Current toast plus the bounded FIFO waiting behind it.
@immutable
final class ToastQueueState {
  ToastQueueState({this.current, List<ToastMessage> pending = const []})
    : pending = List<ToastMessage>.unmodifiable(pending);

  final ToastMessage? current;
  final List<ToastMessage> pending;

  ToastQueueState copyWith({
    Object? current = _unchanged,
    List<ToastMessage>? pending,
  }) {
    return ToastQueueState(
      current: identical(current, _unchanged)
          ? this.current
          : current as ToastMessage?,
      pending: pending ?? this.pending,
    );
  }
}

/// Narrow command interface exposed to non-Riverpod presentation widgets.
abstract interface class ToastPresentationService {
  /// Queues a transient message. Returns false when the request is invalid,
  /// duplicated, or rejected because the bounded queue is full.
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  });

  /// Dismisses the current message, optionally only when its [id] still owns
  /// the presentation slot.
  void dismissCurrent({int? id});
}

const _unchanged = Object();
