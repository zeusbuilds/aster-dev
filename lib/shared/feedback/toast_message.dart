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

  @override
  bool operator ==(Object other) =>
      other is ToastMessage &&
      other.id == id &&
      other.title == title &&
      other.message == message &&
      other.variant == variant &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(id, title, message, variant, duration);
}

/// Current toast plus the bounded FIFO waiting behind it.
@immutable
final class ToastQueueState {
  ToastQueueState({
    this.current,
    List<ToastMessage> pending = const [],
    this.scopeGeneration = 0,
  }) : pending = List<ToastMessage>.unmodifiable(pending);

  final ToastMessage? current;
  final List<ToastMessage> pending;
  final int scopeGeneration;

  ToastQueueState copyWith({
    Object? current = _unchanged,
    List<ToastMessage>? pending,
  }) {
    return ToastQueueState(
      current: identical(current, _unchanged)
          ? this.current
          : current as ToastMessage?,
      pending: pending ?? this.pending,
      scopeGeneration: scopeGeneration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToastQueueState &&
      other.current == current &&
      other.scopeGeneration == scopeGeneration &&
      listEquals(other.pending, pending);

  @override
  int get hashCode =>
      Object.hash(current, Object.hashAll(pending), scopeGeneration);
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

/// Captures the route/wallet generation that owns an asynchronous action.
/// Capture before awaiting; a late result cannot acquire a newer scope.
abstract interface class OriginScopedToastPresentationService
    implements ToastPresentationService {
  ToastPresentationService captureOrigin();
}

const _unchanged = Object();
