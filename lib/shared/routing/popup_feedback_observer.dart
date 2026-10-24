import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Drops feedback belonging to the presentation that a popup replaces.
/// Each Navigator must own a separate observer instance.
final class PopupFeedbackObserver extends NavigatorObserver {
  PopupFeedbackObserver({
    required this.discardMessages,
    required this.isActive,
  });

  final VoidCallback discardMessages;
  final bool Function() isActive;
  bool _scheduled = false;

  void _popupChanged() {
    if (!isActive()) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      discardMessages();
      return;
    }
    // Navigator observers can run while declarative routes are being built.
    // Never mutate a provider from that phase, and coalesce one frame's changes.
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (isActive()) discardMessages();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popupChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popupChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popupChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PopupRoute || oldRoute is PopupRoute) _popupChanged();
  }
}
