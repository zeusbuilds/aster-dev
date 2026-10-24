import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme/tokens/motion_tokens.dart';
import 'toast_message.dart';

part 'toast_controller.g.dart';

/// Owns the app's bounded, deduplicated FIFO toast queue.
@Riverpod(keepAlive: true)
class ToastController extends _$ToastController
    implements OriginScopedToastPresentationService {
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
  int _scopeEpoch = 0;
  int _presentationGeneration = 0;
  Object? _routeScope;
  String? _walletScope;
  bool _hasPresented = false;

  /// Navigation invalidates visible and queued feedback from the old route.
  /// Returning to the same route later never revives an earlier action.
  void updateRouteScope(Object route) {
    if (_routeScope == route) return;
    _routeScope = route;
    _invalidateScope();
  }

  /// Wallet changes invalidate feedback even when the visible route is stable.
  void updateWalletScope(String? walletId) {
    if (_walletScope == walletId) return;
    _walletScope = walletId;
    _invalidateScope();
  }

  void _invalidateScope() {
    _scopeEpoch += 1;
    discardMessagesForPopup();
  }

  /// A popup replaces transient presentation, but does not replace the action
  /// that opened it. Its result can still report feedback after it closes,
  /// provided the original route and wallet remain current.
  void discardMessagesForPopup() {
    _presentationGeneration += 1;
    if (_hasPresented) {
      // Notify even if the last toast is already dismissing: its outgoing
      // animation must not survive into a new route or wallet.
      state = ToastQueueState(scopeGeneration: _presentationGeneration);
    }
  }

  @override
  ToastPresentationService captureOrigin() =>
      _OriginBoundToasts(this, _scopeEpoch);

  bool _ownsOrigin(int epoch) => ref.mounted && epoch == _scopeEpoch;

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
    _hasPresented = true;
    if (state.current == null) {
      state = ToastQueueState(
        current: candidate,
        scopeGeneration: _presentationGeneration,
      );
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
      state = ToastQueueState(scopeGeneration: _presentationGeneration);
      return;
    }
    state = ToastQueueState(
      current: state.pending.first,
      pending: state.pending.skip(1).toList(growable: false),
      scopeGeneration: _presentationGeneration,
    );
  }

  bool _contains(ToastMessage candidate) {
    final current = state.current;
    return (current != null && current.hasSameContent(candidate)) ||
        state.pending.any(candidate.hasSameContent);
  }
}

final class _OriginBoundToasts implements ToastPresentationService {
  const _OriginBoundToasts(this.controller, this.epoch);

  final ToastController controller;
  final int epoch;

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) =>
      controller._ownsOrigin(epoch) &&
      controller.show(
        title: title,
        variant: variant,
        message: message,
        duration: duration,
      );

  @override
  void dismissCurrent({int? id}) {
    if (controller._ownsOrigin(epoch)) controller.dismissCurrent(id: id);
  }
}
